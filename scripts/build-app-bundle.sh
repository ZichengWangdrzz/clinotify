#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIGURATION="${CONFIGURATION:-debug}"
CHANNEL="${CHANNEL:-production}"
VERSION="${VERSION:-0.1.0}"
BUILD_DIR="$ROOT_DIR/.build/arm64-apple-macosx/$CONFIGURATION"

# Channel identity: the dev channel is a fully separate app so it can run beside the installed
# production build. The daemon learns its channel from CLINOTIFY_CHANNEL (injected via LSEnvironment).
if [[ "$CHANNEL" == "dev" ]]; then
  APP_BASENAME="CLINotify Dev"
  BUNDLE_ID="app.clinotify.helper.dev"
  BUNDLE_NAME="CLINotify Dev"
  LS_ENVIRONMENT=$'  <key>LSEnvironment</key>\n  <dict>\n    <key>CLINOTIFY_CHANNEL</key>\n    <string>dev</string>\n  </dict>\n'
else
  APP_BASENAME="CLINotify"
  BUNDLE_ID="app.clinotify.helper"
  BUNDLE_NAME="CLINotify"
  LS_ENVIRONMENT=""
fi

APP_DIR="${APP_DIR:-$ROOT_DIR/.build/app/$APP_BASENAME.app}"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

cd "$ROOT_DIR"
CLANG_MODULE_CACHE_PATH="${CLANG_MODULE_CACHE_PATH:-/tmp/clinotify-clang-cache}" swift build

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

cp "$BUILD_DIR/CLINotifyApp" "$MACOS_DIR/CLINotifyApp"
cp "$BUILD_DIR/clinotify" "$MACOS_DIR/clinotify"
chmod 755 "$MACOS_DIR/CLINotifyApp" "$MACOS_DIR/clinotify"

if [[ -d "$ROOT_DIR/Resources" ]]; then
  rsync -a "$ROOT_DIR/Resources/" "$RESOURCES_DIR/"
fi

cat > "$CONTENTS_DIR/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleExecutable</key>
  <string>CLINotifyApp</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>$BUNDLE_NAME</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>$VERSION</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSMinimumSystemVersion</key>
  <string>13.0</string>
  <key>LSUIElement</key>
  <true/>
${LS_ENVIRONMENT}  <key>NSHumanReadableCopyright</key>
  <string>Copyright 2026 devpsycho</string>
</dict>
</plist>
PLIST

echo "$APP_DIR"
