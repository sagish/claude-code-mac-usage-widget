# Claude Usage Widget

A small always-on-top floating widget for macOS showing your Claude Code usage
limits — current session, all-models weekly, and Fable weekly — the same data
as [claude.ai/settings/usage](https://claude.ai/settings/usage).

Native Swift/AppKit, no dependencies.

![Claude Usage Widget](screenshot.png)

## Quick setup

1. **Prereqs**: Xcode Command Line Tools (`xcode-select --install`) and a
   Claude Code sign-in (run `claude` once and log in, if you haven't).
2. **Clone and build**:
   ```sh
   git clone git@github.com:empathycom/claude-usage-widget.git
   cd claude-usage-widget
   swiftc -O -o ClaudeUsageWidget ClaudeUsageWidget.swift
   ```
3. **Run it**:
   ```sh
   ./ClaudeUsageWidget &
   ```
   macOS will ask to allow Keychain access to your Claude Code credentials —
   click **Always Allow**. The widget appears in the top-right corner; drag it
   wherever you like.
4. **(Optional) Start at login**:
   ```sh
   cat > ~/Library/LaunchAgents/com.empathy.claude-usage-widget.plist <<EOF
   <?xml version="1.0" encoding="UTF-8"?>
   <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
   <plist version="1.0"><dict>
     <key>Label</key><string>com.empathy.claude-usage-widget</string>
     <key>ProgramArguments</key><array><string>$PWD/ClaudeUsageWidget</string></array>
     <key>RunAtLoad</key><true/>
   </dict></plist>
   EOF
   launchctl load ~/Library/LaunchAgents/com.empathy.claude-usage-widget.plist
   ```

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
