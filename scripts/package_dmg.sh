#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_BUNDLE="$PROJECT_DIR/Gabi.app"
DMG_OUT="$PROJECT_DIR/Gabi-macOS.dmg"
STAGE_DIR="$PROJECT_DIR/.tmp_dmg_stage"

if [ ! -d "$APP_BUNDLE" ]; then
  "$PROJECT_DIR/build.sh"
fi

rm -rf "$STAGE_DIR" "$DMG_OUT"
mkdir -p "$STAGE_DIR"
cp -R "$APP_BUNDLE" "$STAGE_DIR/"
ln -s /Applications "$STAGE_DIR/Applications"

hdiutil create \
  -volname "Gabi" \
  -srcfolder "$STAGE_DIR" \
  -ov \
  -format UDZO \
  "$DMG_OUT"

rm -rf "$STAGE_DIR"
echo "Created $DMG_OUT"
