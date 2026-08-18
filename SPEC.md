# SPEC.md — Claude Usage Widget

Behavioral specification for the widget. Update this file whenever behavior
changes.

## Purpose

A small always-on-top macOS panel mirroring the usage limits shown at
claude.ai/settings/usage for the signed-in Claude Code account: current
session, all-models weekly, and the model-scoped weekly limit (currently
"Fable").

## Data sources

### Credentials

1. macOS Keychain generic password, service `Claude Code-credentials`, read
   via `/usr/bin/security find-generic-password -w`.
2. Fallback: `~/.claude/.credentials.json`.

Either yields JSON containing `claudeAiOauth.accessToken`. The token is
re-read on every poll, so tokens refreshed by Claude Code are picked up
without restarting. The token is used only as a `Bearer` header to
`api.anthropic.com` and is never persisted, logged, or displayed.

### Endpoints

Both called with headers `Authorization: Bearer <token>` and
`anthropic-beta: oauth-2025-04-20`, 15 s timeout.

- `GET https://api.anthropic.com/api/oauth/usage` — polled every 60 s.
  - **Primary parse**: the `limits` array. Each entry has `kind`, `percent`
    (0–100), `resets_at` (ISO 8601), and optional
    `scope.model.display_name`. Mapping: `session` → Session row,
    `weekly_all` → All models row, `weekly_scoped` → third row, whose label
    is set from `scope.model.display_name` when present.
  - **Fallback parse** (if `limits` is absent): top-level `five_hour`,
    `seven_day`, and the first non-null of `seven_day_fable` /
    `seven_day_opus` / `seven_day_sonnet`, each `{utilization, resets_at}`.
  - Normalization: if all parsed values are ≤ 1.5 they are treated as
    fractions and scaled ×100.
- `GET https://api.anthropic.com/api/oauth/profile` — fetched once at launch.
  Renders `account.full_name` (fallback `display_name`, then `email`) and
  `organization.name` as `"<name> · <org>"`.

## Window behavior

- Borderless, non-activating `NSPanel`, 260 × 184 pt, `.floating` level,
  visible on all Spaces and over full-screen apps, no Dock icon
  (`.accessory` activation policy).
- HUD-material visual effect background, 12 pt corner radius, shadow.
- Draggable by its background; frame persisted via autosave name
  `ClaudeUsageWidget`. First launch defaults to the top-right corner of the
  main screen (16 pt inset).

## Layout (top to bottom)

1. Title "Claude usage"; on the right, a pulsing live dot and a ↻ refresh
   button.
2. User line: `Full Name · Organization` (blank until profile loads).
3. **Session** row.
4. `WEEKLY` section header.
5. **All models** row.
6. Model-scoped row (labeled from the API, e.g. **Fable**).
7. Footer: `Session resets in X hr Y min · updated H:MM PM` (re-rendered
   every 30 s between polls; errors replace this text).
8. **Start at login** mini checkbox.

Each row: label (left), progress bar, integer percentage (right). Bar fill
color: blue below 70 %, orange at 70–89 %, red at ≥ 90 %. Rows with a known
reset time get a tooltip `Resets EEE h:mm a`. A row with no data shows "–"
and an empty bar.

## Live dot

Pulses continuously (opacity 1.0 ↔ 0.2, 0.9 s autoreverse). Gray before the
first poll, green after a successful poll, red after a failed one. Tooltip:
"Live — refreshes every minute".

## Polling and errors

- Usage poll every 60 s, plus on launch and on manual refresh (↻ button or
  right-click → Refresh now).
- Footer error states:
  - no readable token → `⚠︎ no token — sign in with \`claude\``
  - HTTP 401/403 → `⚠︎ token expired — open Claude Code to refresh`
  - other HTTP status → `⚠︎ HTTP <code>`
  - network failure → `⚠︎ offline — retrying…`
- Errors never clear the last successfully displayed bar values.

## Start at login

Checkbox state on launch = existence of
`~/Library/LaunchAgents/com.empathy.claude-usage-widget.plist`.

- **On**: writes that plist with `RunAtLoad = true` and `ProgramArguments`
  set to the running binary's absolute path. Deliberately not loaded via
  `launchctl` (that would spawn a second instance); effective at next login.
- **Off**: `launchctl unload` (best-effort) then deletes the plist.

## Context menu (right-click)

Refresh now · Quit Claude Usage Widget.

## Non-goals

Extra-usage credits, spend, per-surface scopes, and the other buckets in the
usage response are intentionally ignored. No auto-token-refresh via the
OAuth refresh token — the widget relies on Claude Code keeping the token
fresh.
