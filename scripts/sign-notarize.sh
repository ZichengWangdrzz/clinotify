#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_PATH="${APP_PATH:-$ROOT_DIR/.build/app/CLINotify.app}"
DMG_PATH="${DMG_PATH:-$ROOT_DIR/.build/release/CLINotify.dmg}"
IDENTITY="${DEVELOPER_ID_APPLICATION:-}"
APPLE_ID="${APPLE_ID:-}"
TEAM_ID="${APPLE_TEAM_ID:-}"
PASSWORD="${APP_SPECIFIC_PASSWORD:-}"

if [[ ! -d "$APP_PATH" ]]; then
  "$ROOT_DIR/scripts/build-app-bundle.sh" >/dev/null
fi

if [[ -z "$IDENTITY" || -z "$APPLE_ID" || -z "$TEAM_ID" || -z "$PASSWORD" || "${DRY_RUN:-0}" == "1" ]]; then
  cat <<EOF
Dry run only. Set these environment variables to sign and notarize:
  DEVELOPER_ID_APPLICATION
  APPLE_ID
  APPLE_TEAM_ID
  APP_SPECIFIC_PASSWORD

Would run:
  codesign --force --deep --options runtime --sign "$IDENTITY" "$APP_PATH"
  scripts/create-dmg.sh
  xcrun notarytool submit "$DMG_PATH" --apple-id "$APPLE_ID" --team-id "$TEAM_ID" --password "***" --wait
  xcrun stapler staple "$DMG_PATH"
EOF
  exit 0
fi

codesign --force --deep --options runtime --sign "$IDENTITY" "$APP_PATH"
"$ROOT_DIR/scripts/create-dmg.sh" >/dev/null
xcrun notarytool submit "$DMG_PATH" \
  --apple-id "$APPLE_ID" \
  --team-id "$TEAM_ID" \
  --password "$PASSWORD" \
  --wait
xcrun stapler staple "$DMG_PATH"

echo "$DMG_PATH"
