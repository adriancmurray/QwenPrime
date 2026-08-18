#!/bin/bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$PROJECT_DIR"

VERSION="${QWEN_PRIME_VERSION:-1.1.1}"
BUILD_NUMBER="${QWEN_PRIME_BUILD_NUMBER:-1}"
BUILD_SYSTEM="${QWEN_PRIME_SWIFT_BUILD_SYSTEM:-native}"
if [[ ! "$VERSION" =~ ^[0-9A-Za-z.-]+$ ]] || [[ ! "$BUILD_NUMBER" =~ ^[0-9]+$ ]]; then
    echo "Invalid Qwen Prime version or build number." >&2
    exit 1
fi
if [[ "$BUILD_SYSTEM" != "swiftbuild" && "$BUILD_SYSTEM" != "native" ]]; then
    echo "QWEN_PRIME_SWIFT_BUILD_SYSTEM must be swiftbuild or native." >&2
    exit 1
fi
BUILD_ARGUMENTS=(-c release --build-system "$BUILD_SYSTEM")
if [[ "${QWEN_PRIME_DISABLE_SWIFTPM_SANDBOX:-0}" == "1" ]]; then
    BUILD_ARGUMENTS+=(--disable-sandbox)
fi

echo "Building QwenPrime in release mode..."
swift build "${BUILD_ARGUMENTS[@]}"
swift build "${BUILD_ARGUMENTS[@]}" --product QwenPrimeCommandHelper
swift build "${BUILD_ARGUMENTS[@]}" --product QwenPrimeHarness

APP_DIR="$PROJECT_DIR/QwenPrime.app"
CONTENTS="$APP_DIR/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"
FRAMEWORKS="$CONTENTS/Frameworks"
XPC_SERVICES="$CONTENTS/XPCServices"
HELPERS="$CONTENTS/Helpers"

rm -rf "$APP_DIR"
mkdir -p "$MACOS" "$RESOURCES" "$FRAMEWORKS" "$XPC_SERVICES" "$HELPERS"

BIN_DIR="$(swift build "${BUILD_ARGUMENTS[@]}" --show-bin-path)"
install -m 755 "$BIN_DIR/QwenPrime" "$MACOS/QwenPrime"
install_name_tool -add_rpath "@executable_path/../Frameworks" "$MACOS/QwenPrime"
install -m 755 "$BIN_DIR/QwenPrimeHarness" "$HELPERS/QwenPrimeHarness"

COMMAND_HELPER="$XPC_SERVICES/QwenPrimeCommandHelper.xpc"
COMMAND_HELPER_CONTENTS="$COMMAND_HELPER/Contents"
COMMAND_HELPER_MACOS="$COMMAND_HELPER_CONTENTS/MacOS"
mkdir -p "$COMMAND_HELPER_MACOS"
install -m 755 "$BIN_DIR/QwenPrimeCommandHelper" \
    "$COMMAND_HELPER_MACOS/QwenPrimeCommandHelper"
cat > "$COMMAND_HELPER_CONTENTS/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key><string>en</string>
    <key>CFBundleExecutable</key><string>QwenPrimeCommandHelper</string>
    <key>CFBundleIdentifier</key><string>app.dech.qwenprime.command-helper</string>
    <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
    <key>CFBundleName</key><string>Qwen Prime Command Helper</string>
    <key>CFBundlePackageType</key><string>XPC!</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>$BUILD_NUMBER</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>XPCService</key>
    <dict>
        <key>ServiceType</key><string>Application</string>
    </dict>
</dict>
</plist>
EOF
plutil -lint "$COMMAND_HELPER_CONTENTS/Info.plist"

SPARKLE_FRAMEWORK=""
if [ -d "$BIN_DIR/Sparkle.framework" ]; then
    SPARKLE_FRAMEWORK="$BIN_DIR/Sparkle.framework"
else
    while IFS= read -r candidate; do
        SPARKLE_FRAMEWORK="$candidate"
        break
    done < <(find "$PROJECT_DIR/.build/artifacts" -type d -name Sparkle.framework 2>/dev/null)
fi
if [ -z "$SPARKLE_FRAMEWORK" ]; then
    echo "Sparkle.framework was not produced by SwiftPM." >&2
    exit 1
fi
ditto "$SPARKLE_FRAMEWORK" "$FRAMEWORKS/Sparkle.framework"

if [ -f "$PROJECT_DIR/Resources/AppIcon.icns" ]; then
    cp "$PROJECT_DIR/Resources/AppIcon.icns" "$RESOURCES/AppIcon.icns"
fi
if [ -d "$BIN_DIR/QwenPrime_QwenPrime.bundle" ]; then
    cp -R "$BIN_DIR/QwenPrime_QwenPrime.bundle" "$RESOURCES/"
fi
cp "$PROJECT_DIR/LICENSE" "$RESOURCES/LICENSE"
cp "$PROJECT_DIR/THIRD_PARTY_NOTICES.md" "$RESOURCES/THIRD_PARTY_NOTICES.md"

if [ -n "${QWEN_PRIME_EMBEDDED_RUNTIME:-}" ]; then
    RUNTIME_SOURCE="$QWEN_PRIME_EMBEDDED_RUNTIME"
    if [ ! -x "$RUNTIME_SOURCE/bin/qwen-prime-runtime" ]; then
        echo "Embedded runtime must contain bin/qwen-prime-runtime." >&2
        exit 1
    fi
    if [ ! -x "$RUNTIME_SOURCE/python/bin/python3.12" ]; then
        echo "Embedded runtime must contain executable CPython 3.12." >&2
        exit 1
    fi
    if [ ! -d "$RUNTIME_SOURCE/site-packages/harness" ]; then
        echo "Embedded runtime is missing the qwen-prime-runtime package." >&2
        exit 1
    fi
    if find "$RUNTIME_SOURCE" -type f \( -name '*.safetensors' -o -name '*.gguf' -o -name '*.mlx' \) -print -quit | grep -q .; then
        echo "Refusing to package model weights inside Qwen Prime." >&2
        exit 1
    fi
    ditto "$RUNTIME_SOURCE" "$RESOURCES/QwenPrimeRuntime"
fi

cat > "$CONTENTS/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key><string>en</string>
    <key>CFBundleExecutable</key><string>QwenPrime</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundleIdentifier</key><string>app.dech.qwenprime</string>
    <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
    <key>CFBundleName</key><string>Qwen Prime</string>
    <key>CFBundleDisplayName</key><string>Qwen Prime</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>$BUILD_NUMBER</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSPrincipalClass</key><string>NSApplication</string>
    <key>NSAppTransportSecurity</key>
    <dict><key>NSAllowsLocalNetworking</key><true/></dict>
</dict>
</plist>
EOF

if [ -n "${SPARKLE_PUBLIC_ED_KEY:-}" ]; then
    SPARKLE_FEED_URL="${SPARKLE_FEED_URL:-https://raw.githubusercontent.com/adriancmurray/QwenPrime/main/appcast.xml}"
    /usr/libexec/PlistBuddy -c "Add :SUFeedURL string $SPARKLE_FEED_URL" "$CONTENTS/Info.plist"
    /usr/libexec/PlistBuddy -c "Add :SUPublicEDKey string $SPARKLE_PUBLIC_ED_KEY" "$CONTENTS/Info.plist"
    /usr/libexec/PlistBuddy -c "Add :SUEnableAutomaticChecks bool false" "$CONTENTS/Info.plist"
fi

plutil -lint "$CONTENTS/Info.plist"
if [ -n "${DEVELOPER_ID_APPLICATION:-}" ]; then
    if [ -d "$RESOURCES/QwenPrimeRuntime" ]; then
        while IFS= read -r -d '' item; do
            if file "$item" | grep -q 'Mach-O'; then
                codesign --force --options runtime --timestamp \
                    --sign "$DEVELOPER_ID_APPLICATION" "$item"
            fi
        done < <(find "$RESOURCES/QwenPrimeRuntime" -type f -print0)
    fi

    SPARKLE_VERSION="$FRAMEWORKS/Sparkle.framework/Versions/B"
    codesign --force --options runtime --timestamp \
        --sign "$DEVELOPER_ID_APPLICATION" \
        "$SPARKLE_VERSION/XPCServices/Installer.xpc"
    codesign --force --options runtime --timestamp \
        --preserve-metadata=entitlements \
        --sign "$DEVELOPER_ID_APPLICATION" \
        "$SPARKLE_VERSION/XPCServices/Downloader.xpc"
    codesign --force --options runtime --timestamp \
        --sign "$DEVELOPER_ID_APPLICATION" "$SPARKLE_VERSION/Autoupdate"
    codesign --force --options runtime --timestamp \
        --sign "$DEVELOPER_ID_APPLICATION" "$SPARKLE_VERSION/Updater.app"
    codesign --force --options runtime --timestamp \
        --sign "$DEVELOPER_ID_APPLICATION" "$FRAMEWORKS/Sparkle.framework"
    codesign --force --options runtime --timestamp \
        --entitlements "$PROJECT_DIR/Entitlements/QwenPrimeCommandHelper.entitlements" \
        --sign "$DEVELOPER_ID_APPLICATION" "$COMMAND_HELPER"
    codesign --force --options runtime --timestamp \
        --sign "$DEVELOPER_ID_APPLICATION" "$HELPERS/QwenPrimeHarness"
    codesign --force --options runtime --timestamp \
        --sign "$DEVELOPER_ID_APPLICATION" "$APP_DIR"
else
    codesign --force \
        --entitlements "$PROJECT_DIR/Entitlements/QwenPrimeCommandHelper.entitlements" \
        --sign - "$COMMAND_HELPER"
    codesign --force --sign - "$HELPERS/QwenPrimeHarness"
    codesign --force --sign - "$APP_DIR"
    echo "Created an ad-hoc signed development bundle with sandboxed command helper."
fi
codesign --verify --deep --strict --verbose=2 "$APP_DIR"
codesign -d --entitlements :- "$COMMAND_HELPER" 2>&1 \
    | grep -q 'com.apple.security.app-sandbox'

PACKAGED_RUNTIME="$RESOURCES/QwenPrimeRuntime"
if [ -d "$PACKAGED_RUNTIME" ]; then
    "$PACKAGED_RUNTIME/bin/qwen-prime-runtime" --help >/dev/null
    if find "$PACKAGED_RUNTIME" -type d -name __pycache__ -print -quit | grep -q .; then
        echo "Embedded runtime mutated the signed app by writing Python bytecode." >&2
        exit 1
    fi
    codesign --verify --deep --strict --verbose=2 "$APP_DIR"
fi

echo "QwenPrime.app created at $APP_DIR"
