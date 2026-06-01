#!/bin/bash
# ============================================================================
# ENGINE HF MODULE
# ============================================================================
# Hugging Face model management - single consolidated script
# Usage: ./engine-hf.sh <command> [args...]
# ============================================================================

set -e

# Determine script directory
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Source common utilities
source "$SCRIPT_DIR/engine-common.sh"

# Load configuration
load_config

# ============================================================================
# FUNCTIONS
# ============================================================================

# Show help message (separata funzione)
show_help() {
    cat <<EOF
Engine HF Module v2.0 (curl/wget)
Hugging Face model management for AI Engine (no CLI required)

USAGE:
    engine-hf.sh <command> [args...]

COMMANDS:
    download <model_id> [output_dir] [branch]    Download model from Hugging Face
    list [query] [limit] [format]                List models on Hugging Face
    delete <model_name>                          Remove model from local storage
    sync                                         Update engine-models.json manifest

OPTIONS:
    -h, --help               Show this help message

LIST FORMAT (optional, default: table):
    table      Nicely formatted table with aligned columns (recommended)
    compact    One-liner per model with separators
    json       Raw JSON output

EXAMPLES:
    engine-hf.sh download meta-llama/Llama-3.2-1B
    engine-hf.sh download Qwen/Qwen2.5-7B-Instruct ./custom_models main
    engine-hf.sh list "llama" 20
    engine-hf.sh list "llama" 20 table
    engine-hf.sh list "" 100 compact
    engine-hf.sh list "qwen" 50 json
    engine-hf.sh delete Llama-3.2-1B
    engine-hf.sh sync

REQUIREMENTS:
    curl                     For API calls and downloads
    wget (optional)          Preferred for large files (resume capability)
    jq (optional)            For JSON formatting
    column (optional)        For better table formatting

ENVIRONMENT:
    MODELS_ROOT              Base directory for model storage (from config)

EOF
}

# Get list of files in HF model using API
hf_get_file_list() {
    local model_name="$1"
    local branch="${2:-main}"
    
    local api_url="https://huggingface.co/api/models/$model_name/tree/$branch"
    
    # Fetch file list from HF API
    curl -s "$api_url" | jq -r '.[] | select(.type=="file") | .path' 2>/dev/null
}

# Download a single file from HF using direct URL
hf_download_file() {
    local model_name="$1"
    local file_path="$2"
    local output_dir="$3"
    local branch="${4:-main}"
    
    local file_name=$(basename "$file_path")
    local output_file="$output_dir/$file_name"
    
    # Construct direct download URL
    local download_url="https://huggingface.co/$model_name/resolve/$branch/$file_path"
    
    log_msg "INFO" "Downloading $file_name..."
    
    # Use wget with resume capability (preferred for large files)
    if command -v wget &> /dev/null; then
        wget -c -q --show-progress \
            -O "$output_file" \
            "$download_url" 2>&1
    # Fallback to curl
    elif command -v curl &> /dev/null; then
        curl -L -C - -o "$output_file" \
            -# "$download_url" 2>&1
    else
        log_msg "ERROR" "Neither wget nor curl found"
        return $EXIT_ERROR
    fi
    
    if [ $? -eq 0 ]; then
        log_msg "SUCCESS" "✓ $file_name"
        return $EXIT_SUCCESS
    else
        log_msg "ERROR" "Failed to download $file_name"
        return $EXIT_ERROR
    fi
}

# Download model from Hugging Face
hf_download() {
    local model_name="$1"
    shift
    local output_dir="${1:-$MODELS_ROOT}"
    local branch="${2:-main}"
    
    # Create output directory
    mkdir -p "$output_dir"
    
    # Extract model name from full path if provided
    local clean_name
    if [[ "$model_name" == *"/"* ]]; then
        clean_name="${model_name##*/}"
    else
        clean_name="$model_name"
    fi
    
    local model_path="$output_dir/$clean_name"
    mkdir -p "$model_path"
    
    log_msg "INFO" "Downloading $model_name to $model_path..."
    
    # Check if curl is available
    if ! command -v curl &> /dev/null; then
        log_msg "ERROR" "curl not found. Install with: sudo apt install curl"
        return $EXIT_ERROR
    fi
    
    # Get file list from HF API
    log_msg "INFO" "Fetching file list from Hugging Face..."
    local files
    files=$(hf_get_file_list "$model_name" "$branch")
    
    if [ -z "$files" ]; then
        log_msg "ERROR" "Failed to fetch file list. Model not found or API error"
        return $EXIT_ERROR
    fi
    
    # Download each file
    local file_count=0
    local success_count=0
    
    while IFS= read -r file_path; do
        [ -z "$file_path" ] && continue
        ((file_count++))
        
        if hf_download_file "$model_name" "$file_path" "$model_path" "$branch"; then
            ((success_count++))
        fi
    done <<< "$files"
    
    log_msg "SUCCESS" "Model downloaded: $success_count/$file_count files"
    
    if [ "$success_count" -eq "$file_count" ]; then
        return $EXIT_SUCCESS
    else
        return $EXIT_ERROR
    fi
}

# List models on Hugging Face
hf_list() {
    local query="${1:-}"
    local limit="${2:-50}"
    local format="${3:-table}"  # table, compact, json
    
    log_msg "INFO" "Fetching models from Hugging Face..."
    
    # Check if curl is available
    if ! command -v curl &> /dev/null; then
        log_msg "ERROR" "curl not found. Install with: sudo apt install curl"
        return $EXIT_ERROR
    fi
    
    # Check if jq is available for JSON parsing
    if ! command -v jq &> /dev/null; then
        log_msg "WARN" "jq not found. Output will be raw JSON. Install with: sudo apt install jq"
        PLAIN_JSON=true
    fi
    
    # Build API URL with query parameters
    local api_url="https://huggingface.co/api/models?limit=$limit"
    [ -n "$query" ] && api_url="$api_url&search=$query"
    
    # Fetch models from HF API
    local response
    response=$(curl -s "$api_url")
    
    if [ -z "$response" ]; then
        log_msg "ERROR" "Failed to fetch models from Hugging Face API"
        return $EXIT_ERROR
    fi
    
    # Parse and format output
    if [ "$PLAIN_JSON" = true ] || [ "$format" = "json" ]; then
        echo "$response"
    elif [ "$format" = "compact" ]; then
        # Compact one-liner format
        echo "$response" | jq -r '.[] | "\(.id) | ⭐ \(.likes // 0) | ↓ \(.downloads // 0)"' 2>/dev/null
    else
        # Table format (default) - just model IDs, clean and simple
        echo "$response" | jq -r '.[] | .id' 2>/dev/null
    fi
    
    return $EXIT_SUCCESS
}

# Delete model from local storage
hf_delete() {
    local model_name="$1"
    
    # Extract model name from full path if provided
    local clean_name
    if [[ "$model_name" == *"/"* ]]; then
        clean_name="${model_name##*/}"
    else
        clean_name="$model_name"
    fi
    
    local model_path="$MODELS_ROOT/$clean_name"
    
    if [ ! -d "$model_path" ]; then
        log_msg "WARN" "Model not found: $model_path"
        return $EXIT_NOT_FOUND
    fi
    
    log_msg "WARN" "Deleting model: $model_path"
    rm -rf "$model_path"
    
    log_msg "SUCCESS" "Model deleted successfully"
    return $EXIT_SUCCESS
}

# Sync model manifest
hf_sync() {
    local manifest_file="$SCRIPT_DIR/engine-models.json"
    
    if [ ! -f "$manifest_file" ]; then
        log_msg "ERROR" "Manifest file not found: $manifest_file"
        return $EXIT_NOT_FOUND
    fi
    
    log_msg "INFO" "Syncing model manifest..."
    
    # Get list of downloaded models
    local models_list
    models_list=$(find "$MODELS_ROOT" -maxdepth 1 -type d -name "*" -exec basename {} \; 2>/dev/null | grep -v "^$\|^engine-models.json")
    
    if [ -z "$models_list" ]; then
        log_msg "WARN" "No models found in $MODELS_ROOT"
        return $EXIT_ERROR
    fi
    
    echo "$models_list" | while read model; do
        log_msg "INFO" "Found model: $model"
    done
    
    return $EXIT_SUCCESS
}

# ============================================================================
# MAIN
# ============================================================================

echo "=== Engine HF Module v2.0 (curl/wget) ===" >&2

# Parse arguments
if [ $# -lt 1 ]; then
    show_help
    exit $EXIT_ERROR
fi

COMMAND="$1"
shift

echo "→ HF Command: $COMMAND" >&2

# Execute command
case "$COMMAND" in
    "download")
        # Validate model name
        if [ -z "$1" ]; then
            log_msg "ERROR" "Model name required for download"
            show_help
            exit $EXIT_ERROR
        fi
        hf_download "$1" "$@"
        exit $?
        ;;
    "list")
        hf_list "$@"
        exit $?
        ;;
    "delete")
        # Validate model name
        if [ -z "$1" ]; then
            log_msg "ERROR" "Model name required for delete"
            show_help
            exit $EXIT_ERROR
        fi
        hf_delete "$1" "$@"
        exit $?
        ;;
    "sync")
        hf_sync "$@"
        exit $?
        ;;
    "help"|"-h"|"--help")
        show_help
        exit $EXIT_SUCCESS
        ;;
    *)
        log_msg "ERROR" "Unknown command: $COMMAND"
        show_help
        exit $EXIT_ERROR
        ;;
esac