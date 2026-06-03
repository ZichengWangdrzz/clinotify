# CLINotify

> Native macOS menu-bar helper that pops a desktop toast — a waving pixel-art crab, a speech bubble with the project/session name, and a sound — the moment your CLI coding agent finishes a task or needs your input.

CLINotify watches **Claude Code** and **Codex** sessions and tells you when they're done or waiting on you, so you can step away without babysitting the terminal. The toast is a screen-corner window, so it works in **every** terminal — Ghostty, iTerm2, Apple Terminal, kitty, WezTerm, the VS Code terminal, and inside tmux — because it never targets the terminal itself.

- One toast per session. Set it up once; new sessions auto-register.
- Click the toast to dismiss. On Claude Code it also auto-dismisses when you start typing again.
- Menu-bar only — no Dock icon.
- Free core experience. Some skins/sounds are paid (commercial product, Lemon Squeezy licensing).

## Demo

![demo](docs/demo.gif)

> TODO: record and add `docs/demo.gif`.

## Install

### Homebrew (cask)

```sh
brew install --cask ZichengWangdrzz/clinotify/clinotify
```

### Direct download

1. Download `CLINotify.dmg` from the [Releases](https://github.com/ZichengWangdrzz/CLINotify/releases) page.
2. Open the DMG and drag **CLINotify** to `/Applications`.

Release builds are signed and notarized by Apple, so Gatekeeper opens them normally. (If you ever run an unsigned **local** build, right-click the app → **Open** the first time.)

## First run / setup

1. Launch **CLINotify** from `/Applications`. It lives in the menu bar (the crab icon) — there is no Dock icon.
2. Open the menu → **Install Hooks** (or run `clinotify install` from a terminal).
3. That's it. Start a Claude Code or Codex session as usual; CLINotify registers it and toasts you when the agent finishes or needs input.

## Usage

The bundled CLI is `clinotify`:

```sh
clinotify status                          # show channel, socket, and state dir
clinotify list                            # list registered sessions
clinotify settings                        # view / change skin + sound settings
clinotify test claude-code --label "demo" # fire a test toast
clinotify install                         # install hooks (Claude Code + Codex)
clinotify uninstall                       # remove hooks
```

### Skins

Four independent skin axes, set via `clinotify settings`:

```sh
clinotify settings animation <name>   # the crab animation
clinotify settings bubble    <name>   # the speech-bubble style
clinotify settings frame     <name>   # the toast frame
clinotify settings sound     <name>   # the notification sound
```

Run `clinotify settings` with no arguments to see the current selection and available options. Some skins/sounds are paid.

## Requirements

- macOS 13 (Ventura) or later.

## Build from source

```sh
swift build
swift test
./scripts/build-app-bundle.sh          # → .build/app/CLINotify.app
open .build/app/CLINotify.app
```

## Development / dev channel

CLINotify ships two build channels that run **side by side** without colliding:

| Channel    | App                 | CLI            | State dir                                          | Bundle id                 |
|------------|---------------------|----------------|----------------------------------------------------|---------------------------|
| production | `CLINotify.app`     | `clinotify`    | `~/Library/Application Support/CLINotify/`          | `app.clinotify.helper`     |
| dev        | `CLINotify Dev.app` | `clinotify-dev`| `~/Library/Application Support/CLINotify-Dev/`      | `app.clinotify.helper.dev` |

The channel is selected by the invoked binary name (`clinotify-dev`) or by setting `CLINOTIFY_CHANNEL=dev`. Each channel has its own Unix socket and state directory, so the installed production app and a dev build can both run at once.

```sh
CHANNEL=dev ./scripts/build-app-bundle.sh    # → ".build/app/CLINotify Dev.app"
open ".build/app/CLINotify Dev.app"
clinotify-dev install                        # install hooks for the dev channel

clinotify status        # production: its socket + state dir
clinotify-dev status    # dev: a separate socket + state dir
```

## How it works

```
agent event ──► clinotify (hook) ──► Unix socket ──► CLINotifyApp (menu-bar daemon) ──► toast
```

- `clinotify` is installed as a **hook** into Claude Code (`~/.claude/settings.json`: `Stop` / `Notification` / `UserPromptSubmit` / `SessionEnd`) and Codex (`~/.codex/config.toml`: `notify`).
- On each event the hook sends a small message over a **Unix domain socket** to the long-running menu-bar daemon (`CLINotifyApp`).
- The daemon renders the screen-corner toast, keyed by the agent's session id. Because the toast is its own window, it is **terminal-agnostic** — it never tries to attach to or draw inside any terminal.

## Release

Releases are distributed two ways from the same signed, notarized, stapled DMG:

1. A **GitHub Release** with `CLINotify.dmg` attached.
2. A **Homebrew cask** in the `ZichengWangdrzz/homebrew-clinotify` tap.

Tagging a `v*` tag triggers `.github/workflows/release.yml`, which builds, signs+notarizes, publishes the release, and generates the cask. See that workflow for the repo secrets it requires.

## License

CLINotify is licensed under the [Elastic License 2.0](LICENSE) (`Elastic-2.0`) — a source-available license. The core app is free to use, copy, modify, and redistribute. You may **not** circumvent the license-key functionality that gates paid skins/sounds, and you may not offer CLINotify as a hosted/managed service. Copyright © 2026 devpsycho.
