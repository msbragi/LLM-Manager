#!/bin/bash
# UnLoad a model 
# Usage: unload.sh <model_id>

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/ollama-api.sh"

MODEL_ID="$1"

if [ -z "$MODEL_ID" ]; then
    log_msg "ERROR" "No model ID provided"
    json_output "error" "load" "ollama" '{"message":"model_id argument required"}'
    exit $EXIT_ERROR
fi

# Call the API orchestrator
log_msg "INFO" "Unloading model: $MODEL_ID"
ollama_unload_model "$MODEL_ID"
json_output "success" "unload" "ollama" \
    "{\"model\":\"$MODEL_ID\",\"status\":\"unloaded\"}"
exit $EXIT_SUCCESS
