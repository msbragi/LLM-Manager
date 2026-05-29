#!/bin/bash
# ============================================================================
# ENGINE GLOBAL STATUS
# ============================================================================
# Aggregates status across all engines and system information
#
# USAGE:
#   ./engine-run.sh status
#
# OUTPUT:
#   JSON with system info, all engines status, loaded models, active engine
# ============================================================================

# Determine script directory
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Source common utilities
source "$SCRIPT_DIR/engine-common.sh"

# Load configuration
load_config

# ============================================================================
# GLOBAL STATUS - ALL ENGINES
# ============================================================================

global_status() {
    local engines_data="{"
    local first=true
    local active_engine=""

    log_msg "INFO" "Checking all engines status"

    # Loop through valid engines (skip dummy)
    for engine in $VALID_ENGINES; do
        # Skip test engines
        [ "$engine" = "dummy" ] && continue

        # Check if status script exists
        local status_script="$SCRIPT_DIR/$engine/status.sh"
        if [ ! -f "$status_script" ]; then
            log_msg "WARN" "Skipping $engine (no status script)"
            continue
        fi

        # Execute status script and capture JSON output
        log_msg "INFO" "Querying $engine"
        local status_output=$(bash "$status_script" 2>/dev/null)

        if echo "$status_output" | jq empty 2>/dev/null; then
            local engine_data=$(echo "$status_output" | jq -c '.data // {}')
            # Add engines data to result
            if [ "$first" = false ]; then
                active_engine+="," 
                engines_data+="," 
            fi 
            engines_data+="\"$engine\":$engine_data"
            active_engine+="$engine"
            first=false
        else
            log_msg "ERROR" "Invalid JSON from $engine/status.sh"
        fi
    done

    engines_data+="}"

    # Gather system information using engine-system.sh
    local system_data=$(source "$SCRIPT_DIR/engine-system.sh" && get_system_info)
    # update api_host
    local api_host=$(get_api_host)
    system_data=$(echo "$system_data" | jq --arg api_host "$api_host" '.api_host = $api_host')

    # Build final JSON
    local result=$(echo "{\"system\":$system_data,\"active_engine\":\"$active_engine\",\"engines\":$engines_data}" | jq)

    json_output "success" "status" "all" "$result"

    return $EXIT_SUCCESS
}

# ============================================================================
# MAIN
# ============================================================================

global_status