#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DMG_PATH="${DMG_PATH:-$ROOT_DIR/.build/release/CLINotify.dmg}"
VERSION="${VERSION:-0.1.0}"
DOWNLOAD_URL="${DOWNLOAD_URL:-https://example.com/downloads/CLINotify-$VERSION.dmg}"
OUT_PATH="${OUT_PATH:-$ROOT_DIR/.build/release/clinotify.rb}"

if [[ ! -f "$DMG_PATH" ]]; then
  echo "Missing DMG at $DMG_PATH. Run scripts/create-dmg.sh first." >&2
  exit 1
fi

mkdir -p "$(dirname "$OUT_PATH")"
SHA256="$(shasum -a 256 "$DMG_PATH" | awk '{print $1}')"

cat > "$OUT_PATH" <<EOF
cask "clinotify" do
  version "$VERSION"
  sha256 "$SHA256"

  url "$DOWNLOAD_URL"
  name "CLINotify"
  desc "Menu bar alerts for Claude Code and Codex CLI sessions"
  homepage "https://example.com/clinotify"

  app "CLINotify.app"

  zap trash: [
    "~/Library/Application Support/CLINotify",
    "~/Library/Preferences/app.clinotify.helper.plist",
  ]
end
EOF

echo "$OUT_PATH"
