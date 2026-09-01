# AGENTS.md

## Project overview

A single-file macOS floating widget (Swift/AppKit, no dependencies, no Xcode
project) that shows Claude Code usage limits. All application code lives in
`ClaudeUsageWidget.swift`. See `SPEC.md` for the full behavioral spec.

## Setup and build

- Requires only Xcode Command Line Tools (`swiftc`). No package manager, no
  `Package.swift` — do not introduce one for small changes.
- Build and run: `./start` — rebuilds only when `ClaudeUsageWidget.swift` is
  newer than the binary, stops any running instance, then launches detached.
  `./start --force` always rebuilds; `./start --stop` just stops it.
- Underlying commands, if you need them directly:
  `swiftc -O -o ClaudeUsageWidget ClaudeUsageWidget.swift` then
  `./ClaudeUsageWidget &` (background it; it's a GUI app with no Dock icon).
  Always stop the old instance first (`pkill -x ClaudeUsageWidget`), otherwise
  two widgets stack on screen and double the API poll rate.
- The compiled binary is gitignored — never commit it.
- `CLAUDE.md` is a symlink to this file; edit `AGENTS.md` only.

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
- Be conservative with API calls: the usage endpoint returns 429 when polled
  too often. Keep the single in-flight request guard, the post-attempt
  rescheduling, and the `Retry-After`/backoff handling in `refresh()` — never
  reintroduce a fixed repeating poll timer, an unthrottled retry, or a poll
  interval shorter than `basePoll` (5 min).
- Never surface errors as panel text. On failure keep the last fetched values on
  screen and signal state only through the live dot's color and tooltip
  (`setStatus`): yellow = retrying by itself, red = the user must act.

## Security constraints

- The OAuth tokens must never be logged or printed. The access token is sent
  only to `api.anthropic.com`; the refresh token only to Anthropic's OAuth
  token endpoint (`console.anthropic.com/v1/oauth/token`) in the refresh
  grant. Debug scripts print response bodies only, never the token or raw
  credentials.
- Credential write-back (after a token refresh) must keep tokens out of
  process argument lists: the Keychain write goes through `security -i` with
  the command fed via stdin — never pass the JSON as a CLI argument.
- Do not add analytics, crash reporting, or any third-party network calls.

## PR / commit guidelines

- Update `SPEC.md` when behavior changes, and `README.md` when setup or
  user-visible features change.
- Refresh `screenshot.png` after UI changes (capture the live widget window).
- Commit messages: imperative summary line; body explains the why.
