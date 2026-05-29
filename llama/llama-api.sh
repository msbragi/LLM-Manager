#!/bin/bash
# ============================================================================
# Llama.cpp API LIBRARY
# ============================================================================

# Get script directory and source common utilities
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../engine-common.sh"
load_config
API_HOST=$(get_api_host)

llama_api_call() {
    local endpoint="$1"
    local method="${2:-GET}"
    local payload="${3:-}"
    local url="http://${API_HOST}:${LLAMA_PORT}${endpoint}"

    if [ "$method" = "GET" ]; then
        curl -s --connect-timeout 3 "$url"
    else
        curl -s -X "$method" -H "Content-Type: application/json" --connect-timeout 3 "$url" -d "$payload"
    fi
}

llama_running() {
    local response
    response=$(curl -f -s -S --connect-timeout 3 --max-time 10 "http://${API_HOST}:${LLAMA_PORT}/props" 2>&1)
    
    if [ $? -ne 0 ]; then
        return 1
    fi
    
    # Verify response contains expected llama.cpp property
    echo "$response" | jq -e "has(\"${LLAMA_HEALTH_CHECK}\")" >/dev/null 2>&1
    return $?
}

# Lists all models available in Llama.cpp (names only, as JSON array).
llama_list_models() {
    # Backward compatible: returns array of model names only
    local raw=$(llama_api_call "/v1/models" "GET")
    echo "$raw" | jq -c '[.models[]?.name // empty]' 2>/dev/null
}

# New: returns full JSON from /api/tags
llama_list_models_full() {
    llama_api_call "/v1/models" "GET"
}

# Lists all running models in Llama.cpp (names only, as JSON array).
llama_running_models() {
    local raw=$(llama_api_call "/props" "GET")
    echo "$raw" | jq -c '[.model_alias // empty]' 2>/dev/null
}

# Shows detailed configuration for a model.
llama_show_model() {
    local model_id="$1"
    llama_api_call "/props" "GET"
}

