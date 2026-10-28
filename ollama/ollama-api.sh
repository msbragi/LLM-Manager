#!/bin/bash
# Ollama API library — source this file from engine scripts; requires engine-common.sh and load_config()

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../engine-common.sh"
load_config
API_HOST=$(get_api_host) || exit "$EXIT_ERROR"

# Low-level REST call to /api/<endpoint>; returns raw curl output
ollama_api_call() {
    local endpoint="$1" method="${2:-GET}" payload="${3:-}"
    local url="http://${API_HOST}:${OLLAMA_PORT}/api/${endpoint}"
    if [ "$method" = "GET" ]; then
        curl -s --connect-timeout 3 "$url"
    else
        curl -s -X "$method" -H "Content-Type: application/json" --connect-timeout 3 "$url" -d "$payload"
    fi
}

# Returns 0 if Ollama is responding, 1 otherwise
ollama_running() {
    if curl -f -s --connect-timeout 3 --max-time 5 "http://${API_HOST}:${OLLAMA_PORT}" 2>/dev/null \
        | grep -qi "$OLLAMA_HEALTH_CHECK"; then
        return 0  # True: Ollama is running
    else
        return 1  # False: Ollama is not running
    fi
}

# Sends a no-op generate request to warm up the model in memory
ollama_preload_model() {
    local model_ref="$1"
    local max_users="${2:-1}"
    local model_config="$3"

    # Estrae il contesto base usando jq con fallback a 4096
    local num_ctx=$(echo "$model_config" | jq -r '.engines.ollama.base_ctx // .base_ctx // 4096')
    local max_ctx=$((num_ctx * max_users))

    # Genera il payload JSON in modo sicuro con jq (senza prompt per un vero no-op preload)
    local payload=$(jq -n \
        --arg model "$model_ref" \
        --argjson ctx "$max_ctx" \
        '{model: $model, stream: false, options: {num_ctx: $ctx}}')

    ollama_api_call "generate" "POST" "$payload" > /dev/null
}

# Returns JSON array of all model names in the local Ollama registry
ollama_list_models() {
    ollama_api_call "tags" "GET" | jq -c '[.models[]?.name // empty]' 2>/dev/null
}

# Returns full JSON response from /api/tags (names + metadata)
ollama_list_models_full() {
    ollama_api_call "tags" "GET"
}

# Returns JSON array of currently loaded (running) model names
ollama_running_models() {
    ollama_api_call "ps" "GET" | jq -c '[.models[]?.name // empty]' 2>/dev/null
}

# Removes a model from the Ollama registry
ollama_remove_model() {
    local payload="{\"model\":\"$1\"}"
    ollama_api_call "delete" "DELETE" "$payload"
}

# Returns full model details JSON from /api/show
ollama_show_model() {
    ollama_api_call "show" "POST" "{\"model\":\"$1\"}"
}

# Copies (renames) a model within the Ollama registry
ollama_copy_model() {
    ollama_api_call "copy" "POST" "{\"source\":\"$1\", \"destination\":\"$2\"}"
}

# Runs an ollama CLI action (serve, pull, cp, rm, create …) on the correct OS
ollama_execute() {
    local action="$1"; shift
    local bin_path log_file

    bin_path=$(find_binary "ollama")
    [ -z "$bin_path" ] && { log_msg "ERROR" "ollama binary not found"; return $EXIT_NOT_FOUND; }

    local log_file="$LOG_DIR/ollama.log"
    log_msg "INFO" "ollama $action $* → $bin_path"

    if [ "$OS_TYPE" = "wsl" ]; then
        local ps1_args=(
            -ExecutionPolicy Bypass
            -File "$(wslpath -w "$SCRIPT_DIR/ollama-win.ps1")"
            -Action "$action"
            -BinPath "$(wslpath -w "$bin_path")"
            -OllamaHost "${OLLAMA_BIND}:${OLLAMA_PORT}"
            -ModelsDir "$(wslpath -w "$MODELS_ROOT")"
        )
        
        [ $# -gt 0 ] && ps1_args+=(-Params "$*")
        
        #log_msg "DEBUG" "PowerShell arguments: ${ps1_args[*]}"

	case "$action" in
	  "stop")
            	bin_path="$(wslpath -w "$bin_path")"
                powershell.exe -Command "& '$bin_path' stop" 2>/dev/null
		;;
	  "serve")
          	powershell.exe "${ps1_args[@]}" >> "$log_file" 2>&1 &
		;;
	  *)
          	powershell.exe "${ps1_args[@]}" >> "$log_file" 2>&1
		;;
	esac

    else
        OLLAMA_HOST="${OLLAMA_BIND}:${OLLAMA_PORT}" 
        OLLAMA_MODELS="$MODELS_ROOT" 
        OLLAMA_KEEP_ALIVE="30m"
        OLLAMA_ORIGINS="*" 
	case "$action" in
	  "stop")
            	"$bin_path" "stop" >> "$log_file" 2>&1 
		;;
	  "serve")
            	nohup "$bin_path" "$action" "$@" >> "$log_file" 2>&1 &
		;;
	  *)
            	nohup "$bin_path" "$action" "$@" >> "$log_file" 2>&1
		;;
	esac
    fi
}

# Starts the Ollama server; returns 0 if running (or already running)
ollama_start() {
    if ollama_running; then
        log_msg "INFO" "Ollama already running"
        return 0
    fi
    ollama_execute "serve"
    local rc=$? 
    attempts=0
    while [ $attempts -lt 10 ] && ! ollama_running; do
        sleep 1; (( attempts++ ))
    done
    ollama_running
    return $?
}

ollama_stop() {
    if ! ollama_running; then
        log_msg "INFO" "Ollama not running"
        return 0
    fi
    log_msg "INFO" "Stopping Ollama"

    ollama_execute "stop"
    local rc=$?
    
    # Wait a moment for graceful shutdown
    sleep 1
    
    # Termina il server d'inferenza (llama-server) se il comando stop avesse fallito
    stop_process "llama-server"

    if ollama_running; then
        log_msg "WARN" "Ollama still running, forcing kill"
	stop_process "ollama"
    fi
    
    ollama_running
    return $? 
}

# Builds a Modelfile string for the given model_id using engine-models.json and engine-templates.json
ollama_create_modelfile() {
    local model_id="$1"
    local model_config family gguf_path mmproj_path template stops

    model_config=$(get_model_config "$model_id")
    [ -z "$model_config" ] && return $EXIT_NOT_FOUND

    local gguf_file; gguf_file=$(echo "$model_config" | jq -r '.file_name')
    gguf_path=$(find_gguf "$gguf_file" "$MODELS_ROOT")
    [ -z "$gguf_path" ] && return $EXIT_NOT_FOUND
    [ "$OS_TYPE" = "wsl" ] && gguf_path=$(wslpath -w "$gguf_path")

    local modelfile="FROM $gguf_path"

    local mmproj_file; mmproj_file=$(echo "$model_config" | jq -r '.engines.ollama.mmproj_file // empty')
    if [ -n "$mmproj_file" ]; then
        mmproj_path=$(find_gguf "$mmproj_file" "$MODELS_ROOT")
        if [ -n "$mmproj_path" ]; then
            [ "$OS_TYPE" = "wsl" ] && mmproj_path=$(wslpath -w "$mmproj_path")
            modelfile+=$'\n'"FROM $mmproj_path"
        fi
    fi

    family=$(echo "$model_config" | jq -r '.family')
    local template_str stops_str
    template_str=$(get_family_template "$family")
    stops_str=$(get_family_stops "$family")

    [ -n "$template_str" ] && modelfile+=$'\n'"TEMPLATE \"\"\"${template_str}\"\"\""
    [ -n "$stops_str" ] && while IFS= read -r tok; do
        modelfile+=$'\n'"PARAMETER stop \"${tok}\""
    done <<< "$stops_str"

    echo "$modelfile"
}

# Creates an Ollama model from a Modelfile string; cleans up temp file on exit
ollama_create_model() {
    local model_id="$1" modelfile_content="$2"
    local bin_path bin_dir modelfile_path

    bin_path=$(find_binary "ollama")
    [ -z "$bin_path" ] && return $EXIT_NOT_FOUND

    bin_dir=$(dirname "$bin_path")
    modelfile_path="$bin_dir/Modelfile-${model_id}"
    echo "$modelfile_content" > "$modelfile_path"

    w_path=$(wslpath -m "$modelfile_path")
    ollama_execute "create" "$model_id" "-f" "$w_path"
    local rc=$?
    rm -f "$modelfile_path"
    return $rc
}

# Pulls a model by tag; optionally renames it to <alias> after pulling
ollama_pull_model() {
    local model_id="$1" alias="$2"
    local payload="{\"name\":\"$model_id\"}"
    ollama_api_call "pull" "POST" "$payload" || return $?
    if [ -n "$alias" ]; then
        ollama_copy_model "$model_id" "$alias" || return $?
        ollama_remove_model "$model_id"
    fi
}


ollama_unload_model() {
    local payload="{\"model\":\"$1\",\"keep_alive\":0}"
    ollama_api_call "generate" "POST" "$payload" 
}

# Main model loading orchestrator: provisions and loads a model into Ollama
# Accepts either model_id (from manifest) or native_tag as input
# Returns: 0 on success, EXIT_NOT_FOUND if model not in manifest, EXIT_ERROR on failure
ollama_load_model() {
    local model_ref="$1" # Can be model_id or native_tag
    local users="${2:-1}" # Number of users default to 1
    local model_config=""

    # 1. Carica la configurazione del modello dal manifest
    log_msg "INFO" "Load configuration for $model_ref in manifest..."
    model_config=$(get_model_config "$model_ref")
    if [ -z "$model_config" ]; then
        log_msg "ERROR" "Model $model_ref not found in manifest"
        return $EXIT_NOT_FOUND
    fi

    # Estraiamo i parametri necessari dal JSON
    local loader; loader=$(echo "$model_config" | jq -r '.engines.ollama.loader // "gguf"')
    local ollama_name; ollama_name=$(echo "$model_config" | jq -r '.engines.ollama.ollama_name')
    local native_tag; native_tag=$(echo "$model_config" | jq -r '.engines.ollama.native_tag // ":::NOTFOUND:::"')

    # 2. CONTROLLO DI ESISTENZA UNIVERSALE (Sia per GGUF che per Native)
    log_msg "INFO" "Checking if $ollama_name is in Ollama registry..."
    local all_models; all_models=$(ollama_list_models)
    if echo "$all_models" | grep -q "\"$ollama_name\""; then
        log_msg "INFO" "Model $ollama_name already found in registry, skipping provision."
        ollama_preload_model "$ollama_name" "$users" "$model_config"
        log_msg "SUCCESS" "Model ready: $ollama_name"
        return 0
    fi

    # 3. Provisioning (Eseguito SOLO se il modello non è registrato in Ollama)
    log_msg "INFO" "Provisioning model..."
    case "$loader" in
        "gguf")
            log_msg "INFO" "Provisioning GGUF model: $ollama_name"
            local modelfile; modelfile=$(ollama_create_modelfile "$model_ref")
            if [ -z "$modelfile" ]; then
                log_msg "ERROR" "Could not build Modelfile for $model_ref"
                return $EXIT_NOT_FOUND
            fi
            ollama_create_model "$ollama_name" "$modelfile"
            [ $? -ne 0 ] && { log_msg "ERROR" "Failed to create model $ollama_name"; return $EXIT_ERROR; }
            ;;
        "native")
            log_msg "INFO" "Provisioning native model: $native_tag → $ollama_name"
            ollama_pull_model "$native_tag" "$ollama_name"
            [ $? -ne 0 ] && { log_msg "ERROR" "Failed to pull/rename $native_tag to $ollama_name"; return $EXIT_ERROR; }
            ;;
        *)
            log_msg "ERROR" "Unknown loader type: $loader"
            return $EXIT_ERROR
            ;;
    esac

    # 4. Caricamento e riscaldamento del modello in VRAM
    log_msg "INFO" "Warming up model into VRAM..."
    ollama_preload_model "$ollama_name" "$users" "$model_config"
    log_msg "SUCCESS" "Model ready: $ollama_name"
    return 0
}
