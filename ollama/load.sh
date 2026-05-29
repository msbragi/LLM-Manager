#!/bin/bash
# Load a model into Ollama (provision and warmup)
# Usage: load.sh <model_id>

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/ollama-api.sh"

MODEL_ID="$1"
MODEL_USER="${2:-1}"

if [ -z "$MODEL_ID" ]; then
    log_msg "ERROR" "No model ID provided"
    json_output "error" "load" "ollama" '{"message":"model_id argument required"}'
    exit $EXIT_ERROR
fi

# Call the API orchestrator
ollama_load_model "$MODEL_ID" "$MODEL_USER"
rc=$?

if [ $rc -eq $EXIT_NOT_FOUND ]; then
    json_output "error" "load" "ollama" \
        "{\"model\":\"$MODEL_ID\",\"message\":\"Model not found in manifest\"}"
    exit $EXIT_NOT_FOUND
elif [ $rc -ne 0 ]; then
    json_output "error" "load" "ollama" \
        "{\"model\":\"$MODEL_ID\",\"message\":\"Failed to load model\"}"
    exit $EXIT_ERROR
fi

json_output "success" "load" "ollama" \
    "{\"model\":\"$MODEL_ID\",\"status\":\"loaded\"}"
exit $EXIT_SUCCESS
