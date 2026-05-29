#!/bin/bash
# Ollama Engine Status Script
# Provides status information for the Ollama engine in JSON format

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/llama-api.sh"

models_loaded="[]"
models_running="[]"

# Get current timestamp in ISO 8601 format
timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

log_msg "INFO" "Check if llama is running"

# Check if Ollama is running
if llama_running; then
    state="running"
    port_status="listening"

    log_msg "INFO" "Retrieve all models in registry"
    models_loaded=$(llama_list_models | jq)

    log_msg "INFO" "Retrieve all running models"
    models_running=$(llama_running_models | jq)
else
    state="stopped"
    port_status="not_listening"
fi

# Output JSON status
json_output "success" "status" "llama" \
    "{\"state\":\"$state\",\"port_status\":\"$port_status\",\"port\":$LLAMA_PORT,\"models_loaded\":$models_loaded,\"models_running\":$models_running}"
exit $EXIT_SUCCESS