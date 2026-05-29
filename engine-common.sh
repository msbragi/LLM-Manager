#!/bin/bash
# ============================================================================
# COMMON UTILITIES - ENGINE FRAMEWORK
# ============================================================================
# Shared functions for all engine management scripts
# Handles: config loading, JSON output, logging, OS detection, system info
# ============================================================================

# Prevent double-sourcing
if [ -n "$ENGINE_COMMON_LOADED" ]; then
    return 0
fi
ENGINE_COMMON_LOADED=true

# Determine script directory (where engine-common.sh is located)
COMMON_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ============================================================================
# LOGGING & OUTPUT
# ============================================================================

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Log message to stderr with optional color
log_msg() {
    local level="$1"
    local message="$2"
    local color=""
    
    case "$level" in
        "ERROR")   color=$RED ;;
        "SUCCESS") color=$GREEN ;;
        "WARN")    color=$YELLOW ;;
        "INFO")    color=$BLUE ;;
        *)         color=$NC ;;
    esac
    
    echo -e "${color}→ [$level] ${message}${NC}" >&2
}

# Output JSON response with consistent schema
# Args: status, action, engine, data
json_output() {
    local status="$1"
    local action="$2"
    local engine="$3"
    local data="$4"
    
    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    
    # data should be valid JSON object or string
    [ -z "$data" ] && data="{}"
    
    cat <<EOF
{
  "timestamp": "$timestamp",
  "status": "$status",
  "action": "$action",
  "engine": "$engine",
  "data": $data
}
EOF
}

# ============================================================================
# CONFIGURATION MANAGEMENT
# ============================================================================

# Load configuration from engine.conf
load_config() {
    local config_file="$COMMON_DIR/engine.conf"
    
    if [ ! -f "$config_file" ]; then
        log_msg "ERROR" "Configuration file not found: $config_file"
        return 1
    fi
    
    # Source the configuration file
    source "$config_file"
    
    # Verify critical variables are set
    if [ -z "$OS_TYPE" ] || [ -z "$BASE_DIR" ] || [ -z "$VALID_ENGINES" ]; then
        log_msg "ERROR" "Configuration incomplete: OS_TYPE, BASE_DIR, or VALID_ENGINES not set"
        return 1
    fi

    # On WSL, ensure Windows System32 tools (powershell.exe, taskkill.exe …) are in PATH
    if [ "$OS_TYPE" = "wsl" ]; then
        local win_sys32="${WIN_DIR}/System32"
        local win_ps="${WIN_DIR}/System32/WindowsPowerShell/v1.0"
        [[ ":$PATH:" != *":$win_sys32:"* ]] && export PATH="$PATH:$win_sys32"
        [[ ":$PATH:" != *":$win_ps:"* ]]    && export PATH="$PATH:$win_ps"
    fi

    log_msg "INFO" "Configuration loaded (OS: $OS_TYPE)"
    return 0
}

# ============================================================================
# OS & ENVIRONMENT DETECTION
# ============================================================================

# Detect operating system type
detect_os() {
    if grep -qi "microsoft" /proc/version 2>/dev/null; then
        echo "wsl"
    elif [ "$(uname -s)" = "Linux" ]; then
        echo "linux"
    else
        echo "unknown"
    fi
}

# Initialize OS_TYPE if not already set
if [ -z "$OS_TYPE" ]; then
    OS_TYPE=$(detect_os)
fi

# Get the appropriate API host based on OS type
get_api_host() {
    case "$OS_TYPE" in
        "wsl")
            # Windows host is the default route gateway, not the DNS nameserver
            ip route show default 2>/dev/null | awk '{print $3; exit}'
            ;;
        *)
            echo "localhost"
            ;;
    esac
}

# ============================================================================
# FILE & BINARY UTILITIES
# ============================================================================

# Find a binary in the system or BASE_DIR
find_binary() {
    local binary="$1"

    # Try PATH first (works for both linux native and wsl .exe in PATH)
    if command -v "$binary" &>/dev/null; then
        command -v "$binary"
        return 0
    fi

    # Search BASE_DIR — on WSL also try .exe suffix
    local names=("$binary")
    [ "$OS_TYPE" = "wsl" ] && names+=("${binary}.exe")

    local name found
    for name in "${names[@]}"; do
        found=$(find "$BASE_DIR" -type f -name "$name" -executable 2>/dev/null | head -1)
        if [ -n "$found" ]; then
            echo "$found"
            return 0
        fi
    done

    log_msg "WARN" "Binary not found: $binary"
    return 1
}

# Find GGUF model files matching pattern
find_gguf() {
    local pattern="$1"
    local search_dir="${2:-$MODELS_ROOT}"
    
    if [ ! -d "$search_dir" ]; then
        return 1
    fi
    
    find "$search_dir" -type f -name "$pattern" 2>/dev/null | head -1
}

# ============================================================================
# PROCESS MANAGEMENT
# ============================================================================

# Check if a process is running by name
is_process_running() {
    local process_name="$1"
    
    case "$OS_TYPE" in
        "wsl")
            # Use tasklist on Windows via WSL
            tasklist.exe 2>/dev/null | grep -qi "$process_name" && return 0
            ;;
        "linux"|*)
            # Use pgrep on Linux
            pgrep -f "$process_name" >/dev/null 2>&1 && return 0
            ;;
    esac
    
    return 1
}

# Stop/kill a process by name
stop_process() {
    local process_name="$1"
    
    case "$OS_TYPE" in
        "wsl")
            # Use taskkill on Windows
            taskkill.exe /IM "$process_name.exe" /F >/dev/null 2>&1
            ;;
        "linux"|*)
            # Use pkill on Linux
            pkill -f "$process_name" >/dev/null 2>&1
            ;;
    esac
    
    return 0
}

# ============================================================================
# JSON & DATA UTILITIES
# ============================================================================

# Read model configuration from engine-models.json
get_model_config() {
    local model_id="$1"
    local config_file="$COMMON_DIR/engine-models.json"
    
    if [ ! -f "$config_file" ]; then
        return 1
    fi
    
    jq ".[] | select(.model_id == \"$model_id\")" "$config_file" 2>/dev/null
}

# Returns the prompt template string for a given model family
get_family_template() {
    local family="$1"
    local template_file="$COMMON_DIR/engine-templates.json"
    [ ! -f "$template_file" ] && return 1
    jq -r ".\"$family\".template // empty" "$template_file" 2>/dev/null
}

# Returns newline-separated stop tokens for a given model family
get_family_stops() {
    local family="$1"
    local template_file="$COMMON_DIR/engine-templates.json"
    [ ! -f "$template_file" ] && return 1
    jq -r ".\"$family\".stops[]? // empty" "$template_file" 2>/dev/null
}

# Extract a specific field from model config
get_model_field() {
    local model_id="$1"
    local field="$2"
    
    get_model_config "$model_id" | jq -r ".$field // empty" 2>/dev/null
}

# ============================================================================
# INITIALIZATION
# ============================================================================

# Initialize critical directories
init_directories() {
    local dirs=(
        "$BASE_DIR"
        "$MODELS_ROOT"
        "$LOG_DIR"
    )
    
    for dir in "${dirs[@]}"; do
        if [ -n "$dir" ] && [ ! -d "$dir" ]; then
            mkdir -p "$dir" || {
                log_msg "ERROR" "Failed to create directory: $dir"
                return 1
            }
        fi
    done
    
    return 0
}

log_msg "INFO" "Common utilities loaded"
