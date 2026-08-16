#!/bin/bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -n "${QWEN_PRIME_RUNTIME_SOURCE:-}" ]; then
    RUNTIME_SOURCE="$QWEN_PRIME_RUNTIME_SOURCE"
elif [ -x "$PROJECT_DIR/../qwen-prime-runtime/scripts/install_qwen_prime_runtime.command" ]; then
    RUNTIME_SOURCE="$PROJECT_DIR/../qwen-prime-runtime"
else
    RUNTIME_SOURCE="$PROJECT_DIR/../local-eval-harness"
fi
TARGET_MODEL="${1:-${QWEN_PRIME_TARGET_MODEL:-}}"
DRAFT_MODEL="${2:-${QWEN_PRIME_DRAFT_MODEL:-}}"

if [ "$(uname -m)" != "arm64" ]; then
    echo "Qwen Prime and MLX require Apple Silicon." >&2
    exit 1
fi
if [ -z "$TARGET_MODEL" ] || [ -z "$DRAFT_MODEL" ]; then
    echo "Usage: ./setup.sh /path/to/target /path/to/draft" >&2
    exit 1
fi
if [ ! -x "$RUNTIME_SOURCE/scripts/install_qwen_prime_runtime.command" ]; then
    echo "Runtime installer not found at $RUNTIME_SOURCE" >&2
    exit 1
fi

"$RUNTIME_SOURCE/scripts/install_qwen_prime_runtime.command"
RUNTIME_BIN="$(command -v qwen-prime-runtime || true)"
if [ -z "$RUNTIME_BIN" ] && [ -x "$HOME/.local/bin/qwen-prime-runtime" ]; then
    RUNTIME_BIN="$HOME/.local/bin/qwen-prime-runtime"
fi
if [ -z "$RUNTIME_BIN" ]; then
    echo "qwen-prime-runtime was installed but is not on PATH." >&2
    exit 1
fi

"$RUNTIME_BIN" configure --target "$TARGET_MODEL" --draft "$DRAFT_MODEL"
"$RUNTIME_BIN" doctor
"$RUNTIME_BIN" configure-prime-agent
"$PROJECT_DIR/package_app.sh"

echo "Setup complete. Start the runtime with: qwen-prime-runtime serve"
