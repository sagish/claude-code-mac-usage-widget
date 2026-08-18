# AGENTS.md

## Project overview

A single-file macOS floating widget (Swift/AppKit, no dependencies, no Xcode
project) that shows Claude Code usage limits. All application code lives in
`ClaudeUsageWidget.swift`. See `SPEC.md` for the full behavioral spec.

## Setup and build

- Requires only Xcode Command Line Tools (`swiftc`). No package manager, no
  `Package.swift` — do not introduce one for small changes.
- Build: `swiftc -O -o ClaudeUsageWidget ClaudeUsageWidget.swift`
- Run: `./ClaudeUsageWidget &` (background it; it's a GUI app with no Dock
  icon). Kill with `pkill -f ClaudeUsageWidget` before relaunching a rebuild,
  otherwise two widgets stack on screen.
- The compiled binary is gitignored — never commit it.

## Testing and verification

- There is no test suite. Verify changes by building (must compile with zero
  warnings from the snippet above) and running the widget.
- API integration can be checked without the UI:
  - `swift debug-usage.swift` — prints the raw `/api/oauth/usage` response
  - `swift debug-profile.swift` — prints the raw `/api/oauth/profile` response
- Both need a signed-in Claude Code (token in the macOS Keychain under
  `Claude Code-credentials`, or `~/.claude/.credentials.json`). First keychain
  access triggers a user-facing macOS prompt — expect it in manual runs.

## Code style

- Plain AppKit with fixed-frame layout (no Auto Layout, no SwiftUI, no
  storyboards). Panel size is hardcoded in `buildPanel()`; positions are
  computed top-down from `height` — when adding a row, grow `height` and shift
  the y-offsets below the insertion point.
- Keep everything in the one source file, organized under the existing
  `// MARK:` sections (Data, Credentials, Fetch + parse, Views, App).
- Networking uses `URLSession` with completions dispatched to the main queue;
  parsing uses `JSONSerialization` with defensive optional casts (the API
  shape has changed before — prefer the `limits` array, keep legacy fallbacks).

## Security constraints

- The OAuth token must never be logged, printed, or sent anywhere except
  `api.anthropic.com`. Debug scripts print response bodies only, never the
  token or raw credentials.
- Do not add analytics, crash reporting, or any third-party network calls.

## PR / commit guidelines

- Update `SPEC.md` when behavior changes, and `README.md` when setup or
  user-visible features change.
- Refresh `screenshot.png` after UI changes (capture the live widget window).
- Commit messages: imperative summary line; body explains the why.
