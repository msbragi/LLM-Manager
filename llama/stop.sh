#!/bin/bash
# ============================================================================
# ENGINE STOP - LLAMA
# ============================================================================
# Stop llama-server

# Get script directory and source common utilities
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/llama-api.sh"

echo "→ Stopping llama-server..." >&2

# Stop the process
stop_process "llama-server"

log_msg "OK" "llama-server stopped"
json_output "success" "stop" "llama" '{"state":"stopped"}'

exit $EXIT_SUCCESS
