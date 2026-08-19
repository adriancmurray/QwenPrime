#!/bin/zsh
set -euo pipefail

PROJECT_DIR="${0:A:h}"
if [[ -n "${QWEN_PRIME_RUNTIME_SOURCE:-}" ]]; then
    RUNTIME_SOURCE="$QWEN_PRIME_RUNTIME_SOURCE"
elif [[ -x "$PROJECT_DIR/../qwen-prime-runtime/scripts/build_embedded_runtime.command" ]]; then
    RUNTIME_SOURCE="$PROJECT_DIR/../qwen-prime-runtime"
else
    echo "Companion qwen-prime-runtime checkout not found." >&2
    echo "Set QWEN_PRIME_RUNTIME_SOURCE to the verified runtime checkout." >&2
    exit 1
fi
OUTPUT="${QWEN_PRIME_RUNTIME_OUTPUT:-$PROJECT_DIR/.build/QwenPrimeRuntime}"
BUILDER="$RUNTIME_SOURCE/scripts/build_embedded_runtime.command"

if [[ ! -x "$BUILDER" ]]; then
    echo "Runtime builder not found at $BUILDER" >&2
    echo "Set QWEN_PRIME_RUNTIME_SOURCE to the verified qwen-prime-runtime checkout." >&2
    exit 1
fi

"$BUILDER" "$OUTPUT"
echo "$OUTPUT"
