#!/bin/bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VERSION="${QWEN_PRIME_VERSION:-0.1.0}"
if [ -z "${DEVELOPER_ID_APPLICATION:-}" ]; then
    echo "Set DEVELOPER_ID_APPLICATION to an installed Developer ID identity." >&2
    exit 1
fi
if [ -z "${SPARKLE_PUBLIC_ED_KEY:-}" ]; then
    echo "Set SPARKLE_PUBLIC_ED_KEY for signed Sparkle updates." >&2
    exit 1
fi

RUNTIME_PAYLOAD="${QWEN_PRIME_EMBEDDED_RUNTIME:-$PROJECT_DIR/.build/QwenPrimeRuntime}"
if [ -z "${QWEN_PRIME_EMBEDDED_RUNTIME:-}" ]; then
    QWEN_PRIME_RUNTIME_OUTPUT="$RUNTIME_PAYLOAD" \
        "$PROJECT_DIR/build_embedded_runtime.command"
fi
QWEN_PRIME_EMBEDDED_RUNTIME="$RUNTIME_PAYLOAD" "$PROJECT_DIR/package_app.sh"
ARCHIVE="$PROJECT_DIR/QwenPrime-v$VERSION-macOS.zip"
rm -f "$ARCHIVE" "$ARCHIVE.sha256"
ditto -c -k --keepParent "$PROJECT_DIR/QwenPrime.app" "$ARCHIVE"

NOTARIZED=0
if [ -n "${NOTARY_PROFILE:-}" ]; then
    xcrun notarytool submit "$ARCHIVE" --keychain-profile "$NOTARY_PROFILE" --wait
    NOTARIZED=1
elif [ -n "${APPLE_ID:-}" ] && [ -n "${APPLE_TEAM_ID:-}" ] \
    && [ -n "${NOTARY_APP_PASSWORD:-}" ]; then
    xcrun notarytool submit "$ARCHIVE" \
        --apple-id "$APPLE_ID" \
        --team-id "$APPLE_TEAM_ID" \
        --password "$NOTARY_APP_PASSWORD" \
        --wait
    NOTARIZED=1
fi
if [ "$NOTARIZED" = "1" ]; then
    xcrun stapler staple "$PROJECT_DIR/QwenPrime.app"
    rm -f "$ARCHIVE"
    ditto -c -k --keepParent "$PROJECT_DIR/QwenPrime.app" "$ARCHIVE"
fi

shasum -a 256 "$ARCHIVE" > "$ARCHIVE.sha256"
echo "Release archive: $ARCHIVE"
echo "Checksum: $ARCHIVE.sha256"
