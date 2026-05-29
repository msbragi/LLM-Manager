#!/bin/bash
# ============================================================================
# SYSTEM INFORMATION MODULE
# Functions to gather system metrics (RAM, GPU, Disk)
# ============================================================================

# ============================================================================
# MEMORY INFORMATION
# ============================================================================

get_memory_info() {
    local mem_total=0
    local mem_available=0
    local mem_used=0
    local mem_unit="MB"
    
    # Read from /proc/meminfo (KB values)
    if [ -f /proc/meminfo ]; then
        mem_total=$(grep "MemTotal:" /proc/meminfo | awk '{print int($2/1024)}')
        mem_available=$(grep "MemAvailable:" /proc/meminfo | awk '{print int($2/1024)}')
        mem_used=$((mem_total - mem_available))
    fi
    
    echo "{\"total_mb\":$mem_total,\"available_mb\":$mem_available,\"used_mb\":$mem_used,\"unit\":\"$mem_unit\"}"
}

# ============================================================================
# GPU INFORMATION (AMD ROCm)
# ============================================================================

get_gpu_info() {
    local gpu_detected=false
    local gpu_name="unknown"
    local vram_total=0
    local vram_used=0
    local vram_unit="MB"
    
    # Check for ROCm
    if command -v rocm-smi &> /dev/null; then
        gpu_detected=true
        
        # Get GPU name (first GPU)
        gpu_name=$(rocm-smi --showproductname 2>/dev/null | grep "GPU" | head -1 | awk -F': ' '{print $2}' || echo "AMD GPU")
        
        # Get VRAM info (parse rocm-smi output)
        local vram_info=$(rocm-smi --showmeminfo vram 2>/dev/null | grep "GPU" | head -1)
        if [ -n "$vram_info" ]; then
            # Extract used and total VRAM (values are in MB)
            vram_used=$(echo "$vram_info" | awk '{print $3}' | sed 's/[^0-9]//g')
            vram_total=$(echo "$vram_info" | awk '{print $5}' | sed 's/[^0-9]//g')
        fi
    elif [ -n "$HSA_OVERRIDE_GFX_VERSION" ]; then
        # HSA variable set, assume AMD GPU present
        gpu_detected=true
        gpu_name="AMD GPU (ROCm)"
    fi

    # Se siamo in WSL e la GPU non è stata ancora rilevata (es. da rocm-smi)
    # Nota: ! $gpu_detected esegue il contenuto della variabile come comando
    if [ "$OS_TYPE" = "wsl" ] && ! $gpu_detected; then
        # Usiamo Get-CimInstance e un cast [long] per evitare overflow della RAM su GPU potenti
        # tr -d '\r' è fondamentale per pulire l'output Windows per Bash
        gpu_info=$(powershell.exe -NoProfile -Command "Get-CimInstance Win32_VideoController | Select-Object -First 1 Name, @{Name='AdapterRAM'; Expression={[long]\$_.AdapterRAM}} | ConvertTo-Json" 2>/dev/null | tr -d '\r')

        if [ -n "$gpu_info" ] && [ "$gpu_info" != "null" ]; then
            gpu_detected=true
            gpu_name=$(echo "$gpu_info" | jq -r '.Name')
            
            # Recupero VRAM gestendo il caso null di jq
            vram_raw=$(echo "$gpu_info" | jq -r '.AdapterRAM // 0')
            
            # Conversione da Bytes a MB (Bash gestisce solo interi, il cast [long] lato PS aiuta)
            vram_total=$((vram_raw / 1024 / 1024)) 
            
            # Se il valore è negativo (bug comune WMI), lo normalizziamo (es. 4GB unsigned)
            if [ "$vram_total" -lt 0 ]; then
                vram_total=$(( (vram_raw + 4294967296) / 1024 / 1024 ))
            fi
        fi
    fi

    echo "{\"detected\":$gpu_detected,\"name\":\"$gpu_name\",\"vram_total_mb\":${vram_total:-0},\"vram_used_mb\":${vram_used:-0},\"vram_unit\":\"$vram_unit\"}"
}

# ============================================================================
# DISK SPACE (MODELS_ROOT)
# ============================================================================

get_disk_space() {
    local disk_total=0
    local disk_used=0
    local disk_available=0
    local disk_unit="GB"
    local models_path="$MODELS_ROOT"
    
    if [ -d "$models_path" ]; then
        # Use df to get disk space in GB
        local df_output=$(df -BG "$models_path" 2>/dev/null | tail -1)
        if [ -n "$df_output" ]; then
            disk_total=$(echo "$df_output" | awk '{print $2}' | sed 's/G//')
            disk_used=$(echo "$df_output" | awk '{print $3}' | sed 's/G//')
            disk_available=$(echo "$df_output" | awk '{print $4}' | sed 's/G//')
        fi
    fi
    
    echo "{\"total_gb\":${disk_total:-0},\"used_gb\":${disk_used:-0},\"available_gb\":${disk_available:-0},\"unit\":\"$disk_unit\",\"path\":\"$models_path\"}"
}

# ============================================================================
# CPU INFORMATION
# ============================================================================

get_cpu_info() {
    local cpu_cores=0
    local cpu_load_1m=0
    local cpu_load_5m=0
    local cpu_load_15m=0
    
    # Get number of CPU cores
    if [ -f /proc/cpuinfo ]; then
        cpu_cores=$(grep -c "^processor" /proc/cpuinfo)
    fi
    
    # Get load average
    if [ -f /proc/loadavg ]; then
        read cpu_load_1m cpu_load_5m cpu_load_15m _ _ < /proc/loadavg
    fi
    
    echo "{\"cores\":${cpu_cores:-0},\"load_1m\":${cpu_load_1m:-0},\"load_5m\":${cpu_load_5m:-0},\"load_15m\":${cpu_load_15m:-0}}"
}

# ============================================================================
# AGGREGATE SYSTEM INFO
# ============================================================================

get_system_info() {
    echo "→ Gathering system information..." >&2
    
    local memory_json=$(get_memory_info)
    local gpu_json=$(get_gpu_info)
    local disk_json=$(get_disk_space)
    local cpu_json=$(get_cpu_info)
    
    # Build system JSON
    local system_json=$(cat <<EOF
{
    "os_type": "$OS_TYPE",
    "api_host": "$API_HOST",
    "base_dir": "$BASE_DIR",
    "models_root": "$MODELS_ROOT",
    "memory": $memory_json,
    "gpu": $gpu_json,
    "disk": $disk_json,
    "cpu": $cpu_json
}
EOF
)
    
    echo "$system_json" | jq -c '.'
}
