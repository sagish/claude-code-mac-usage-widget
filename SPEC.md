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

- `GET https://api.anthropic.com/api/oauth/usage` — polled every 5 min.
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

## Menu bar mode

A **Menu bar** mini checkbox (bottom-right of the panel) tucks the widget
into the menu bar so the floater doesn't cover other windows. State persists
in `UserDefaults` key `InMenuBar` and is applied on launch.

- **On**: the panel hides and an `NSStatusItem` appears — sparkle symbol +
  `S <session>% · F <fable>%` (the "F" is the first letter of the
  model-scoped row's label), monospaced digits, each percentage tinted
  orange at ≥ 70 % and red at ≥ 90 %; a metric with no data shows "–", and
  before any data arrives the whole title is "–". Tooltip lists all three
  metrics.
  - Left-click toggles the full panel, dropped down under the status item
    (clamped to the screen edge). Everything in it keeps working, including
    unticking the checkbox.
  - Right-click: Refresh now · Move back to floating widget · Quit.
- **Off**: the status item is removed and the panel reappears at its saved
  floating position. Frame autosave is suspended while in menu bar mode so
  drop-down positioning never overwrites the remembered floating frame.

## Layout (top to bottom)

1. Title "Claude usage"; on the right, a pulsing live dot and a ↻ refresh
   button.
2. User line: `Full Name · Organization` (blank until profile loads).
3. **Session** row.
4. `WEEKLY` section header.
5. **All models** row.
6. Model-scoped row (labeled from the API, e.g. **Fable**).
7. Footer: `Session resets in X hr Y min · updated H:MM PM`, where "updated"
   is the last *successful* fetch (re-rendered every 30 s between polls). It
   never shows an error — before the first successful fetch it reads
   `loading…`, or `no data yet` once an attempt has failed.
8. **Start at login** mini checkbox (left) and **Menu bar** mini checkbox
   (right, see Menu bar mode).

Each row: label (left), progress bar, integer percentage (right). Bar fill
color: blue below 70 %, orange at 70–89 %, red at ≥ 90 %. Rows with a known
reset time get a tooltip `Resets EEE h:mm a`. A row with no data shows "–"
and an empty bar.

## Live dot

Pulses continuously (opacity 1.0 ↔ 0.2, 0.9 s autoreverse). It is the only
place a problem is surfaced — color plus tooltip, never panel text:
- gray, "Waiting for data…" — before the first poll
- green, "Live" — last poll succeeded
- yellow — transient trouble, retrying by itself: "Paused — Claude asked to
  slow down" (429) or "Can't reach Claude — retrying" (offline, 5xx,
  unparseable body)
- red — needs the user: "Not signed in — run `claude` to sign in" or
  "Sign-in expired — open Claude Code"
When data has been fetched at least once, the tooltip appends
`· updated H:MM PM`.

## Polling and errors

Polling is deliberately conservative: the figures move over hours and days,
while the endpoint returns 429 if it is called too often.
- Usage poll on launch, then rescheduled after every attempt (one-shot timer,
  never a fixed repeating beat): 5 min after a success, longer after a failure.
  Every scheduled delay gets 0–15 % of extra jitter, so restarts and a second
  instance never line up on the same second, and a cool-off is never cut short.
- At most one usage request is in flight at a time. Manual refresh (↻ button or
  right-click → Refresh now) skips the remaining wait but is debounced to one
  request per 30 s.
- Rate limiting (HTTP 429): the retry delay is the server's `Retry-After`
  header (seconds or HTTP date) clamped to 5–30 min, falling back to the backoff
  below when the header is absent. Until it elapses no request is sent at all,
  manual refreshes included.
- Any other failure doubles the retry delay (5 → 10 → 20 → 30 min, capped); a
  success resets it to 5 min.
- Wake from sleep: timers don't tick while the Mac sleeps, so on
  `NSWorkspace.didWakeNotification` any failure backoff is reset to 5 min and a
  poll is scheduled ~5 s later (letting the network come back up). The poll goes
  through the normal guards — a 429 cool-off still blocks it.
- Failures never write to the panel: bars, percentages and footer keep the last
  successfully fetched values, and only the live dot's color and tooltip change
  (see Live dot).

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
