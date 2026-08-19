#!/bin/zsh
set -euo pipefail

PROJECT_DIR="${0:A:h}"
VERSION="${1:-}"
MODE="${2:-}"
failures=()
deferred=()

if [[ ! "$VERSION" =~ '^[0-9]+\.[0-9]+\.[0-9]+([.-][0-9A-Za-z.-]+)?$' ]]; then
    echo "Usage: ./release_preflight.command 0.1.0 [--publish]" >&2
    exit 2
fi
if [[ "$(uname -s)" != "Darwin" || "$(uname -m)" != "arm64" ]]; then
    failures+=("Release builds require Apple Silicon macOS.")
fi

for tool in swift uv ditto codesign xcrun gh shasum xmllint; do
    command -v "$tool" >/dev/null 2>&1 || failures+=("Missing required tool: $tool")
done

[[ -x "$PROJECT_DIR/build_embedded_runtime.command" ]] \
    || failures+=("build_embedded_runtime.command is not executable.")
[[ -x "$PROJECT_DIR/package_app.sh" ]] \
    || failures+=("package_app.sh is not executable.")
[[ -x "$PROJECT_DIR/release_app.command" ]] \
    || failures+=("release_app.command is not executable.")
[[ -x "$PROJECT_DIR/.build/artifacts/sparkle/Sparkle/bin/generate_appcast" ]] \
    || failures+=("Sparkle tools are missing; run swift package resolve.")
[[ -x "$PROJECT_DIR/.build/artifacts/sparkle/Sparkle/bin/generate_keys" ]] \
    || failures+=("Sparkle key tools are missing; run swift package resolve.")
xmllint --noout "$PROJECT_DIR/appcast.xml" >/dev/null 2>&1 \
    || failures+=("appcast.xml is not valid XML.")

if [[ "$MODE" == "--publish" ]]; then
    [[ -n "${DEVELOPER_ID_APPLICATION:-}" ]] \
        || failures+=("DEVELOPER_ID_APPLICATION is not injected.")
    if [[ -z "${NOTARY_PROFILE:-}" ]] && {
        [[ -z "${APPLE_ID:-}" ]] ||
        [[ -z "${APPLE_TEAM_ID:-}" ]] ||
        [[ -z "${NOTARY_APP_PASSWORD:-}" ]]
    }; then
        failures+=("Inject NOTARY_PROFILE or APPLE_ID, APPLE_TEAM_ID, and NOTARY_APP_PASSWORD.")
    fi
    [[ -n "${SPARKLE_PUBLIC_ED_KEY:-}" ]] \
        || failures+=("SPARKLE_PUBLIC_ED_KEY is not injected.")
    SPARKLE_ACCOUNT="${SPARKLE_ACCOUNT:-app.dech.qwenprime}"
    "$PROJECT_DIR/.build/artifacts/sparkle/Sparkle/bin/generate_keys" \
        --account "$SPARKLE_ACCOUNT" -p >/dev/null 2>&1 \
        || failures+=("Sparkle signing key account is unavailable: $SPARKLE_ACCOUNT")
    [[ -z "$(git -C "$PROJECT_DIR" status --porcelain)" ]] \
        || failures+=("Release source is not committed and clean.")
    gh auth status >/dev/null 2>&1 \
        || failures+=("GitHub CLI authentication is unavailable.")
else
    [[ -n "${DEVELOPER_ID_APPLICATION:-}" ]] \
        || deferred+=("Developer ID Application identity")
    [[ -n "${NOTARY_PROFILE:-}" ]] \
        || deferred+=("Apple ID, team ID, and app-specific notary password")
    [[ -n "${SPARKLE_PUBLIC_ED_KEY:-}" ]] \
        || deferred+=("Sparkle public Ed25519 key")
    deferred+=("Sparkle Keychain account (defaults to app.dech.qwenprime)")
    deferred+=("GitHub CLI release authorization")
fi

if (( ${#failures} > 0 )); then
    echo "Release preflight failed:" >&2
    for failure in "${failures[@]}"; do
        echo "- $failure" >&2
    done
    exit 1
fi

echo "Release source preflight passed for Qwen Prime $VERSION."
if (( ${#deferred} > 0 )); then
    echo "Deferred to the final credential checkpoint:"
    for item in "${deferred[@]}"; do
        echo "- $item"
    done
fi
