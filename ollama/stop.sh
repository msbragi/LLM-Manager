#!/bin/bash
# Stop the Ollama server gracefully
# Usage: stop.sh

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/ollama-api.sh"

# ── Stop server ────────────────────────────────────────────────────────────────

ollama_stop
rc=$?

if [ $rc -ne 0 ]; then
    json_output "error" "stop" "ollama" \
        '{"message":"Failed to stop Ollama"}'
    exit $EXIT_ERROR
fi

# Verify it stopped
attempts=0
while [ $attempts -lt 5 ] && ollama_running; do
    sleep 1; (( attempts++ ))
done

if ollama_running; then
    json_output "error" "stop" "ollama" \
        '{"message":"Ollama did not stop gracefully"}'
    exit $EXIT_ERROR
fi

log_msg "SUCCESS" "Ollama stopped"
json_output "success" "stop" "ollama" \
    '{"status":"stopped"}'
