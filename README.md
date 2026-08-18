# Claude Usage Widget

A small always-on-top floating widget for macOS showing your Claude Code usage
limits — current session, all-models weekly, and Fable weekly — the same data
as [claude.ai/settings/usage](https://claude.ai/settings/usage).

Native Swift/AppKit, no dependencies.

![Claude Usage Widget](screenshot.png)

## Quick setup

1. **Prereqs**: Xcode Command Line Tools (`xcode-select --install`) and a
   Claude Code sign-in (run `claude` once and log in, if you haven't).
2. **Clone**:
   ```sh
   git clone git@github.com:empathycom/claude-usage-widget.git
   cd claude-usage-widget
   ```
3. **Build and run**:
   ```sh
   ./start
   ```
   macOS will ask to allow Keychain access to your Claude Code credentials —
   click **Always Allow**. The widget appears in the top-right corner; drag it
   wherever you like.
4. **(Optional) Start at login**: tick the **Start at login** checkbox at the
   bottom of the widget. It writes a LaunchAgent
   (`~/Library/LaunchAgents/com.empathy.claude-usage-widget.plist`) pointing at
   the binary's current location; untick to remove it. Takes effect at next
   login — don't move the binary afterwards, or re-tick the box if you do.

## How it works

Reads your Claude Code OAuth token from the macOS Keychain (item
`Claude Code-credentials`, falling back to `~/.claude/.credentials.json`) and
polls `https://api.anthropic.com/api/oauth/usage` every minute. Your name and
org come from `/api/oauth/profile`. The token never leaves your machine except
to Anthropic's API.

## Build & run

`./start` compiles the source when it changed, stops a widget that's already
running, and launches a fresh one in the background:

```sh
./start          # build if needed, then run
./start --force  # always rebuild
./start --stop   # stop the running widget
```

On first run, macOS asks to allow Keychain access — choose **Always Allow**.

## Usage

- Drag anywhere; position is remembered. Visible on all Spaces, no Dock icon.
- Pulsing dot: green = live, red = last fetch failed (footer shows why).
- ↻ or right-click → **Refresh now**; right-click → **Quit** to close.
- Bars turn orange at 70% and red at 90%. Hover a row for the exact reset time.
- If the API rate-limits the widget (HTTP 429) it waits out the cool-off the
  server asks for and shows `rate limited — retrying in …`; refreshing by hand
  won't send a request until that passes.

## Debugging

`swift debug-usage.swift` and `swift debug-profile.swift` print the raw API
responses if the format ever changes.
