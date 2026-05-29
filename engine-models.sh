#!/bin/bash
# ============================================================================
# ENGINE MODELS LISTING
# ============================================================================
# List available models from configuration
# Supports filtering by engine and human-readable output
# 
# USAGE:
#   ./engine-run.sh models [engine] [-h|--human]
#
# OPTIONS:
#   engine          Optional: filter by specific engine
#   -h, --human     Human-readable table format (instead of JSON)
#
# OUTPUT:
#   JSON array of models (default) or formatted table (-h flag)
# ============================================================================

set -e

# Determine script directory  
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Source common utilities
source "$SCRIPT_DIR/engine-common.sh"

# Load configuration
load_config

# ============================================================================
# LIST AVAILABLE MODELS
# ============================================================================

list_models() {
    local engine_filter=""
    local human_readable=false

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--human)
                human_readable=true
                shift
                ;;
            *)
                # Assume it's the engine name if not a flag
                if [ -z "$engine_filter" ]; then
                    engine_filter="$1"
                fi
                shift
                ;;
        esac
    done
    
    local models_file="$SCRIPT_DIR/engine-models.json"
    
    if [ ! -f "$models_file" ]; then
        log_msg "ERROR" "Models file not found: $models_file"
        json_output "error" "models" "system" "{\"message\":\"engine-models.json not found\"}"
        return $EXIT_NOT_FOUND
    fi
    
    # Build jq filter
    local jq_filter='.[]'
    if [ -n "$engine_filter" ]; then
        jq_filter=".[] | select(.engines.${engine_filter} != null)"
    fi
    
    # Human-readable table output
    if [ "$human_readable" = true ]; then
        local title="AVAILABLE MODELS"
        [ -n "$engine_filter" ] && title="MODELS FOR ${engine_filter^^}"
        
        echo "" >&2
        echo "═══════════════════════════════════════════════════════════════════════════════════" >&2
        echo "  $title" >&2
        echo "───────────────────────────────────────────────────────────────────────────────────" >&2
        printf "  %-12s | %-20s | %-35s\n" "ENGINES" "MODEL_ID" "FILE" >&2
        echo "───────────────────────────────────────────────────────────────────────────────────" >&2
        
        jq -r "${jq_filter} | (.engines | keys | join(\",\")) + \"|\" + .model_id + \"|\" + .file_name" "$models_file" 2>/dev/null | \
            while IFS='|' read -r engines id file; do
                if [ -n "$id" ]; then
                    printf "  %-12s | %-20s | %-35s\n" "$engines" "$id" "$file" >&2
                fi
            done
        
        echo "═══════════════════════════════════════════════════════════════════════════════════" >&2
        echo "" >&2
        return $EXIT_SUCCESS
    fi
    
    # JSON output (default)
    local filter_info="{}"
    if [ -n "$engine_filter" ]; then
        filter_info="{\"engine\":\"${engine_filter}\"}"
    fi
    
    # Build models array with key fields
    local models_list=$(jq -c "[${jq_filter} | {
        model_id: .model_id,
        display_name: .display_name,
        family: .family,
        file_name: .file_name,
        base_ctx: .base_ctx,
        engines: .engines | keys
    }]" "$models_file" 2>/dev/null)
    
    if [ -z "$models_list" ] || [ "$models_list" = "null" ]; then
        models_list="[]"
    fi
    
    local result="{\"filter\":${filter_info},\"models\":$models_list,\"count\":$(echo "$models_list" | jq 'length')}"
    
    json_output "success" "models" "system" "$result"
    return $EXIT_SUCCESS
}

# ============================================================================
# MAIN
# ============================================================================

# Only log if there's a real filter (not just -h flag)
if [ -z "$1" ]; then
    log_msg "INFO" "Listing all available models"
elif [ "$1" != "-h" ] && [ "$1" != "--human" ]; then
    log_msg "INFO" "Listing models for engine: $1"
else
    log_msg "INFO" "Listing all available models (human-readable)"
fi

list_models "$@"
