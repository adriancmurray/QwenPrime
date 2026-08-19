#!/bin/zsh
set -euo pipefail

PROJECT_DIR="${0:A:h}"
MODE="${1:-ranked}"
case "$MODE" in
    ranked|full|report) ;;
    *) echo "Usage: $0 [ranked|full|report]" >&2; exit 2 ;;
esac

APP_PATH="$PROJECT_DIR/QwenPrime.app"
EXECUTABLE="$APP_PATH/Contents/MacOS/QwenPrime"
USER_TEMP_DIR="${TMPDIR:-$(/usr/bin/getconf DARWIN_USER_TEMP_DIR)}"
RESULT_PATH="${USER_TEMP_DIR%/}/qwen-prime-tool-routing-latest.log"

archive_result() {
    [[ -f "$RESULT_PATH" ]] || return 0
    local result_mode
    result_mode="$(/usr/bin/sed -n 's/.*mode=\([^ ]*\).*/\1/p' "$RESULT_PATH")"
    case "$result_mode" in
        ranked|full)
            /bin/cp "$RESULT_PATH" "/private/tmp/qwen-prime-tool-routing-$result_mode.log"
            ;;
    esac
}

if [[ "$MODE" == "report" ]]; then
    for result in /private/tmp/qwen-prime-tool-routing-{full,ranked}.log; do
        if [[ -f "$result" ]]; then
            /bin/cat "$result"
            echo
        fi
    done
    exit 0
fi
archive_result

if [[ ! -x "$EXECUTABLE" ]]; then
    echo "Packaged app not found at $APP_PATH" >&2
    exit 1
fi

/usr/bin/defaults write app.dech.qwenprime AgentToolRoutingMode -string "$MODE"
rm -f "$RESULT_PATH"

if ! /usr/sbin/lsof -t -- "$EXECUTABLE" >/dev/null 2>&1; then
    /usr/bin/open "$APP_PATH"
fi

echo "Tool routing mode: $MODE"
echo "The running app and warm model are preserved. Use a new conversation for the test prompt."
echo "After the response: cat '$RESULT_PATH'"
echo "After both modes: $0 report"
