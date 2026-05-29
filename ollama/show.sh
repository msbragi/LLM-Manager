#!/bin/bash
# Ollama Engine show model information

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/ollama-api.sh"

MODEL_ID="${1:-}"

if [ -z "$MODEL_ID" ]; then
    json_output "error" "show" "ollama" \
        '{"message":"Model id is required"}'
    exit $EXIT_ERROR
fi

if ! ollama_running; then
    json_output "error" "show" "ollama" \
        '{"message":"Failed to start Ollama"}'
    exit $EXIT_ERROR
fi

# Get current timestamp in ISO 8601 format
timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

model_info=$(ollama_show_model $MODEL_ID | jq)

# Output model info
json_output "success" "show" "ollama" \
    "{\"model\":\"$MODEL_ID\",\"info\":\"$model_info\"}"
exit $EXIT_SUCCESS