#!/bin/bash
# Isolated routing/collection tests: no engines or Windows installation required.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FIXTURE=$(mktemp -d)
trap 'rm -rf "$FIXTURE"' EXIT
cp "$ROOT/engine-run.sh" "$ROOT/engine-status.sh" "$ROOT/engine-system.sh" "$FIXTURE/"
mkdir -p "$FIXTURE/bin" "$FIXTURE/ollama"
export STATUS_TEST_TRACE="$FIXTURE/trace"
export STATUS_TEST_FAIL_WINDOWS=0
cat > "$FIXTURE/engine-common.sh" <<'COMMON'
EXIT_SUCCESS=0
EXIT_ERROR=1
EXIT_NOT_FOUND=2
VALID_COMMANDS='status'
VALID_ENGINES='ollama dummy'
OS_TYPE=wsl
MODELS_ROOT='/mnt/c/Models with spaces'
BASE_DIR='/mnt/c/engines with spaces'
load_config() { :; }
get_api_host() { echo 127.0.0.1; }
log_msg() { :; }
json_output() {
    jq -cn --arg status "$1" --arg action "$2" --arg engine "$3" --argjson data "$4" \
        '{timestamp:"fixture",status:$status,action:$action,engine:$engine,data:$data}'
}
COMMON
cat > "$FIXTURE/ollama/status.sh" <<'ENGINE'
#!/bin/bash
echo engine >> "$STATUS_TEST_TRACE"
printf '%s\n' '{"data":{"state":"running","models_loaded":["model"],"models_running":["model"]}}'
ENGINE
cat > "$FIXTURE/bin/wslpath" <<'CONVERT'
#!/bin/bash
printf '%s\n' 'C:\fixture\engine-system-win.ps1'
CONVERT
cat > "$FIXTURE/bin/powershell.exe" <<'POWERSHELL'
#!/bin/bash
echo system >> "$STATUS_TEST_TRACE"
[ "$STATUS_TEST_FAIL_WINDOWS" = 0 ] || exit 1
# Verify argument boundaries and context are preserved, including spaces.
[ "$1" = '-NoProfile' ] && [ "$2" = '-File' ] && [ "$3" = 'C:\fixture\engine-system-win.ps1' ]
[ "$4" = '-ModelsRoot' ] && [ "$5" = '/mnt/c/Models with spaces' ] || exit 2
[ "$6" = '-BaseDir' ] && [ "$7" = '/mnt/c/engines with spaces' ] || exit 2
[ "$8" = '-ApiHost' ] && [ "$9" = '127.0.0.1' ] || exit 2
[ "${10}" = '-OsType' ] && [ "${11}" = 'wsl' ] || exit 2
printf '{"os_type":"wsl","api_host":"127.0.0.1","gpu":{"vram_used_mb":123}}\r\n'
POWERSHELL
chmod +x "$FIXTURE/bin/wslpath" "$FIXTURE/bin/powershell.exe"
export PATH="$FIXTURE/bin:$PATH"

: > "$STATUS_TEST_TRACE"
output=$(bash "$FIXTURE/engine-run.sh" status system 2>/dev/null)
jq -e '.scope == "system" and .action == "status" and .status == "success" and (.data | keys) == ["system"] and .data.system.gpu.vram_used_mb == 123' <<< "$output" >/dev/null
[ "$(cat "$STATUS_TEST_TRACE")" = system ]
# A compact fixture envelope must still become fully indented on output.
[ "$output" = "$(jq . <<< "$output")" ]

: > "$STATUS_TEST_TRACE"
output=$(bash "$FIXTURE/engine-run.sh" status engines 2>/dev/null)
jq -e '.scope == "engines" and (.data | keys) == ["active_engine","engines"] and .data.engines.ollama.models_running == ["model"]' <<< "$output" >/dev/null
[ "$(cat "$STATUS_TEST_TRACE")" = engine ]

: > "$STATUS_TEST_TRACE"
output=$(bash "$FIXTURE/engine-run.sh" status 2>/dev/null)
jq -e '.scope == "all" and (.data | keys) == ["active_engine","engines","system"] and .engine == "all"' <<< "$output" >/dev/null
[ "$(sort "$STATUS_TEST_TRACE" | tr '\n' ' ')" = 'engine system ' ]

: > "$STATUS_TEST_TRACE"
output=$(bash "$FIXTURE/engine-run.sh" status ollama 2>/dev/null)
jq -e '.data.state == "running"' <<< "$output" >/dev/null
[ "$(cat "$STATUS_TEST_TRACE")" = engine ]

export STATUS_TEST_FAIL_WINDOWS=1
if output=$(bash "$FIXTURE/engine-run.sh" status system 2>/dev/null); then
    echo 'Expected failure for Windows collector error' >&2
    exit 1
fi
jq -e '.scope == "system" and .status == "error" and .action == "status"' <<< "$output" >/dev/null
printf '%s\n' 'Status section tests passed'
