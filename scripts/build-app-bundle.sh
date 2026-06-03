#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# Default to debug for fast local iteration (reinstall-local.sh); the release pipeline sets
# CONFIGURATION=release UNIVERSAL=1 (see .github/workflows/release.yml) so users get an optimized,
# Intel+Apple-Silicon build with no debug get-task-allow entitlement (which would fail notarization).
CONFIGURATION="${CONFIGURATION:-debug}"
UNIVERSAL="${UNIVERSAL:-0}"
CHANNEL="${CHANNEL:-production}"
VERSION="${VERSION:-0.1.0}"

# swift build product layout: a single-arch build lands in .build/<arch>-apple-macosx/<config>; a
# universal (--arch arm64 --arch x86_64) build lands in the merged .build/apple/Products/<Config>
# (capitalized). BUILD_DIR + the swift build flags must agree, so derive both from UNIVERSAL.
if [[ "$UNIVERSAL" == "1" ]]; then
  SWIFT_ARCH_FLAGS=(--arch arm64 --arch x86_64)
  CONFIG_CAP="$(printf '%s' "${CONFIGURATION:0:1}" | tr '[:lower:]' '[:upper:]')${CONFIGURATION:1}"
  BUILD_DIR="$ROOT_DIR/.build/apple/Products/$CONFIG_CAP"
else
  SWIFT_ARCH_FLAGS=()
  BUILD_DIR="$ROOT_DIR/.build/$(uname -m)-apple-macosx/$CONFIGURATION"
fi

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
# `${arr[@]+"${arr[@]}"}` safely expands to nothing when the array is empty under `set -u` (macOS ships
# bash 3.2, where a bare "${arr[@]}" on an empty array is an "unbound variable" error).
CLANG_MODULE_CACHE_PATH="${CLANG_MODULE_CACHE_PATH:-/tmp/clinotify-clang-cache}" \
  swift build -c "$CONFIGURATION" ${SWIFT_ARCH_FLAGS[@]+"${SWIFT_ARCH_FLAGS[@]}"}

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

cp "$BUILD_DIR/CLINotifyApp" "$MACOS_DIR/CLINotifyApp"
cp "$BUILD_DIR/clinotify" "$MACOS_DIR/clinotify"
chmod 755 "$MACOS_DIR/CLINotifyApp" "$MACOS_DIR/clinotify"

# Assert both Mach-O executables landed (cp+set -e already catch a missing source, but verify exec bit
# and arch explicitly so a packaging regression fails loudly here, not at notarization/runtime).
for bin in CLINotifyApp clinotify; do
  test -x "$MACOS_DIR/$bin" || { echo "missing/non-exec: $MACOS_DIR/$bin" >&2; exit 1; }
  file "$MACOS_DIR/$bin" | grep -q 'Mach-O' || { echo "not a Mach-O binary: $MACOS_DIR/$bin" >&2; exit 1; }
  if [[ "$UNIVERSAL" == "1" ]]; then
    archs="$(lipo -archs "$MACOS_DIR/$bin")"
    [[ "$archs" == *arm64* && "$archs" == *x86_64* ]] \
      || { echo "expected universal (arm64 + x86_64), got '$archs' for $bin" >&2; exit 1; }
  fi
done

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
