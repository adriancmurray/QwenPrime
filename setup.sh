#!/bin/bash
set -e

echo "🔮 ==================================================="
echo "🔮 Qwen Prime: Local MLX & Agent Setup for macOS"
echo "🔮 ==================================================="
echo ""

# 1. Check System
ARCH=$(uname -m)
if [ "$ARCH" != "arm64" ]; then
    echo "⚠️ Error: Qwen Prime & MLX require Apple Silicon (M1/M2/M3/M4)."
    exit 1
fi

echo "✅ Detected Apple Silicon ($ARCH)"

# 2. Configure Prime Agent Provider (~/.prime/agent/models.json)
PRIME_DIR="$HOME/.prime/agent"
mkdir -p "$PRIME_DIR"

cat << 'EOF' > "$PRIME_DIR/models.json"
{
  "providers": {
    "local-mlx": {
      "name": "Local MLX Speculative Engine",
      "baseUrl": "http://127.0.0.1:8000/v1",
      "api": "openai-completions",
      "models": [
        {
          "id": "qwen3.8-27b",
          "name": "Qwen 3.8 27B (Local MLX)",
          "reasoning": true,
          "contextWindow": 32768,
          "maxTokens": 4096,
          "cost": { "input": 0.0, "output": 0.0 }
        }
      ]
    }
  }
}
EOF

if [ ! -f "$PRIME_DIR/auth.json" ]; then
    echo '{"local-mlx": "local-dummy-key"}' > "$PRIME_DIR/auth.json"
fi

echo "✅ Configured Prime Agent CLI (~/.prime/agent/models.json)"

# 3. Create Sandbox Directory
mkdir -p "$HOME/prime-sandbox"
echo "✅ Prepared sandbox directory at $HOME/prime-sandbox"

# 4. Build Native macOS App
echo "🔨 Compiling QwenPrime.app..."
swift build -c release

APP_DIR="$(pwd)/QwenPrime.app"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$(swift build -c release --show-bin-path)/QwenPrime" "$APP_DIR/Contents/MacOS/QwenPrime"
chmod +x "$APP_DIR/Contents/MacOS/QwenPrime"

if [ -f "Resources/AppIcon.icns" ]; then
    cp "Resources/AppIcon.icns" "$APP_DIR/Contents/Resources/AppIcon.icns"
fi

cat << 'EOF' > "$APP_DIR/Contents/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>QwenPrime</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>com.adrian.qwenprime</string>
    <key>CFBundleName</key>
    <string>Qwen Prime</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
EOF

echo "✨ QwenPrime.app is built and ready!"
echo ""
echo "🚀 Next steps:"
echo "1. Start your MLX server on port 8000 (or use Qwen Prime's built-in engine toggle)"
echo "2. Open the app: open QwenPrime.app"
echo "3. Or run via CLI: prime-agent --provider local-mlx --model qwen3.8-27b"
