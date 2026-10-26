# SPEC.md — Claude Usage Widget

Behavioral specification; update it whenever behavior changes. The widget is a
small always-on-top macOS panel mirroring the usage limits at
claude.ai/settings/usage for the signed-in Claude Code account: current session,
all-models weekly, and the model-scoped weekly limit (now "Fable").

## Credentials and token refresh

1. macOS Keychain generic password, service `Claude Code-credentials`, via
   `/usr/bin/security find-generic-password -w`, with a 10 s deadline
   (then terminate, then `SIGKILL`, up to 14 s in all) so an unanswered Keychain
   prompt cannot block. On timeout, failure or a blank value, fall through to
   (2). `-w` prints the value hex-encoded when it contains any non-ASCII byte,
   so all-hex output is decoded before parsing.
2. `~/.claude/.credentials.json`.

Either yields JSON with the OAuth fields under `claudeAiOauth` (legacy: at the
top level): `accessToken`, `refreshToken`, `expiresAt` in epoch ms, plus
metadata like `scopes`. It is kept whole (a refresh preserves unknown keys) and
re-read every poll, so tokens Claude Code refreshes are picked up live. The
access token goes only in a `Bearer` header to `api.anthropic.com`, the refresh
token only in the grant below; neither is logged or shown.

When the access token is expired or within 60 s of `expiresAt`, the widget
renews it before polling: `POST https://console.anthropic.com/v1/oauth/token`,
body `{grant_type: refresh_token, refresh_token, client_id}`, client ID
`9d1c250a-e61b-44d9-88ed-5944d1962f5e`. The exchange is capped at 30 s by
URLSession itself (15 s idle) and the widget always waits for its outcome:
abandoning a response the server has already answered would lose a rotation.

All credential reads, refreshes and writes run on one serial queue, so two
fetches never touch the Keychain item at the same time.

- On success `accessToken`, `refreshToken` (rotated; the old one kept only if
  the response omits a new one) and `expiresAt` (now + `expires_in`) are
  written back to the store they came from, never the other; rotation
  invalidates the old refresh token, so this write is mandatory. The store is
  re-read right before writing and only those three fields are merged into its
  *current* JSON, so changes Claude Code made meanwhile (e.g. MCP OAuth
  entries) survive. If the stored refresh token is no longer the one the widget
  spent, Claude Code refreshed or signed in on its own: its credentials win and
  nothing is written.
- If the write fails, the rotated tokens are kept in memory and used for
  polling, and the write is retried at the start of every poll until it lands
  (or Claude Code's own newer credentials appear). Meanwhile a successful poll
  shows the dot yellow, "Couldn't save renewed sign-in — retrying", instead of
  green. Quitting the widget in this state drops the only live tokens, so
  Claude Code would need a fresh sign-in. A write only ever goes over a store
  that was just read back: if the item is missing (signed out meanwhile) or
  unreadable, it is never re-created from memory. The profile fetch also uses
  the in-memory tokens while a write is pending.
- Keychain write-back uses `security -i` with the command on stdin, keeping the
  JSON out of any argument list, under the same deadline as the read; file
  write-back is atomic, `0600`.
- A Keychain write counts only if `security -i` exits 0 and the item reads back
  identical; otherwise it is retried once.
- Size guard: `security -i` reads each stdin line into a 4096-byte buffer and
  stores longer lines truncated (the exit status doesn't reflect it), which
  corrupts the item and signs Claude Code out. Claude Code keeps extra data
  (e.g. MCP OAuth tokens) in the same item, so it can outgrow that. The write
  command is capped at 4000 bytes; before refreshing, the widget checks the
  current credentials plus 256 bytes of headroom would fit, and otherwise skips
  the refresh (never rotating tokens it couldn't save), leaving renewal to
  Claude Code.
- A 401/403 from the usage endpoint triggers one reactive refresh and retry.
- At most one attempt per 60 s. On failure (or a refresh skipped by the size
  guard) the poll continues with the stale token and the error path reports it
  (red dot and footer, "Sign-in expired — open Claude Code, then ↻").

## Endpoints

Both use `Authorization: Bearer <token>`, `anthropic-beta: oauth-2025-04-20` and
a 15 s timeout. `GET https://api.anthropic.com/api/oauth/usage` is polled every
5 min:

- **Primary parse**: the `limits` array — entries of `kind`, `percent` (0–100),
  `resets_at` (ISO 8601), optional `scope.model.display_name`. `session` →
  Session row, `weekly_all` → All models row, `weekly_scoped` → third row,
  labeled from that display name when present.
- **Fallback** for anything `limits` left unfilled: top-level `five_hour`,
  `seven_day`, and the first non-null of `seven_day_fable` / `seven_day_opus` /
  `seven_day_sonnet`, each with `utilization` (or `used_percent`) and
  `resets_at` (or `resetsAt`). Dates accept ISO 8601 with or without fractional
  seconds, or an epoch number; a response with no metric at all is a failure.
- No normalization: `percent` and `utilization` are both 0–100; never scale up a
  suspected 0–1 fraction (it once turned a real 1 % into 100 %).

`GET https://api.anthropic.com/api/oauth/profile`, once at launch: renders
`account.full_name` (fallback `display_name`, then `email`) and
`organization.name` as `"<name> · <org>"` (whichever of the two is present),
refetched if the user line is still blank after a successful poll.

## Panel and layout

Borderless, non-activating `NSPanel`, 260 × 184 pt, `.floating` level, on all
Spaces and over full-screen apps, no Dock icon (`.accessory` policy),
HUD-material background, 12 pt radius, shadow. Draggable by its background;
frame saved under autosave name `ClaudeUsageWidget`, defaulting to the main
screen's top-right (16 pt inset). Right-click: Refresh now · Quit Claude Usage
Widget. Top to bottom:

1. Title "Claude usage"; right, a pulsing live dot and a ↻ refresh button.
2. User line `Full Name · Organization`, blank until the profile loads.
3. **Session** row, `WEEKLY` header, **All models** row, then the model-scoped
   row labeled from the API (e.g. **Fable**).
4. Footer `Session resets in X hr Y min · updated H:MM PM` — `X min` under an
   hour, `Session reset · updated H:MM PM` past it, plain `updated H:MM PM` with
   no known reset. "updated" is the last *successful* fetch, re-rendered every
   30 s. `loading…` before the first success, `no data yet` after a failure.
   The only errors it ever shows are the two red "needs action" states below,
   where it carries that message in red instead of the stamp.
5. **Start at login** checkbox (left), **Menu bar** checkbox (right).

Rows are label, bar, integer percentage. Bar fill: blue below 70 %, orange at
70–89 %, red at ≥ 90 %. A row with a known reset time gets the tooltip
`Resets EEE h:mm a`; one with no data shows "–" and an empty bar.

The live dot pulses continuously (opacity 1.0 ↔ 0.2, 0.9 s autoreverse).
Transient problems surface there only — color and tooltip, never panel text:

- gray "Waiting for data…" before the first poll; green "Live" after a success.
- yellow, retrying by itself: "Paused — Claude asked to slow down" (429),
  "Can't reach Claude — retrying" (offline, 5xx, unparseable body), or
  "Couldn't save renewed sign-in — retrying" (see Credentials).
- red, needs the user: "Not signed in — open Claude Code, then ↻" or "Sign-in
  expired — open Claude Code, then ↻".

After any successful fetch the tooltip appends `· updated H:MM PM`.

The red states are the one exception to "never panel text": a tiny red dot
reads as a broken widget, not as "sign in again". While one is active the
footer shows that message in red (the "updated" stamp lives in the tooltip
meanwhile), and the three rows plus the `WEEKLY` header are dimmed to 55 %
opacity so the last numbers read as stale rather than current — they are not
emptied, since weekly limits don't vanish with the token. The next successful
fetch restores the footer, colors and opacity. "Open Claude Code" is the
instruction in every red case: with a dead refresh token it prompts a sign-in,
with a merely stale one it refreshes, and either way the widget re-reads the
credentials on its next poll — ↻ gets there sooner.

## Menu bar mode

The **Menu bar** checkbox tucks the widget into the menu bar instead of floating
over windows; state persists in `UserDefaults` key `InMenuBar`, applied on
launch.

- **On**: the panel hides and an `NSStatusItem` appears — sparkle symbol plus
  `S <session>% · W <weekly>% · M <model-scoped>%` (fixed tags, one per
  limit kind — session / weekly_all / weekly_scoped — never derived from the
  model name, so a model like "Sonnet 5" can't collide with Session's "S") in monospaced
  digits, each percentage orange at ≥ 70 % and red at ≥ 90 %, "–" where a
  metric is missing. Before any data the title is "–" with tooltip
  `Claude usage — waiting for data`; otherwise
  `Claude usage — Session 42% · All models 18% · Fable 9%`. In a red state the
  title is a plain, untinted `Sign in` (status items are monochrome; the
  tooltip carries the full message). Left-click toggles
  the fully working panel, dropped under the status item and clamped to the
  screen edge. Right-click: Refresh now · Move back to floating widget · Quit.
- **Off**: the status item goes away and the panel returns to its saved floating
  position. Autosave is suspended in menu bar mode, so the drop-down never
  overwrites that frame.

## Polling and errors

Conservative by design — the figures move over hours, and the endpoint 429s if
polled too often.

- Poll on launch, then rescheduled after every attempt (one-shot timer, never a
  fixed repeating beat): 5 min after a success, longer after a failure, plus
  0–15 % jitter that never shortens a cool-off.
- One request in flight at a time. Manual refresh (↻ or Refresh now) blips the
  live dot to acknowledge the click and skips the remaining wait, debounced to
  one request per 30 s: a click inside that gap still fires once it is up.
- HTTP 429: the delay is the server's `Retry-After` (seconds or HTTP date),
  else the backoff below, clamped to 5 min–24 h. A wait longer than the 30 min
  backoff cap is honoured, not retried early; the 24 h ceiling (and ignoring a
  non-finite value) keeps one bogus header from stopping polling until a
  restart. Until it elapses nothing is sent at all, manual refreshes included.
  Any other failure doubles the delay (5 → 10 → 20 → 30 min, capped), except
  the two red states, which stay at 5 min: the backoff exists for a flaky
  server, not for waiting on the user, and a new sign-in should be picked up
  within one base poll (a poll with a dead token costs one request plus at most
  one rate-gated refresh attempt). Success resets it to 5 min.
- On `NSWorkspace.didWakeNotification` the backoff resets to 5 min and a poll
  runs ~5 s later, still through every guard (a 429 cool-off blocks it).
- The in-flight guard is released once a fetch has been in flight over 2 min;
  that fetch's late result is then discarded (per-fetch generation counter),
  the next poll is scheduled at the normal interval in its place, and the
  serial credential queue keeps it from overlapping the next one.
  The 30 s footer timer doubles as a watchdog, calling `refresh()` — through
  every guard, never faster than normal — if nothing has been *attempted* for
  longer than `maxPoll` + 5 min with no 429 cool-off running.
- App Nap: a `beginActivity(.userInitiated)` assertion is held for the app's
  lifetime, or an accessory app with no window would have its one-shot timers
  deferred by minutes. Timer tolerances only ever delay a fire.
- Transient failures never write to the panel: bars, percentages and footer
  keep the last successfully fetched values; only the dot changes. The red
  states additionally take over the footer and dim the rows (see Panel).

## Start at login

Checkbox state on launch = existence of
`~/Library/LaunchAgents/com.empathy.claude-usage-widget.plist`. Ticking it writes
that plist with `RunAtLoad = true` and `ProgramArguments` set to the binary's
absolute path, deliberately without `launchctl load` (that would spawn a second
instance), so it applies at next login. Unticking only deletes the plist,
symmetrically without `launchctl unload`/`bootout`: if this instance was
started at login it is the agent's process, and launchd would kill it.

## Non-goals

Extra-usage credits, spend, per-surface scopes and the other buckets in the
usage response are ignored. No interactive sign-in flow — if the refresh token
itself is dead, the user must sign in via Claude Code.
