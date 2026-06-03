#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_PATH="${APP_PATH:-$ROOT_DIR/.build/app/CLINotify.app}"
RELEASE_DIR="${RELEASE_DIR:-$ROOT_DIR/.build/release}"
DMG_PATH="${DMG_PATH:-$RELEASE_DIR/CLINotify.dmg}"
VOLUME_NAME="${VOLUME_NAME:-CLINotify}"

if [[ ! -d "$APP_PATH" ]]; then
  "$ROOT_DIR/scripts/build-app-bundle.sh" >/dev/null
fi

mkdir -p "$RELEASE_DIR"
rm -f "$DMG_PATH"
hdiutil create \
  -volname "$VOLUME_NAME" \
  -srcfolder "$APP_PATH" \
  -ov \
  -format UDZO \
  "$DMG_PATH"

echo "$DMG_PATH"
