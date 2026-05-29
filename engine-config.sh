#!/bin/bash
# ============================================================================
# ENGINE CONFIGURATION BUILDER
# ============================================================================
# Returns system configuration: engines, commands, multi-model support
# 
# USAGE:
#   ./engine-run.sh config
#
# OUTPUT:
#   JSON with engines, commands, multi-model support, models registry
# ============================================================================

set -e

# Determine script directory
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Source common utilities
source "$SCRIPT_DIR/engine-common.sh"

# Load configuration
load_config

# ============================================================================
# BUILD CONFIGURATION JSON
# ============================================================================

build_config() {
    local models_file="$SCRIPT_DIR/engine-models.json"
    
    if [ ! -f "$models_file" ]; then
        json_output "error" "config" "system" "{\"message\":\"engine-models.json not found\"}"
        return $EXIT_NOT_FOUND
    fi
    
    # Get engines list (skip dummy engine for production)
    local engines_array=$(echo "$VALID_ENGINES" | tr ' ' '\n' | grep -v "dummy" | jq -R . | jq -s -c .)
    
    # Get list of engines that support multiple models
    local multi_model_engines=$(echo "$MULTI_MODEL_ENGINES" | tr ' ' '\n' | grep -v "dummy" | jq -R . | jq -s -c .)
    
    # Multi-engine support flag
    local multi_engine_support=$(echo "$MULTI_ENGINE_ENABLED")
    
    # Get model registry
    local models_registry=$(jq -c . "$models_file")
    
    # Command syntax from config
    local commands=$COMMAND_SYNTAX
    
    # Build complete configuration response
    local config="{
  \"system\": {
    \"os_type\": \"$OS_TYPE\",
    \"base_dir\": \"$BASE_DIR\",
    \"models_root\": \"$MODELS_ROOT\",
    \"log_dir\": \"$LOG_DIR\"
  },
  \"engines\": $engines_array,
  \"engines_multi_model\": $multi_model_engines,
  \"multi_engine\": $multi_engine_support,
  \"models\": $models_registry,
  \"commands\": $commands
}"
    
    json_output "success" "config" "system" "$config"
    return $EXIT_SUCCESS
}

# ============================================================================
# MAIN
# ============================================================================

log_msg "INFO" "Building system configuration"

build_config
