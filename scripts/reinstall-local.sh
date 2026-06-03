#!/usr/bin/env bash
#
# reinstall-local.sh — build + (re)install one CLINotify channel from the CURRENT source, in one step.
#
# This is the local "promote": make a channel reflect exactly the code you have right now (e.g. the
# production build you're about to push), then exercise it like a real user would.
#
#   Dev loop (develop + test):     CHANNEL=dev ./scripts/reinstall-local.sh
#   Promote to local production:   ./scripts/reinstall-local.sh        # CHANNEL defaults to production
#
# Parity model: there is ONE source tree (src/CLINotify). `dev` and `production` are two build
# CHANNELS of that same source — identical code, different identity (app name, bundle id, CLI name,
# state dir, socket, hooks). So "keep production the same as dev" = build BOTH from the same source
# without editing in between; they are then byte-identical logic.
#
# Restart is autostart-aware: if the channel is launchd-managed (its LaunchAgent plist exists, i.e.
# you ran `clinotify autostart on`), the daemon is restarted via `launchctl kickstart` so it picks up
# the new binary — we must NOT pkill it, because launchd KeepAlive would just fight us. Otherwise the
# daemon is stopped and relaunched manually via `open` (waiting for the single-instance flock to free).
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CHANNEL="${CHANNEL:-production}"

case "$CHANNEL" in
  dev)        APP_BASENAME="CLINotify Dev"; LABEL="app.clinotify.helper.dev" ;;
  production) APP_BASENAME="CLINotify";     LABEL="app.clinotify.helper" ;;
  *) echo "reinstall-local.sh: CHANNEL must be 'production' or 'dev' (got '$CHANNEL')" >&2; exit 2 ;;
esac

APP_DIR="$ROOT_DIR/.build/app/$APP_BASENAME.app"
DAEMON="$APP_DIR/Contents/MacOS/CLINotifyApp"
CLI="$APP_DIR/Contents/MacOS/clinotify"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
GUI="gui/$(id -u)"
# Escape regex metachars (notably '.') so the pattern matches this channel's path literally and can
# never accidentally match the other channel (e.g. 'CLINotify.app' vs 'CLINotify Dev.app').
DAEMON_PATTERN="$(printf '%s' "$DAEMON" | sed 's/[.[\*^$]/\\&/g')"

echo "==> [$CHANNEL] building the app bundle"
CHANNEL="$CHANNEL" "$ROOT_DIR/scripts/build-app-bundle.sh" >/dev/null
echo "    $APP_DIR"

echo "==> [$CHANNEL] refreshing CLI symlink + Claude/Codex hooks"
# Direct exec of the bundle binary (named 'clinotify' for both channels), so force the channel.
CLINOTIFY_CHANNEL="$CHANNEL" "$CLI" install

if [ -f "$PLIST" ]; then
  # Autostart is ON for this channel: launchd owns the daemon. Restart it via kickstart so it execs
  # the freshly-built binary. Do NOT pkill — KeepAlive would immediately resurrect the old one and
  # the two would fight. kickstart -k = stop-if-running + start.
  echo "==> [$CHANNEL] autostart is on -> restarting via launchd (kickstart)"
  if ! launchctl kickstart -k "$GUI/$LABEL" 2>/dev/null; then
    # Plist present but not currently loaded (e.g. fresh login not yet reached): load then kick.
    launchctl bootstrap "$GUI" "$PLIST" 2>/dev/null || true
    launchctl kickstart -k "$GUI/$LABEL" 2>/dev/null || true
  fi
else
  echo "==> [$CHANNEL] stopping the old daemon (this channel only; the other keeps running)"
  if pkill -f "$DAEMON_PATTERN" 2>/dev/null; then
    # CRITICAL: wait for the old daemon to FULLY exit before relaunching. It holds an exclusive
    # single-instance flock (helper.lock); if `open` starts the new instance while the old one is
    # still dying, the new instance can't get the lock and self-exits — leaving NO daemon at all
    # (the bug: "sound but no toast"). Poll until gone, escalating to SIGKILL if it refuses to die.
    for _ in $(seq 1 50); do pgrep -f "$DAEMON_PATTERN" >/dev/null 2>&1 || break; sleep 0.1; done
    if pgrep -f "$DAEMON_PATTERN" >/dev/null 2>&1; then
      echo "    still alive after ~5s; sending SIGKILL"
      pkill -9 -f "$DAEMON_PATTERN" 2>/dev/null || true
      for _ in $(seq 1 20); do pgrep -f "$DAEMON_PATTERN" >/dev/null 2>&1 || break; sleep 0.1; done
    fi
    echo "    stopped"
  else
    echo "    (none running)"
  fi

  echo "==> [$CHANNEL] launching the daemon"
  CLINOTIFY_CHANNEL="$CHANNEL" "$CLI" launch || true
  # Belt-and-suspenders: confirm an actual daemon PROCESS exists (not just a transiently-reachable
  # socket). Retry the launch once if it didn't stick.
  if ! pgrep -f "$DAEMON_PATTERN" >/dev/null 2>&1; then
    echo "    daemon process not present after launch; retrying open once"
    open "$APP_DIR" || true
  fi
fi

# Confirm a live daemon PID + reachability regardless of which restart path ran.
for _ in $(seq 1 30); do pgrep -f "$DAEMON_PATTERN" >/dev/null 2>&1 && break; sleep 0.2; done
pgrep -f "$DAEMON_PATTERN" >/dev/null 2>&1 \
  && echo "    daemon running (pid $(pgrep -f "$DAEMON_PATTERN" | head -1))" \
  || echo "    WARNING: daemon still not running"

echo
CLINOTIFY_CHANNEL="$CHANNEL" "$CLI" status
echo
echo "Done — '$CHANNEL' now mirrors the current source."
