#!/bin/bash
# ============================================================================
# ENGINE GLOBAL STATUS
# ============================================================================
# Aggregates status across all engines and system information
#
# USAGE:
#   ./engine-run.sh status [system|engines]
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

# Keep the common envelope and add the requested scope only for global status.
status_response() {
    local response_status="$1" scope="$2" data="$3"
    json_output "$response_status" "status" "all" "$data" |
        jq --arg scope "$scope" '{timestamp, status, action, scope: $scope, engine, data}'
}

global_status() {
    local section="${1:-all}"
    case "$section" in
        all|system|engines) ;;
        *)
            status_response "error" "$section" '{"message":"Invalid status section. Use system or engines, or omit for all."}'
            return "$EXIT_ERROR"
            ;;
    esac
    local api_host
    if ! api_host=$(get_api_host); then
        status_response "error" "$section" '{"message":"Cannot resolve API host. Check WSL_NAT and the default gateway."}'
        return "$EXIT_ERROR"
    fi

    local engines_data="{"
    local first=true
    local active_engine=""

    if [ "$section" != system ]; then
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

    fi
    engines_data+="}"

    local result='{}' system_data
    if [ "$section" != engines ]; then
        source "$SCRIPT_DIR/engine-system.sh"
        # Resolve the host once and pass it to the collector as well as the payload.
        local API_HOST="$api_host"
        if ! system_data=$(get_system_info) || ! printf '%s\n' "$system_data" | jq -e 'type == "object"' >/dev/null 2>&1; then
            status_response "error" "$section" '{"message":"System information collection failed."}'
            return "$EXIT_ERROR"
        fi
        result=$(jq -cn --argjson system "$system_data" '{system: $system}')
    fi
    if [ "$section" != system ]; then
        result=$(jq -cn --argjson data "$result" --arg active "$active_engine" \
            --argjson engines "$engines_data" '$data + {active_engine: $active, engines: $engines}')
    fi

    status_response "success" "$section" "$result"

    return $EXIT_SUCCESS
}

# ============================================================================
# MAIN
# ============================================================================

global_status "$@"
