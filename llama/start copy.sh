#!/bin/bash
# ============================================================================
# ENGINE START - LLAMA
# ============================================================================
# Start llama-server with model
# Usage: start.sh <model_id> [users]
#
# Unlike Ollama, llama-server loads the model at startup

# Get script directory and source common utilities
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/llama-api.sh"

# Parse arguments
MODEL_ID="${1:-}"
USERS="${2:-1}"

if [ -z "$MODEL_ID" ]; then
    log_msg "ERROR" "Model ID required for llama-server"
    json_output "error" "start" "llama" '{"message":"Model ID is required. Usage: start llama <model_id> [users]"}'
    exit $EXIT_ERROR
fi

echo "→ Starting llama-server with model: $MODEL_ID (users: $USERS)..." >&2

# Get model configuration
MODEL_CONFIG=$(get_model_config "$MODEL_ID")
if [ -z "$MODEL_CONFIG" ]; then
    log_msg "ERROR" "Model $MODEL_ID not found in manifest"
    json_output "error" "start" "llama" "{\"message\":\"Model not found in configuration\"}"
    exit $EXIT_NOT_FOUND
fi

# Extract GGUF filename
GGUF_FILENAME=$(echo "$MODEL_CONFIG" | jq -r '.file_name')

# Find GGUF file
GGUF_PATH=$(find_gguf "$GGUF_FILENAME" "$MODELS_ROOT")
if [ -z "$GGUF_PATH" ]; then
    log_msg "ERROR" "GGUF file not found: $GGUF_FILENAME"
    json_output "error" "start" "llama" "{\"message\":\"GGUF file not found: $GGUF_FILENAME\"}"
    exit $EXIT_NOT_FOUND
fi

# Find llama-server binary
BIN_PATH=$(find_binary "llama-server" "$OS_TYPE")
if [ -z "$BIN_PATH" ]; then
    log_msg "ERROR" "llama-server binary not found"
    json_output "error" "start" "llama" "{\"message\":\"Binary not found\"}"
    exit $EXIT_NOT_FOUND
fi

BIN_DIR=$(dirname "$BIN_PATH")
BIN_FILE=$(basename "$BIN_PATH")

echo "→ Binary: $BIN_PATH" >&2

# Get context size from config (default 4096)
CTX_BASE=$(echo "$MODEL_CONFIG" | jq -r '.engines.llama.ctx // .ctx // 4096')
MAX_CTX=$((CTX_BASE * USERS))

echo "→ Context: ${CTX_BASE} x ${USERS} users = ${MAX_CTX}" >&2

# Get GPU layers (default 99 = all)
GPU_LAYERS=$(echo "$MODEL_CONFIG" | jq -r '.engines.llama.n_gpu_layers // 99')

# Check for draft model (optional, for speculative decoding)
DRAFT_PATTERN=$(echo "$MODEL_CONFIG" | jq -r '.engines.llama.draft_pattern // empty')
DRAFT_TOKENS=$(echo "$MODEL_CONFIG" | jq -r '.engines.llama.draft_tokens // 5')

if [ -n "$DRAFT_PATTERN" ]; then
    echo "→ Searching for draft model: $DRAFT_PATTERN" >&2
    DRAFT_PATH=$(find "$MODELS_ROOT" -type f -iname "*${DRAFT_PATTERN}*.gguf" -print -quit 2>/dev/null)
    
    if [ -n "$DRAFT_PATH" ]; then
        echo "→ Found draft model: $DRAFT_PATH" >&2
        USE_DRAFT=true
    else
        echo "→ Draft model not found, continuing without speculative decoding" >&2
        USE_DRAFT=false
    fi
else
    USE_DRAFT=false
fi

# Check for multimodal projector (optional, for vision/multimodal models)
MMPROJ_FILE=$(echo "$MODEL_CONFIG" | jq -r '.common.mmproj_file // empty')
USE_MMPROJ=false
if [ -n "$MMPROJ_FILE" ]; then
    MMPROJ_PATH=$(find_gguf "$MMPROJ_FILE" "$MODELS_ROOT")
    if [ -n "$MMPROJ_PATH" ]; then
        echo "→ Found mmproj: $MMPROJ_PATH" >&2
        USE_MMPROJ=true
    else
        echo "→ mmproj file not found: $MMPROJ_FILE, starting without vision support" >&2
    fi
fi

# Convert paths and prepare arguments
if [ "$OS_TYPE" == "wsl" ]; then
    MODEL_PATH=$(wslpath -w "$GGUF_PATH")
    [ "$USE_DRAFT" = true ] && DRAFT_PATH=$(wslpath -w "$DRAFT_PATH")
    [ "$USE_MMPROJ" = true ] && MMPROJ_PATH=$(wslpath -w "$MMPROJ_PATH")
else
    MODEL_PATH="$GGUF_PATH"
fi

MODEL_ALIAS=$(echo "$MODEL_CONFIG" | jq -r '.model_id')

# Build unified arguments array
ARGS=(
    "--alias", "$MODEL_ALIAS:latest"    
    "--model" "$MODEL_PATH"
    "--host" "0.0.0.0"
    "--port" "$LLAMA_PORT"
    "--ctx-size" "$MAX_CTX"
    "--parallel" "$USERS"
    "--n-gpu-layers" "$GPU_LAYERS"
    "--cont-batching"
)

if [ "$USE_DRAFT" = true ]; then
    ARGS+=("--model-draft" "$DRAFT_PATH" "--draft" "$DRAFT_TOKENS" "--n-gpu-layers-draft" "99")
fi

if [ "$USE_MMPROJ" = true ]; then
    ARGS+=("--mmproj" "$MMPROJ_PATH")
fi

# Start the server
cd "$BIN_DIR"
if [ "$OS_TYPE" == "wsl" ]; then
    log_msg "INFO" "Starting llama-server from WSL via PowerShell..."
    
    # Build PowerShell command string: Quote only if it contains spaces or backslashes, but NOT if it's a flag
    PS_ARGS=""
    for arg in "${ARGS[@]}"; do
        if [[ "$arg" == -* ]]; then
            PS_ARGS="$PS_ARGS $arg"
        elif [[ "$arg" == *" "* ]] || [[ "$arg" == *"\\"* ]]; then
            PS_ARGS="$PS_ARGS \"$arg\""
        else
            PS_ARGS="$PS_ARGS $arg"
        fi
    done
    
    script_file="llama-serve.ps1"
    cat > "$script_file" <<EOFPS
& ".\\$BIN_FILE" $PS_ARGS
exit \$LASTEXITCODE
EOFPS
    powershell.exe -ExecutionPolicy Bypass -File "$script_file" > llama-stdout.log 2> llama-stderr.log &
    START_RESULT=$?
else
    log_msg "INFO" "Starting llama-server natively on Linux..."
    nohup ./"$BIN_FILE" "${ARGS[@]}" > "$BASE_DIR/$LOG_DIR/llama-stdout.log" 2> "$BASE_DIR/$LOG_DIR/llama-stderr.log" &
    START_RESULT=$?
fi

if [ $START_RESULT -ne 0 ]; then
    log_msg "ERROR" "Failed to start llama-server"
    json_output "error" "start" "llama" "{\"message\":\"Failed to execute start command\"}"
    exit $EXIT_ERROR
fi

# Wait for process to start
echo "→ Waiting for server to start..." >&2
sleep 5

# Check if process is running
if ! llama_running; then
    log_msg "ERROR" "llama-server failed to start"
    json_output "error" "start" "llama" "{\"message\":\"Process did not start. Check logs.\"}"
    exit $EXIT_ERROR
fi

log_msg "OK" "llama-server started successfully (PORT: $ENGINE_PORT)"
json_output "success" "start" "llama" "{\"state\":\"running\",\"port\":$ENGINE_PORT,\"message\":\"Server running on port: $ENGINE_PORT.\"}"
exit $EXIT_SUCCESS
