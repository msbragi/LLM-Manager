#!/bin/bash
# System collector selector. Both backends return the contents of data.system.
SYSTEM_MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

get_system_info() {
    case "$OS_TYPE" in
        wsl|windows)
            local collector_path output
            if ! collector_path=$(wslpath -w "$SYSTEM_MODULE_DIR/engine-system-win.ps1"); then
                echo "Cannot translate Windows collector path" >&2
                return 1
            fi
            if ! output=$(powershell.exe -NoProfile -File "$collector_path" \
                -ModelsRoot "$MODELS_ROOT" -BaseDir "$BASE_DIR" \
                -ApiHost "${API_HOST:-127.0.0.1}" -OsType "$OS_TYPE"); then
                echo "Windows system collector failed" >&2
                return 1
            fi
            # Windows PowerShell emits CRLF. Validate before passing to callers.
            printf '%s\n' "$output" | tr -d '\r' | jq -ce 'select(type == "object")'
            ;;
        linux)
            source "$SYSTEM_MODULE_DIR/engine-system-lnx.sh"
            get_linux_system_info
            ;;
        *)
            echo "Unsupported system collector OS_TYPE: $OS_TYPE" >&2
            return 1
            ;;
    esac
}
