# Claude Usage Widget

A small always-on-top floating widget for macOS showing your Claude Code usage
limits — current session, all-models weekly, and Fable weekly — the same data
as [claude.ai/settings/usage](https://claude.ai/settings/usage).

Native Swift/AppKit, no dependencies.

## How it works

Reads your Claude Code OAuth token from the macOS Keychain (item
`Claude Code-credentials`, falling back to `~/.claude/.credentials.json`) and
polls `https://api.anthropic.com/api/oauth/usage` every minute. Your name and
org come from `/api/oauth/profile`. The token never leaves your machine except
to Anthropic's API.

## Build & run

```sh
swiftc -O -o ClaudeUsageWidget ClaudeUsageWidget.swift
./ClaudeUsageWidget &
```

On first run, macOS asks to allow Keychain access — choose **Always Allow**.

## Usage

- Drag anywhere; position is remembered. Visible on all Spaces, no Dock icon.
- Pulsing dot: green = live, red = last fetch failed (footer shows why).
- ↻ or right-click → **Refresh now**; right-click → **Quit** to close.
- Bars turn orange at 70% and red at 90%. Hover a row for the exact reset time.

## Debugging

`swift debug-usage.swift` and `swift debug-profile.swift` print the raw API
responses if the format ever changes.
