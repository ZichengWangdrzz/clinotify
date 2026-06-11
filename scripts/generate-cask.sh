#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DMG_PATH="${DMG_PATH:-$ROOT_DIR/.build/release/CLINotify.dmg}"
VERSION="${VERSION:-0.1.0}"
DOWNLOAD_URL="${DOWNLOAD_URL:-https://example.com/downloads/CLINotify-$VERSION.dmg}"
HOMEPAGE="${HOMEPAGE:-https://github.com/ZichengWangdrzz/clinotify}"
OUT_PATH="${OUT_PATH:-$ROOT_DIR/.build/release/clinotify.rb}"

if [[ ! -f "$DMG_PATH" ]]; then
  echo "Missing DMG at $DMG_PATH. Run scripts/create-dmg.sh first." >&2
  exit 1
fi

# Guard against shipping a bogus cask from a manual run: the placeholder URL would produce a .rb that
# brew can't install. CI overrides DOWNLOAD_URL with the real release asset (see release.yml).
if [[ "$DOWNLOAD_URL" == *example.com* ]]; then
  echo "DOWNLOAD_URL still points at example.com. Set DOWNLOAD_URL to the real release asset URL." >&2
  exit 1
fi

mkdir -p "$(dirname "$OUT_PATH")"
SHA256="$(shasum -a 256 "$DMG_PATH" | awk '{print $1}')"

# Heredoc is unquoted so $VERSION/$SHA256/$DOWNLOAD_URL/$HOMEPAGE interpolate. `#{appdir}` has no `$`
# so it stays literal for Ruby; the caveats text deliberately avoids `$` and backticks.
cat > "$OUT_PATH" <<EOF
cask "clinotify" do
  version "$VERSION"
  sha256 "$SHA256"

  url "$DOWNLOAD_URL"
  name "CLINotify"
  desc "Menu bar alerts for Claude Code and Codex CLI sessions"
  homepage "$HOMEPAGE"

  depends_on macos: :ventura

  app "CLINotify.app"
  # Put the bundled CLI on Homebrew's PATH so users can run "clinotify install" right after install.
  binary "#{appdir}/CLINotify.app/Contents/MacOS/clinotify"

  # Stop the running menu-bar daemon AND tear down the autostart LaunchAgent (label == bundle id,
  # written by "clinotify autostart on" with KeepAlive) BEFORE Homebrew deletes the app — otherwise
  # launchd keeps relaunching the now-missing binary. (launchctl before quit per cask conventions.)
  # Use trash: not delete: for the plist. It lives in the user's own home and needs no root, but
  # Homebrew's delete: always shells out to sudo rm -- which would prompt for a password on EVERY
  # upgrade/uninstall (and fails outright in a non-interactive shell). trash: runs as the user.
  # (No backticks/dollar signs in these comments: this heredoc is unquoted, so they would execute.)
  uninstall launchctl: "app.clinotify.helper",
            quit:      "app.clinotify.helper",
            trash:     "~/Library/LaunchAgents/app.clinotify.helper.plist"

  # Deep clean (alphabetized per cask conventions). Globs cover both production (CLINotify) and any
  # dev (CLINotify-Dev) state a developer build may have left, plus the autostart plist for --zap.
  zap trash: [
    "~/Library/Application Support/CLINotify*",
    "~/Library/LaunchAgents/app.clinotify.helper.plist",
    "~/Library/Preferences/app.clinotify.helper*.plist",
  ]

  caveats <<~CAVEATS
    Before "brew uninstall --cask clinotify", run:
        clinotify uninstall
    That strips the Claude Code / Codex hooks CLINotify added to
    ~/.claude/settings.json and ~/.codex/config.toml and removes the
    ~/.local/bin/clinotify symlink. Homebrew cannot edit those files,
    so skipping it leaves dangling hooks that error on every session event.
  CAVEATS
end
EOF

echo "$OUT_PATH"
