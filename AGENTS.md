# AGENTS.md

## Project overview

A single-file macOS floating widget (Swift/AppKit, no dependencies, no Xcode
project) showing Claude Code usage limits. All code lives in
`ClaudeUsageWidget.swift`; `SPEC.md` is the behavioral contract — read and
update it there, don't restate it here.

## Build and verify

- Needs only Xcode Command Line Tools (`swiftc`); no package manager and no
  `Package.swift` — don't introduce one for small changes.
- `./start` rebuilds only when `ClaudeUsageWidget.swift` is newer than the
  binary, stops any running instance, then launches detached. `./start --force`
  always rebuilds; `./start --stop` just stops it.
- Directly: `swiftc -O -o ClaudeUsageWidget ClaudeUsageWidget.swift` then
  `./ClaudeUsageWidget &` (background it; GUI app, no Dock icon). Always stop
  the old instance first (`pkill -x ClaudeUsageWidget`), or two widgets stack on
  screen and double the API poll rate.
- The compiled binary is gitignored — never commit it. `CLAUDE.md` is a symlink
  to this file; edit `AGENTS.md` only.
- No test suite: verify by building (zero warnings) and running it.
- `swift debug-usage.swift` and `swift debug-profile.swift` print the raw
  `/api/oauth/usage` and `/api/oauth/profile` responses without the UI. Both need
  a signed-in Claude Code (Keychain item `Claude Code-credentials`, or
  `~/.claude/.credentials.json`); the first keychain access shows a macOS prompt.

## Code style

- Plain AppKit, fixed-frame layout (no Auto Layout, SwiftUI or storyboards).
  Panel size is hardcoded in `buildPanel()`, positions computed top-down from
  `height` — when adding a row, grow `height` and shift the y-offsets below it.
- Keep everything in the one source file, under the existing `// MARK:` sections:
  Data, Credentials, Token refresh, Fetch + parse, Views, Start at login, App.
- Prefer the shared helpers to new one-offs: `runSecurity` (the only place
  `/usr/bin/security` is spawned), `oauthGET` (the only place the Bearer header
  is set), `jsonNumber`, `warningColor` (the 70/90 % thresholds), `buildMenu`.
- `URLSession` with completions dispatched to the main queue; `JSONSerialization`
  with defensive optional casts (the API shape has changed before — prefer the
  `limits` array, keep the legacy fallbacks).
- Be conservative with API calls: the usage endpoint 429s when polled too often.
  Keep the single in-flight guard, the post-attempt rescheduling and the
  `Retry-After`/backoff handling in `refresh()` — never a fixed repeating poll
  timer, an unthrottled retry, or an interval below `basePoll` (5 min).
- Never surface errors as panel text. On failure keep the last fetched values on
  screen and signal state only through the live dot's color and tooltip
  (`setStatus`): yellow = retrying by itself, red = the user must act.

## Security constraints

- Tokens must never be logged or printed. The access token goes only to
  `api.anthropic.com`, the refresh token only to Anthropic's OAuth token endpoint
  (`console.anthropic.com/v1/oauth/token`) in the refresh grant. Debug scripts
  print response bodies only, never tokens or credentials.
- Credential write-back after a refresh must keep tokens out of process argument
  lists: the Keychain write goes through `security -i` with the command fed via
  stdin — never pass the JSON as a CLI argument.
- Do not add analytics, crash reporting, or any third-party network calls.

## PR / commit guidelines

- Update `SPEC.md` when behavior changes, `README.md` when setup or user-visible
  features change, and `claude-usage-widget-promo.png` after UI changes
  (capture the live widget).
- Commit messages: imperative summary line; body explains the why.
