#!/bin/bash
# Start the Ollama server; optionally load a model after startup
# Usage: start.sh [model_id]

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/ollama-api.sh"

MODEL_ID="${1:-}"

# ── Start server ──────────────────────────────────────────────────────────────

ollama_start
if [ $? -ne 0 ]; then
    json_output "error" "start" "ollama" \
        '{"message":"Failed to start Ollama"}'
    exit $EXIT_ERROR
fi
log_msg "SUCCESS" "Ollama running on port $OLLAMA_PORT"

# ── Load model (if requested) ─────────────────────────────────────────────────

if [ -n "$MODEL_ID" ]; then
    "$SCRIPT_DIR/load.sh" "$MODEL_ID"
    rc=$?
    if [ $rc -ne 0 ]; then
        json_output "error" "start" "ollama" \
            "{\"message\":\"Failed to load model: $MODEL_ID\"}"
        exit $rc
    fi
    json_output "success" "start" "ollama" \
        "{\"port\":$OLLAMA_PORT,\"model\":\"$MODEL_ID\"}"
else
    json_output "success" "start" "ollama" \
        "{\"port\":$OLLAMA_PORT,\"model\":null}"
fi
