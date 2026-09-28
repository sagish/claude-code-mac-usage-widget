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
   git clone git@github.com:sagish/claude-code-mac-usage-widget.git
   cd claude-code-mac-usage-widget
   ```
3. **Build and run**:
   ```sh
   ./start          # build if needed, stop any old instance, then run
   ./start --force  # always rebuild
   ./start --stop   # stop the running widget
   ```
   On first run macOS asks to allow Keychain access to your Claude Code
   credentials — click **Always Allow**. The widget appears in the top-right
   corner; drag it wherever you like.
4. **(Optional) Start at login**: tick the checkbox at the bottom of the widget.
   It writes `~/Library/LaunchAgents/com.empathy.claude-usage-widget.plist`
   pointing at the binary's current location; untick to remove it. Effective at
   next login — don't move the binary afterwards, or re-tick the box if you do.

## How it works

It reads your Claude Code OAuth token from the macOS Keychain (falling back to
`~/.claude/.credentials.json`) and polls Anthropic's usage endpoint every
5 minutes — slow on purpose, so it never trips the API's rate limit. An expired
token is renewed with the same OAuth refresh grant Claude Code uses, so the
widget keeps working after a long break. Tokens never leave your machine except
to Anthropic.

## Usage

- Drag anywhere; position is remembered. Visible on all Spaces, no Dock icon.
- Pulsing dot: green = up to date, yellow = temporary hiccup (it retries on its
  own), red = you need to sign in again. Hover for the detail and the last
  update time; errors never replace the numbers on the panel.
- ↻ or right-click → **Refresh now**; right-click → **Quit** to close.
- Bars turn orange at 70% and red at 90%. Hover a row for the exact reset time.
- Floater in the way? Tick **Menu bar** (bottom-right) to tuck the widget into
  the menu bar as `S 42% · W 18% · F 9%` (session, weekly, Fable). Click it to
  drop the full panel down, right-click for Refresh / move back / Quit. Untick,
  or right-click → **Move back to floating widget**, to float again at the
  remembered spot.

## Debugging

`swift debug-usage.swift` and `swift debug-profile.swift` print the raw API
responses if the format ever changes.
