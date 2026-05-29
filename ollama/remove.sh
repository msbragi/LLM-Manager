#!/bin/bash
# Remove a model from ollama registry
# Usage: remove.sh <model_id>

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/ollama-api.sh"

MODEL_ID="$1"

if [ -z "$MODEL_ID" ]; then
    log_msg "ERROR" "No model ID provided"
    json_output "error" "remove" "ollama" '{"message":"model_id argument required"}'
    exit $EXIT_ERROR
fi

# Call the API orchestrator
log_msg "INFO" "Remove model from registry: $MODEL_ID"
ollama_remove_model "$MODEL_ID"
rc=$?

if [ $rc -ne 0 ]; then
    json_output "error" "remove" "ollama" \
        "{\"model\":\"$MODEL_ID\",\"message\":\"Failed to remove model\"}"
    exit $EXIT_ERROR
fi

json_output "success" "remove" "ollama" \
    "{\"model\":\"$MODEL_ID\",\"status\":\"removed\"}"
exit $EXIT_SUCCESS
