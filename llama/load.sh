#!/bin/bash
# ============================================================================
# ENGINE LOAD - LLAMA
# ============================================================================
# Load a new model (stop + start with model path)

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/llama-api.sh"

MODEL_ID="$1"
if [ -z "$MODEL_ID" ]; then
    log_msg "ERROR" "Model id required"
    json_output "error" "load" "llama" '{"message":"Model id is required"}'
    exit $EXIT_ERROR
fi

"$SCRIPT_DIR/stop.sh"
EXIT_CODE=$?
if [ $EXIT_CODE -eq 0 ]; then
    "$SCRIPT_DIR/start.sh" $@
    EXIT_CODE=$?
fi
