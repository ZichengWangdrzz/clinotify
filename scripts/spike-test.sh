#!/bin/sh
# Phase 0 feasibility harness. Run this INSIDE each terminal you care about
# (Apple Terminal, iTerm2, Ghostty, tmux, VS Code integrated terminal, SSH session).
#
#   sh scripts/spike-test.sh
#
# It runs the ttyspike binary in two modes and prints each diagnostics report.
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BIN="$ROOT/.build/debug/ttyspike"

if [ ! -x "$BIN" ]; then
  echo "Building ttyspike..."
  (cd "$ROOT" && swift build --product ttyspike >/dev/null)
fi

printf '\n========================================================\n'
printf 'Terminal: %s (TERM=%s)\n' "${TERM_PROGRAM:-?}" "${TERM:-?}"
printf '========================================================\n'

printf '\n[1] DIRECT (interactive stdio) — you should see the crab animate:\n\n'
"$BIN" || true

printf '\n[2] HOOK-STYLE (stdin piped, stdout -> /dev/null) — the crab should STILL\n'
printf '    animate (drawn to /dev/tty), proving a piped/redirected hook can reach\n'
printf '    the visible terminal. Watch the area below and read the report:\n\n'
echo '{"hook_event_name":"Stop"}' | "$BIN" >/dev/null || true

printf '\nDone. KEY SIGNAL: in run [2], did the crab still appear and did the report\n'
printf 'say "open(/dev/tty): OK"? If yes here, the in-terminal overlay is viable in\n'
printf 'this terminal. If it says FAIL errno=6, this terminal needs the fallback.\n'
