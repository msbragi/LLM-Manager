#!/bin/bash
# Run with: bash tests/test-api-host.sh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENGINE_COMMON_LOADED=""
OS_TYPE=linux
source "$ROOT_DIR/engine-common.sh"
TEST_TMP=$(mktemp -d)
trap 'rm -rf "$TEST_TMP"' EXIT

# Simulate WSL independently of the machine running these tests.
wslinfo() {
    [ "$*" = "--networking-mode" ] || return 1
    printf '%s' "$TEST_MODE"
    return "$TEST_MODE_RC"
}
ip() {
    [ "$*" = "-4 route show default" ] || return 1
    printf '%s\n' "$TEST_ROUTE"
}

check_host() (
    local name="$1" expected="$2" expected_rc="$3" expected_log="$4"
    local actual rc=0
    actual=$(get_api_host 2>"$TEST_TMP/stderr") || rc=$?
    if [ "$actual" != "$expected" ] || [ "$rc" -ne "$expected_rc" ]; then
        printf 'FAIL %s: host=%s rc=%s\n' "$name" "$actual" "$rc" >&2
        exit 1
    fi
    if [ -n "$expected_log" ]; then
        grep -q "$expected_log" "$TEST_TMP/stderr"
    else
        [ ! -s "$TEST_TMP/stderr" ]
    fi
    printf 'PASS %s\n' "$name"
)

OS_TYPE=wsl
TEST_MODE=mirrored
TEST_MODE_RC=0
TEST_ROUTE='default via 172.30.96.1 dev eth0'
WSL_NAT=""
check_host 'automatic mirrored' 127.0.0.1 0 ''
TEST_MODE=$' NAT \r\n'
check_host 'automatic NAT, normalized output' 172.30.96.1 0 ''
unset WSL_NAT
TEST_MODE=mirrored
check_host 'old config without WSL_NAT' 127.0.0.1 0 ''
WSL_NAT=true
check_host 'forced NAT overrides detected mirrored' 172.30.96.1 0 ''
WSL_NAT=false
TEST_MODE=nat
TEST_ROUTE=''
check_host 'forced mirrored requires no gateway' 127.0.0.1 0 ''
WSL_NAT=true
check_host 'missing gateway' '' 1 'ERROR'
TEST_ROUTE='default dev eth0'
check_host 'default route without gateway' '' 1 'ERROR'
WSL_NAT=invalid
check_host 'invalid override' '' 1 'Invalid WSL_NAT'
OS_TYPE=linux
check_host 'native Linux ignores WSL_NAT' localhost 0 ''
OS_TYPE=wsl
WSL_NAT=''
TEST_ROUTE='default via 172.30.96.1 dev eth0'
TEST_MODE=unknown
check_host 'unknown mode falls back to NAT' 172.30.96.1 0 'WARN'
TEST_MODE=mirrored
TEST_MODE_RC=1
check_host 'failed detection falls back to NAT' 172.30.96.1 0 'WARN'
unset -f wslinfo
wslinfo() { return 127; }
check_host 'unavailable detection falls back to NAT' 172.30.96.1 0 'WARN'
WSL_NAT=false
check_host 'forced mirrored bypasses unavailable detection' 127.0.0.1 0 ''

# Keep API initialization isolated from the real engine.conf and servers.
load_config() {
    OS_TYPE=wsl
    WSL_NAT="$TEST_OVERRIDE"
    OLLAMA_PORT=1234
    LLAMA_PORT=12345
    OLLAMA_HEALTH_CHECK='Ollama is running'
    LLAMA_HEALTH_CHECK=default_generation_settings
    EXIT_ERROR=1
}
curl() {
    local arg url=''
    for arg in "$@"; do
        case "$arg" in http://*) url="$arg" ;; esac
    done
    printf '%s\n' "$url" >> "$TEST_TMP/urls"
    case "$url" in
        */props) printf '{"default_generation_settings":{}}' ;;
        *) printf 'Ollama is running' ;;
    esac
}

for TEST_OVERRIDE in true false; do
    expected_host=172.30.96.1
    [ "$TEST_OVERRIDE" = true ] || expected_host=127.0.0.1
    (
        source "$ROOT_DIR/ollama/ollama-api.sh"
        ollama_api_call tags >/dev/null
        ollama_running
    )
    (
        source "$ROOT_DIR/llama/llama-api.sh"
        llama_api_call /v1/models >/dev/null
        llama_running
    )
    for expected_url in \
        "http://$expected_host:1234/api/tags" \
        "http://$expected_host:1234" \
        "http://$expected_host:12345/v1/models" \
        "http://$expected_host:12345/props"; do
        grep -Fxq "$expected_url" "$TEST_TMP/urls"
    done
    printf 'PASS API calls and health checks with WSL_NAT=%s\n' "$TEST_OVERRIDE"
done

for engine in ollama llama; do
    TEST_OVERRIDE=true
    TEST_ROUTE=''
    rc=0
    ( source "$ROOT_DIR/$engine/$engine-api.sh"; exit 99 ) \
        >"$TEST_TMP/stdout" 2>"$TEST_TMP/stderr" || rc=$?
    [ "$rc" -eq 1 ]
    [ ! -s "$TEST_TMP/stdout" ]
    grep -q 'no IPv4 default gateway' "$TEST_TMP/stderr"
    printf 'PASS %s aborts on host resolution failure\n' "$engine"
done

(
    export -f load_config get_api_host log_msg json_output ip
    export ENGINE_COMMON_LOADED TEST_OVERRIDE TEST_ROUTE
    export RED GREEN YELLOW BLUE NC
    rc=0
    bash "$ROOT_DIR/engine-status.sh" \
        >"$TEST_TMP/stdout" 2>"$TEST_TMP/stderr" || rc=$?
    [ "$rc" -eq 1 ]
    jq -e '.status == "error" and .action == "status" and .engine == "all"' \
        "$TEST_TMP/stdout" >/dev/null
    grep -q 'no IPv4 default gateway' "$TEST_TMP/stderr"
    printf 'PASS global status reports host resolution failure as JSON\n'
)
