#!/bin/bash
# ============================================================================
# ENGINE SHOW - LLAMA
# ============================================================================
# Show z model data
# Usage: show.sh <model_id>

# Get script directory and source common utilities
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/llama-api.sh"

# Parse arguments
MODEL_ID="${1:-}"

if [ -z "$MODEL_ID" ]; then
    log_msg "ERROR" "Model ID required"
    json_output "error" "show" "ollama" '{"message":"Model ID is required"}'
    exit $EXIT_ERROR
fi

echo "→ Showing model configuration for: $MODEL_ID" >&2

# Check Llama server running and get PID
if ! llama_running; then
    log_msg "ERROR" "llama-server not started"
    json_output "error" "start" "llama" "{\"message\":\"Process did not start. Check logs.\"}"
    exit $EXIT_ERROR
fi

# Show model via Ollama API library
SHOW_RESPONSE=$(llama_show_model)
SHOW_RESULT=$?

if [ $SHOW_RESULT -ne 0 ]; then
    log_msg "ERROR" "Failed to show model via llama API"
    echo "$SHOW_RESPONSE" # Contains error JSON from llama_api_call
    exit $EXIT_ERROR
fi

log_msg "OK" "Model $MODEL_ID configuration retrieved successfully"
json_output "success" "show" "llama" "{\"model\":\"$MODEL_ID\", \"config\": $(echo "$SHOW_RESPONSE" | jq -c '.')}"

exit $EXIT_SUCCESS
