#requires -Version 5.1
<#
.SYNOPSIS
Collect Windows host metrics as a standalone JSON object (the contents of data.system).
.DESCRIPTION
Does not read engine.conf or contact inference engines. Paths may use Windows syntax
or the standard /mnt/<drive>/ WSL syntax. Output is JSON only; collection failures
are recorded in collection.errors and unknown measurements are null.
#>
[CmdletBinding()]
param(
    [string] $ModelsRoot = '',
    [string] $BaseDir = '',
    [string] $ApiHost = '127.0.0.1',
    [ValidateSet('wsl', 'windows')][string] $OsType = 'wsl',
    [switch] $Pretty
)

$ErrorActionPreference = 'Stop'
$collectionErrors = [System.Collections.Generic.List[object]]::new()
$started = [System.Diagnostics.Stopwatch]::StartNew()
$timings = [ordered]@{}
$collectionWarnings = [System.Collections.Generic.List[object]]::new()
$adapterDiagnostics = @()

function Add-CollectionError([string] $Section, [string] $Message) {
    $collectionErrors.Add([ordered]@{ section = $Section; message = $Message })
}

function Convert-ToWindowsPath([string] $Value) {
    if ($Value -match '^/mnt/([a-zA-Z])(?:/|$)(.*)') {
        return $Matches[1].ToUpperInvariant() + ':\' + $Matches[2].Replace('/', '\')
    }
    if ($Value.StartsWith('/')) {
        throw 'Use a Windows path or a standard /mnt/<drive>/ path.'
    }
    return $Value
}

function Convert-ToMiB($Value) {
    if ($null -eq $Value) { return $null }
    return [math]::Round(([double]$Value / 1MB), 2)
}

# Minimal DXGI interop: enumerate hardware adapters, their LUIDs and capacities.
# No QueryVideoMemoryInfo: its usage and budget refer to the calling process.
# Increment this helper namespace when changing its C# contract: Add-Type types
# cannot be replaced in a running Windows PowerShell session.
function Initialize-Dxgi {
    if ('EngineSystemDxgiV2.Dxgi' -as [type]) { return }
    Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
namespace EngineSystemDxgiV2 {
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    public struct AdapterDesc {
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)] public string Description;
        public uint VendorId, DeviceId, SubSysId, Revision;
        public UIntPtr DedicatedVideoMemory, DedicatedSystemMemory, SharedSystemMemory;
        public uint LuidLow;
        public int LuidHigh;
        public uint Flags;
    }
    public class Adapter {
        public string Name, Luid;
        public uint VendorId, DeviceId, Flags, SubSysId, Revision, EnumerationIndex;
        public ulong Dedicated, DedicatedSystem, Shared;
    }
    public static class Dxgi {
        [DllImport("dxgi.dll", ExactSpelling = true)]
        static extern int CreateDXGIFactory1(ref Guid iid, out IntPtr factory);
        [UnmanagedFunctionPointer(CallingConvention.StdCall)]
        delegate int EnumAdapters1(IntPtr self, uint index, out IntPtr adapter);
        [UnmanagedFunctionPointer(CallingConvention.StdCall)]
        delegate int GetDesc1(IntPtr self, out AdapterDesc desc);
        static Delegate Method(IntPtr obj, int slot, Type type) {
            IntPtr table = Marshal.ReadIntPtr(obj);
            return Marshal.GetDelegateForFunctionPointer(
                Marshal.ReadIntPtr(table, slot * IntPtr.Size), type);
        }
        public static Adapter[] Read() {
            Guid iid = new Guid("770aae78-f26f-4dba-a829-253c83d1b387");
            IntPtr factory;
            Marshal.ThrowExceptionForHR(CreateDXGIFactory1(ref iid, out factory));
            var result = new List<Adapter>();
            try {
                var enumerate = (EnumAdapters1)Method(factory, 12, typeof(EnumAdapters1));
                for (uint i = 0; ; i++) {
                    IntPtr adapter;
                    int hr = enumerate(factory, i, out adapter);
                    if (hr == unchecked((int)0x887A0002)) break; // DXGI_ERROR_NOT_FOUND
                    Marshal.ThrowExceptionForHR(hr);
                    try {
                        AdapterDesc desc;
                        Marshal.ThrowExceptionForHR(((GetDesc1)Method(adapter, 10, typeof(GetDesc1)))(adapter, out desc));
                        // Preserve all descriptors for diagnostics; filter in PowerShell.
                        result.Add(new Adapter {
                            Name = desc.Description,
                            Luid = String.Format("luid_0x{0:X8}_0x{1:X8}", unchecked((uint)desc.LuidHigh), desc.LuidLow),
                            VendorId = desc.VendorId, DeviceId = desc.DeviceId,
                            Flags = desc.Flags, SubSysId = desc.SubSysId,
                            Revision = desc.Revision, EnumerationIndex = i,
                            Dedicated = desc.DedicatedVideoMemory.ToUInt64(),
                            DedicatedSystem = desc.DedicatedSystemMemory.ToUInt64(),
                            Shared = desc.SharedSystemMemory.ToUInt64()
                        });
                    } finally { Marshal.Release(adapter); }
                }
            } finally { Marshal.Release(factory); }
            return result.ToArray();
        }
    }
}
'@
}

$sectionTimer = [System.Diagnostics.Stopwatch]::StartNew()
$memory = [ordered]@{ total_mb = $null; available_mb = $null; used_mb = $null; unit = 'MB'; source = 'windows_cim' }
try {
    $os = Get-CimInstance Win32_OperatingSystem
    $memory.total_mb = Convert-ToMiB ([double]$os.TotalVisibleMemorySize * 1024)
    $memory.available_mb = Convert-ToMiB ([double]$os.FreePhysicalMemory * 1024)
    $memory.used_mb = Convert-ToMiB (([double]$os.TotalVisibleMemorySize - [double]$os.FreePhysicalMemory) * 1024)
} catch { Add-CollectionError 'memory' $_.Exception.Message }
$timings.memory_cim_ms = $sectionTimer.ElapsedMilliseconds
$sectionTimer.Restart()

$cpu = [ordered]@{ cores = $null; load_1m = $null; load_5m = $null; load_15m = $null; usage_percent = $null; source = 'windows_cim' }
try {
    $processors = @(Get-CimInstance Win32_Processor)
    $cpu.cores = [int](($processors | Measure-Object NumberOfLogicalProcessors -Sum).Sum)
    $cpu.name = (($processors | ForEach-Object { $_.Name.Trim() }) -join ', ')
    $timings.cpu_inventory_cim_ms = $sectionTimer.ElapsedMilliseconds
    $sectionTimer.Restart()
    $load = Get-CimInstance Win32_PerfFormattedData_PerfOS_Processor -Filter "Name='_Total'"
    if ($null -ne $load) { $cpu.usage_percent = [double]$load.PercentProcessorTime }
} catch { Add-CollectionError 'cpu' $_.Exception.Message }
$timings.cpu_usage_cim_ms = $sectionTimer.ElapsedMilliseconds
$sectionTimer.Restart()

$disk = [ordered]@{ total_gb = $null; used_gb = $null; available_gb = $null; unit = 'GB'; path = $ModelsRoot; windows_path = $null; source = 'windows_volume' }
try {
    if ([string]::IsNullOrWhiteSpace($ModelsRoot)) { throw 'ModelsRoot was not supplied.' }
    $windowsPath = Convert-ToWindowsPath $ModelsRoot
    if (-not [System.IO.Path]::IsPathRooted($windowsPath)) { throw 'ModelsRoot must be an absolute path.' }
    $disk.windows_path = $windowsPath
    # GetDiskFreeSpaceEx follows mounted folders and supports UNC paths. Require
    # an existing directory so the volume is never silently guessed.
    if (-not [System.IO.Directory]::Exists($windowsPath)) { throw 'ModelsRoot is not an accessible Windows directory.' }
    $timings.disk_path_ms = $sectionTimer.ElapsedMilliseconds
    $sectionTimer.Restart()
    if (-not ('EngineSystem.Disk' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
namespace EngineSystem {
    public static class Disk {
        [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        public static extern bool GetDiskFreeSpaceEx(string path, out ulong available, out ulong total, out ulong free);
    }
}
'@
    }
    $timings.disk_interop_init_ms = $sectionTimer.ElapsedMilliseconds
    $sectionTimer.Restart()
    [uint64]$available = 0; [uint64]$total = 0; [uint64]$free = 0
    if (-not [EngineSystem.Disk]::GetDiskFreeSpaceEx($windowsPath, [ref]$available, [ref]$total, [ref]$free)) {
        throw [System.ComponentModel.Win32Exception]::new([Runtime.InteropServices.Marshal]::GetLastWin32Error())
    }
    $disk.total_gb = [math]::Round($total / 1GB, 2)
    $disk.available_gb = [math]::Round($available / 1GB, 2)
    $disk.used_gb = [math]::Round(($total - $free) / 1GB, 2)
} catch { Add-CollectionError 'disk' $_.Exception.Message }
$timings.disk_query_ms = $sectionTimer.ElapsedMilliseconds
$sectionTimer.Restart()

$adapters = @()
$counters = @()
$inventoryKnown = $false
try {
    Initialize-Dxgi
    $timings.dxgi_interop_init_ms = $sectionTimer.ElapsedMilliseconds
    $sectionTimer.Restart()
    $adapters = @([EngineSystemDxgiV2.Dxgi]::Read())
    $inventoryKnown = $true
} catch { Add-CollectionError 'gpu_inventory' $_.Exception.Message }
$timings.dxgi_enumeration_ms = $sectionTimer.ElapsedMilliseconds
$sectionTimer.Restart()
try {
    $counters = @(Get-CimInstance Win32_PerfFormattedData_GPUPerformanceCounters_GPUAdapterMemory)
} catch { Add-CollectionError 'gpu_metrics' $_.Exception.Message }
$timings.gpu_counters_cim_ms = $sectionTimer.ElapsedMilliseconds
$sectionTimer.Restart()

# Keep every enumerated descriptor visible, including filtered software/remote
# adapters. Equal names/vendor IDs do not establish physical-device identity.
$adapterDiagnostics = @(foreach ($adapter in $adapters) {
    $softwareFlag = ($adapter.Flags -band 2) -ne 0
    $remoteFlag = ($adapter.Flags -band 1) -ne 0
    # Basic Render is Microsoft's software rasterizer. Retain the identity-based
    # fallback explicitly in diagnostics when the software flag is absent.
    $basicRender = $adapter.VendorId -eq 0x1414 -and $adapter.DeviceId -eq 0x008C
    $reason = $null
    if ($softwareFlag) { $reason = 'software_flag' }
    elseif ($basicRender) { $reason = 'basic_render_identity' }
    # REMOTE is reserved in DXGI_ADAPTER_FLAG; expose it without using it to
    # discard an adapter. Only identified software adapters are filtered.
    [ordered]@{
        id = $adapter.Luid
        name = $adapter.Name
        enumeration_index = $adapter.EnumerationIndex
        flags = $adapter.Flags
        flags_hex = ('0x{0:X8}' -f $adapter.Flags)
        is_software = $softwareFlag
        is_remote = $remoteFlag
        vendor_id = ('0x{0:X4}' -f $adapter.VendorId)
        device_id = ('0x{0:X4}' -f $adapter.DeviceId)
        subsystem_id = ('0x{0:X8}' -f $adapter.SubSysId)
        revision = $adapter.Revision
        excluded_reason = $reason
    }
})
$excludedLuids = @{}
foreach ($descriptor in $adapterDiagnostics) {
    if ($null -ne $descriptor.excluded_reason) { $excludedLuids[$descriptor.id] = $true }
}

$matchedCounters = @{}
$gpus = @(foreach ($adapter in $adapters) {
    if ($excludedLuids.ContainsKey($adapter.Luid)) { continue }
    # Counter names include the DXGI LUID and a physical-node suffix. Never join
    # by enumeration order or add unrelated (possibly stale) counter instances.
    $matchesForAdapter = @($counters | Where-Object {
        $_.Name -match ('^' + [regex]::Escape($adapter.Luid) + '_phys_\d+$')
    })
    $metricsStatus = 'unavailable'
    $dedicatedUsed = $null; $sharedUsed = $null; $committed = $null
    if ($matchesForAdapter.Count -eq 1) {
        $metricsStatus = 'available'
        $counter = $matchesForAdapter[0]
        $matchedCounters[$counter.Name] = $true
        $dedicatedUsed = $counter.DedicatedUsage
        $sharedUsed = $counter.SharedUsage
        $committed = $counter.TotalCommitted
    } elseif ($matchesForAdapter.Count -gt 1) {
        Add-CollectionError 'gpu_metrics' ("Multiple physical nodes for {0}; usage left unknown." -f $adapter.Luid)
    } else {
        $collectionWarnings.Add([ordered]@{
            section = 'gpu_metrics'; id = $adapter.Luid
            message = 'No memory counter; adapter retained with unknown usage.'
        })
    }
    [ordered]@{
        detected = $true
        id = $adapter.Luid
        name = $adapter.Name
        vendor_id = ('0x{0:X4}' -f $adapter.VendorId)
        device_id = ('0x{0:X4}' -f $adapter.DeviceId)
        vram_total_mb = Convert-ToMiB $adapter.Dedicated
        vram_used_mb = Convert-ToMiB $dedicatedUsed
        vram_unit = 'MB'
        dedicated_total_bytes = $adapter.Dedicated
        dedicated_system_bytes = $adapter.DedicatedSystem
        dedicated_used_bytes = $dedicatedUsed
        shared_limit_bytes = $adapter.Shared
        shared_used_bytes = $sharedUsed
        total_committed_bytes = $committed
        inventory_source = 'dxgi'
        metrics_source = 'windows_gpu_adapter_memory'
        metrics_status = $metricsStatus
    }
})

# Keep the legacy singular object. Prefer telemetry availability, then dedicated
# capacity, with LUID as a deterministic tie-breaker. Use dictionary access in
# calculated sort expressions: these entries are OrderedDictionary objects.
# This is a display default, not a claim about the engine's selection.
$primaryGpu = $null
if ($gpus.Count -gt 0) {
    $primaryGpu = $gpus | Sort-Object -Property @(
        @{ Expression = { $_['metrics_status'] -eq 'available' }; Descending = $true }
        @{ Expression = { $_['dedicated_total_bytes'] }; Descending = $true }
        @{ Expression = { $_['id'] }; Descending = $false }
    ) | Select-Object -First 1
} else {
    $detected = $null
    if ($inventoryKnown) { $detected = $false }
    $primaryGpu = [ordered]@{ detected = $detected; name = $null; vram_total_mb = $null; vram_used_mb = $null; vram_unit = 'MB' }
}

$timings.gpu_association_ms = $sectionTimer.ElapsedMilliseconds
$started.Stop()
$result = [ordered]@{
    os_type = $OsType
    api_host = $ApiHost
    base_dir = $BaseDir
    models_root = $ModelsRoot
    memory = $memory
    gpu = $primaryGpu
    gpus = @($gpus)
    disk = $disk
    cpu = $cpu
    collection = [ordered]@{
        source = 'windows'
        collected_at = [DateTime]::UtcNow.ToString('o')
        duration_ms = $started.ElapsedMilliseconds
        timings_ms = $timings
        warnings = @($collectionWarnings.ToArray())
        dxgi_adapters = @($adapterDiagnostics)
        dxgi_layout = $(if ('EngineSystemDxgiV2.AdapterDesc' -as [type]) {
            [ordered]@{
                pointer_size = [IntPtr]::Size
                descriptor_size = [Runtime.InteropServices.Marshal]::SizeOf([type][EngineSystemDxgiV2.AdapterDesc])
                luid_offset = [Runtime.InteropServices.Marshal]::OffsetOf([type][EngineSystemDxgiV2.AdapterDesc], 'LuidLow').ToInt32()
                flags_offset = [Runtime.InteropServices.Marshal]::OffsetOf([type][EngineSystemDxgiV2.AdapterDesc], 'Flags').ToInt32()
            }
        } else { $null })
        status = $(if ($collectionErrors.Count -eq 0) { 'success' } else { 'partial' })
        errors = @($collectionErrors.ToArray())
        # Expose unassociated instances for diagnostics without treating them as
        # extra physical GPUs or including them in the primary GPU's usage.
        unmatched_gpu_counters = @($counters | Where-Object { -not $matchedCounters.ContainsKey($_.Name) } |
            Select-Object Name, DedicatedUsage, SharedUsage, TotalCommitted)
    }
}
if ($Pretty) { $result | ConvertTo-Json -Depth 10 }
else { $result | ConvertTo-Json -Depth 10 -Compress }
