#!/bin/bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$PROJECT_DIR"

VERSION="${1:-${QWEN_PRIME_VERSION:-}}"
REPOSITORY="adriancmurray/QwenPrime"
TAG="v$VERSION"
SPARKLE_ACCOUNT="${SPARKLE_ACCOUNT:-app.dech.qwenprime}"
SPARKLE_BIN="$PROJECT_DIR/.build/artifacts/sparkle/Sparkle/bin"
KEY_TOOL="$SPARKLE_BIN/generate_keys"

if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+([.-][0-9A-Za-z.-]+)?$ ]]; then
    echo "Usage: ./publish_release.command 0.1.0" >&2
    exit 1
fi
if [[ -z "${SPARKLE_PUBLIC_ED_KEY:-}" ]]; then
    export SPARKLE_PUBLIC_ED_KEY="$("$KEY_TOOL" --account "$SPARKLE_ACCOUNT" -p)"
fi
"$PROJECT_DIR/release_preflight.command" "$VERSION" --publish
if git rev-parse "$TAG" >/dev/null 2>&1; then
    echo "Tag already exists: $TAG" >&2
    exit 1
fi

export QWEN_PRIME_VERSION="$VERSION"
export QWEN_PRIME_BUILD_NUMBER="${QWEN_PRIME_BUILD_NUMBER:-$(date -u +%Y%m%d%H%M)}"
"$PROJECT_DIR/release_app.command"

ARCHIVE="$PROJECT_DIR/QwenPrime-v$VERSION-macOS.zip"
CHECKSUM="$ARCHIVE.sha256"
APPCAST_TOOL="$SPARKLE_BIN/generate_appcast"
if [ ! -x "$APPCAST_TOOL" ]; then
    echo "Resolve Sparkle before publishing: swift package resolve" >&2
    exit 1
fi

RELEASE_DIR="$(mktemp -d /private/tmp/qwenprime-release.XXXXXX)"
cleanup() {
    if [[ "$RELEASE_DIR" == /private/tmp/qwenprime-release.* ]]; then
        rm -rf "$RELEASE_DIR"
    fi
}
trap cleanup EXIT

cp "$ARCHIVE" "$RELEASE_DIR/"
cp "$PROJECT_DIR/appcast.xml" "$RELEASE_DIR/appcast.xml"

"$APPCAST_TOOL" \
    --account "$SPARKLE_ACCOUNT" \
    --download-url-prefix "https://github.com/$REPOSITORY/releases/download/$TAG/" \
    --link "https://github.com/$REPOSITORY/releases/tag/$TAG" \
    --maximum-versions 5 \
    --maximum-deltas 3 \
    -o appcast.xml \
    "$RELEASE_DIR"

cp "$RELEASE_DIR/appcast.xml" "$PROJECT_DIR/appcast.xml"
git add appcast.xml
git commit -m "release: $TAG"
git tag -a "$TAG" -m "Qwen Prime $VERSION"
git push origin main
git push origin "$TAG"

gh release create "$TAG" "$ARCHIVE" "$CHECKSUM" \
    --repo "$REPOSITORY" \
    --title "Qwen Prime $VERSION" \
    --generate-notes \
    --verify-tag

echo "Published https://github.com/$REPOSITORY/releases/tag/$TAG"
