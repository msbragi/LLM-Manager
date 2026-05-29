#!/bin/bash
# ============================================================================
# ENGINE ORCHESTRATOR
# ============================================================================
# Main entry point for AI engine management
# Delegates to specific action/engine scripts
#
# USAGE:
#   ./engine-run.sh <action> <engine> [args...]
#
# OUTPUT:
#   All scripts return JSON on stdout
#   Debug messages go to stderr
#
# EXIT CODES:
#   0 = Success
#   1 = General error
#   2 = Not found (script/binary/model)
#   3 = Already running
#   4 = Not running
# ============================================================================

set -e  # Exit on error

# Determine script directory
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Source common utilities
source "$SCRIPT_DIR/engine-common.sh"

# ============================================================================
# MAIN
# ============================================================================

echo "=== Engine Orchestrator v1.0 ===" >&2

# Load configuration
load_config

# OS already detected when common.sh was sourced
echo "→ OS detected: $OS_TYPE" >&2

# Parse arguments
if [ $# -lt 1 ]; then
    json_output "error" "" "" '{"message":"Usage: engine-run.sh <action> [engine] [args...]"}'
    echo "$COMMAND_HELP" >&2
    exit $EXIT_ERROR
fi

ACTION="$1"
ENGINE=""
if [ $# -gt 1 ]; then
    ENGINE="$2"
    shift 1
fi;
shift 1

echo "→ Action: $ACTION" >&2

# Handle special actions that don't require an engine
case "$ACTION" in
    "config")
        # System-wide configuration (no engine needed)
        bash "$SCRIPT_DIR/engine-config.sh"
        exit $?
        ;;
    "models")
        bash "$SCRIPT_DIR/engine-models.sh" "$ENGINE" "$@"
        exit $?
        ;;
    "status")
        # If no engine specified, show global status
        if [ -z "$ENGINE" ]; then
            bash "$SCRIPT_DIR/engine-status.sh"
            exit $?
        fi
        ;;
esac

# Validate command against whitelist
if ! echo "$VALID_COMMANDS" | grep -qw "$ACTION"; then
    json_output "error" "$ACTION" "$ENGINE" "{\"message\":\"Invalid command for $ENGINE. Valid commands: $VALID_COMMANDS\"}"
    exit $EXIT_ERROR
fi

# For engine-specific actions, require engine parameter
if [ -z "$ENGINE" ]; then
    json_output "error" "$ACTION" "" "{\"message\":\"Engine required for action: $ACTION\"}"
    exit $EXIT_ERROR
fi

echo "→ Engine: $ENGINE" >&2

# Validate engine against whitelist
if ! echo "$VALID_ENGINES" | grep -qw "$ENGINE"; then
    json_output "error" "$ACTION" "$ENGINE" "{\"message\":\"Invalid engine. Valid engines: $VALID_ENGINES\"}"
    exit $EXIT_ERROR
fi

# Build script path - new structure: ENGINE/ACTION.sh
SCRIPT_PATH="$SCRIPT_DIR/$ENGINE/$ACTION.sh"
echo "→ Target script: $SCRIPT_PATH" >&2

# Check if script exists
if [ ! -f "$SCRIPT_PATH" ]; then
    json_output "error" "$ACTION" "$ENGINE" '{"message":"Script not found"}'
    exit $EXIT_NOT_FOUND
fi

# Execute the script
echo "→ Executing script..." >&2
bash "$SCRIPT_PATH" "$@"
EXIT_CODE=$?

echo "→ Script completed with exit code: $EXIT_CODE" >&2
exit $EXIT_CODE
