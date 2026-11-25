#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="Gabi"
APP_BUNDLE="$PROJECT_DIR/$APP_NAME.app"
CONTENTS="$APP_BUNDLE/Contents"
MACOS_DIR="$CONTENTS/MacOS"
RESOURCES_DIR="$CONTENTS/Resources"

echo "Building $APP_NAME.app..."
rm -rf "$APP_BUNDLE"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR/sprites"

# Compile Swift sources into native macOS binary
mkdir -p /tmp/gabi-swift-cache
swiftc \
  -O \
  -target arm64-apple-macos13.0 \
  -module-cache-path /tmp/gabi-swift-cache \
  -framework Cocoa \
  -framework Carbon \
  -framework Speech \
  -framework AVFoundation \
  -framework ApplicationServices \
  "$PROJECT_DIR/Sources/GabiModels.swift" \
  "$PROJECT_DIR/Sources/SoundManager.swift" \
  "$PROJECT_DIR/Sources/BallWindowController.swift" \
  "$PROJECT_DIR/Sources/HotkeyManager.swift" \
  "$PROJECT_DIR/Sources/BrowserTyper.swift" \
  "$PROJECT_DIR/Sources/CommandStore.swift" \
  "$PROJECT_DIR/Sources/GabiAI.swift" \
  "$PROJECT_DIR/Sources/VoiceAssistant.swift" \
  "$PROJECT_DIR/Sources/GabiView.swift" \
  "$PROJECT_DIR/Sources/GabiWindowController.swift" \
  "$PROJECT_DIR/Sources/StatusBarController.swift" \
  "$PROJECT_DIR/Sources/main.swift" \
  -o "$MACOS_DIR/$APP_NAME"

# Copy sprites and sounds
cp "$PROJECT_DIR/assets/sprites/"*.png "$RESOURCES_DIR/sprites/"
if [ -d "$PROJECT_DIR/assets/sounds" ]; then
  mkdir -p "$RESOURCES_DIR/sounds"
  cp "$PROJECT_DIR/assets/sounds/"* "$RESOURCES_DIR/sounds/" 2>/dev/null || true
fi

# Generate macOS App Icon (.icns) from idle_front.png
python3 - "$PROJECT_DIR/assets/sprites/idle_front.png" "$RESOURCES_DIR/AppIcon.icns" <<'PY'
import sys
from PIL import Image
src = Image.open(sys.argv[1]).convert("RGBA")
icon = src.resize((512, 512), Image.Resampling.NEAREST)
icon.save(sys.argv[2], format="ICNS")
PY

# Create Info.plist
cat > "$CONTENTS/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>Gabi</string>
    <key>CFBundleDisplayName</key>
    <string>Gabi</string>
    <key>CFBundleIdentifier</key>
    <string>com.samilz.gabi-pet</string>
    <key>CFBundleVersion</key>
    <string>1.0</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleExecutable</key>
    <string>Gabi</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSMicrophoneUsageDescription</key>
    <string>Gabi necesita el micrófono para escuchar tus órdenes cuando pulses ⌥G.</string>
    <key>NSSpeechRecognitionUsageDescription</key>
    <string>Gabi usa el reconocimiento de voz de macOS para entender lo que le pides.</string>
</dict>
</plist>
PLIST

echo "Done! Built $APP_BUNDLE"
