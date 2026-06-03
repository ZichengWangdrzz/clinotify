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

# DRY RUN is an explicit opt-in (DRY_RUN=1). Missing secrets in a real run are a hard error below, so a
# misconfigured CI fails loudly here instead of silently producing no DMG and erroring at the upload step.
if [[ "${DRY_RUN:-0}" == "1" ]]; then
  cat <<EOF
Dry run (DRY_RUN=1). Set DEVELOPER_ID_APPLICATION / APPLE_ID / APPLE_TEAM_ID / APP_SPECIFIC_PASSWORD to
sign + notarize for real. The real run does, in order:
  # 1. Sign inside-out (nested execs first, then the bundle); secure timestamp + hardened runtime; no --deep:
  codesign --force --timestamp --options runtime --sign "<identity>" "$APP_PATH/Contents/MacOS/clinotify"
  codesign --force --timestamp --options runtime --sign "<identity>" "$APP_PATH/Contents/MacOS/CLINotifyApp"
  codesign --force --timestamp --options runtime --sign "<identity>" "$APP_PATH"
  # 2. Verify + gate: fail if any Mach-O carries get-task-allow (Apple rejects it under hardened runtime):
  codesign --verify --strict --deep --verbose=2 "$APP_PATH"
  # 3. Notarize + staple the .app itself (so the installed app opens offline); require status=Accepted:
  ditto -c -k --keepParent "$APP_PATH" "$APP_PATH.zip"
  xcrun notarytool submit "$APP_PATH.zip" --apple-id "<id>" --team-id "<team>" --password "***" --wait
  xcrun stapler staple "$APP_PATH" && xcrun stapler validate "$APP_PATH"
  # 4. Build the DMG FROM the stapled app, then notarize + staple the DMG too:
  scripts/create-dmg.sh
  xcrun notarytool submit "$DMG_PATH" --apple-id "<id>" --team-id "<team>" --password "***" --wait
  xcrun stapler staple "$DMG_PATH" && xcrun stapler validate "$DMG_PATH"
  # 5. Final Gatekeeper gate:
  spctl -a -t open --context context:primary-signature -vv "$DMG_PATH"
EOF
  exit 0
fi

# Real run: require all four notarization secrets (fail fast — don't silently degrade to a no-op).
missing=()
if [[ -z "$IDENTITY" ]]; then missing+=(DEVELOPER_ID_APPLICATION); fi
if [[ -z "$APPLE_ID" ]]; then missing+=(APPLE_ID); fi
if [[ -z "$TEAM_ID" ]]; then missing+=(APPLE_TEAM_ID); fi
if [[ -z "$PASSWORD" ]]; then missing+=(APP_SPECIFIC_PASSWORD); fi
if (( ${#missing[@]} )); then
  echo "ERROR: missing signing/notarization secrets: ${missing[*]}" >&2
  echo "Set DRY_RUN=1 to intentionally skip signing." >&2
  exit 1
fi

# Assert the final notarization status is "Accepted". notarytool exits 0 even when the result is
# Invalid (only tool/transport failures are nonzero), so the status must be checked explicitly.
notarize() {
  local target="$1" out status
  out="$(xcrun notarytool submit "$target" \
    --apple-id "$APPLE_ID" --team-id "$TEAM_ID" --password "$PASSWORD" \
    --wait --output-format json)"
  echo "$out"
  status="$(printf '%s' "$out" | /usr/bin/python3 -c 'import json,sys; print(json.load(sys.stdin).get("status",""))')"
  if [[ "$status" != "Accepted" ]]; then
    echo "ERROR: notarization status for $target: '$status' (expected Accepted)" >&2
    return 1
  fi
}

# 1. Sign inside-out: nested executables first, then the bundle. --timestamp (notarization requires a
#    secure timestamp) + --options runtime (hardened runtime). Avoid --deep — it is deprecated and
#    unreliable for a bundle with two main-level executables (CLINotifyApp daemon + clinotify CLI).
for exe in clinotify CLINotifyApp; do
  codesign --force --timestamp --options runtime --sign "$IDENTITY" "$APP_PATH/Contents/MacOS/$exe"
done
codesign --force --timestamp --options runtime --sign "$IDENTITY" "$APP_PATH"

# 2. Verify, and gate on get-task-allow (a debug-only entitlement Apple rejects under hardened runtime).
#    A release build does not carry it, but assert so a stray debug build can never reach the notary.
codesign --verify --strict --deep --verbose=2 "$APP_PATH"
for mach in "$APP_PATH" "$APP_PATH/Contents/MacOS/clinotify" "$APP_PATH/Contents/MacOS/CLINotifyApp"; do
  if codesign -d --entitlements - "$mach" 2>/dev/null | grep -q "get-task-allow"; then
    echo "ERROR: $mach carries com.apple.security.get-task-allow — build release (UNIVERSAL=1 CONFIGURATION=release) before signing." >&2
    exit 1
  fi
done

# 3. Notarize + staple the .app itself, so the installed app carries its own ticket and opens offline.
APP_ZIP="$APP_PATH.zip"
ditto -c -k --keepParent "$APP_PATH" "$APP_ZIP"
notarize "$APP_ZIP"
xcrun stapler staple "$APP_PATH"
xcrun stapler validate "$APP_PATH"
rm -f "$APP_ZIP"

# 4. Build the DMG FROM the stapled app, then notarize + staple the DMG for download-time Gatekeeper.
"$ROOT_DIR/scripts/create-dmg.sh" >/dev/null
notarize "$DMG_PATH"
xcrun stapler staple "$DMG_PATH"
xcrun stapler validate "$DMG_PATH"

# 5. Final Gatekeeper assessment — fail the job if the DMG would be blocked on a user's machine.
spctl -a -t open --context context:primary-signature -vv "$DMG_PATH"

echo "$DMG_PATH"
