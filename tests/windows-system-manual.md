# Standalone Windows system collector

Run from the repository directory in **64-bit Windows PowerShell 5.1 or newer**.
The script does not load configuration or query engine status. Standard output
contains the system object only, without the API response envelope.

```powershell
$system = .\engine-system-win.ps1 -ModelsRoot 'C:\ai\engines\Models' -BaseDir 'C:\ai\engines' -OsType windows | ConvertFrom-Json
$system | ConvertTo-Json -Depth 10
$system.collection
```

From WSL (adjust the checkout path):

```bash
powershell.exe -NoProfile -File "$(wslpath -w ./engine-system-win.ps1)" \
  -ModelsRoot /mnt/c/ai/engines/Models -BaseDir /mnt/c/ai/engines -Pretty
```

Parameters are explicit; `base_dir` and `models_root` preserve their supplied
values. `disk.windows_path` shows the translated Windows path. Custom WSL mount
locations must be translated by the caller (for example using `wslpath -w`).

## Checks on the Windows machine

1. Confirm `collection.status` is `success`, or inspect `collection.errors` for
   unavailable providers. Unknown measurements must be null, not invented zeroes.
2. Compare memory with Windows Task Manager, not WSL `/proc/meminfo`.
3. Compare CPU logical processor count and `usage_percent` with Windows. Linux
   load averages remain null; usage is a provider sample, not a 1/5/15-minute load.
4. Compare disk values with the volume containing ModelsRoot. Values use binary
   divisors (MiB/GiB), retaining the legacy MB/GB field names. Test a path containing
   spaces, a missing directory, and a directory on another volume if available.
5. Compare every `gpus` entry's name and dedicated/shared capacities with Task
   Manager. DXGI LUIDs associate counters with adapters; unmatched instances are
   visible in `collection.unmatched_gpu_counters` and never summed into GPU usage.
6. Collect with an Ollama model loaded, unload it, then collect again. Dedicated
   and shared usage should follow Task Manager (allow for sampling delay).
7. Confirm `gpus` remains an array for zero, one, and multiple adapters. `gpu`
   prefers available telemetry, then largest dedicated capacity, then LUID for a
   deterministic tie-breaker. It is not necessarily the adapter an engine uses.
   With two equal-capacity entries, one with unavailable counters, confirm that
   `gpu.metrics_status` is `available` regardless of their enumeration order.
8. Inspect `collection.duration_ms` and `collection.timings_ms` on repeated
   invocations before selecting a dashboard polling interval. External process
   startup and JSON serialization are additional overhead. The timing fields
   separate CIM queries, helper compilation, DXGI enumeration and association.

## Diagnose adapter duplicates and startup cost

Run twice in the same PowerShell session (without starting a new powershell.exe):

```powershell
1..2 | ForEach-Object {
    $system = .\engine-system-win.ps1 -ModelsRoot 'C:\ai\engines\Models' -OsType windows | ConvertFrom-Json
    $system.collection | ConvertTo-Json -Depth 10
}
```

The second invocation reuses compiled helper types. Compare
`dxgi_interop_init_ms` and `disk_interop_init_ms` with their first-run values.
Starting a fresh PowerShell process recompiles the helpers.
The DXGI helper namespace is versioned when its C# contract changes so an older
compiled definition in the same session cannot hide newly added fields. The
first call after such an update recompiles DXGI; the next call reuses it.

`collection.dxgi_adapters` preserves every descriptor, including software adapters
excluded from `gpus`. Inspect `flags_hex`, `is_software`, `subsystem_id`,
`enumeration_index` and `excluded_reason`. Microsoft Basic Render Driver is also
excluded by its vendor/device identity when its software flag is absent; the
fallback reason is explicit. Equal GPU names are never sufficient to deduplicate
two LUIDs. `collection.dxgi_layout` exposes interop layout for verification:
on x64, expected descriptor size is 312 bytes, LUID offset 296, flags offset 304
(on x86: 296, 284, 292 respectively).

An adapter without counters remains in `gpus` with `metrics_status: unavailable`,
null usage and a `collection.warnings` entry. This absence alone does not make
the whole collection fail. Provider failures and ambiguous node associations
remain errors and produce `collection.status: partial`.

`vram_total_mb` and `vram_used_mb` mean dedicated capacity and dedicated usage.
Shared memory is exposed separately and is not added to a claimed allocatable
GPU capacity. `total_committed_bytes` is also distinct from resident usage.

DXGI enumeration uses inline C# interop compiled by Add-Type. If policy blocks
this, the error is recorded; GPU capacities/identity are unknown, while other
sections and raw unmatched memory counters remain available. Multiple physical
nodes for one LUID are left unaggregated until their semantics can be validated.

## Integration through the dispatcher

With `OS_TYPE=wsl` configured in engine.conf, run from the repository in WSL:

```bash
./engine-run.sh status system
./engine-run.sh status engines
./engine-run.sh status
./engine-run.sh status ollama
./engine-run.sh status llama
```

The first returns only `data.system` without querying engine status. The second
returns `data.active_engine` and `data.engines`, including each engine's model
lists, without invoking the system collector. With no selector, the original
complete payload is preserved. Per-engine status commands remain unchanged.
The response envelope retains `action: status` and `engine: all` for all three
global variants. Global responses are pretty-printed and include a top-level
`scope` field (`all`, `system`, or `engines`), including error responses for a
recognized scope. Existing per-engine response envelopes are unchanged.
A collector invocation or JSON validation failure returns an
error response and nonzero exit code; partial metric failures remain recorded
inside `data.system.collection`.

The Linux implementation has been moved to engine-system-lnx.sh without changing
its metric collection logic; it still requires validation on a Linux test host.
