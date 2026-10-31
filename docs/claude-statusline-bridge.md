# Claude Status-Line Bridge

The bridge gives Token Tracker a Claude usage reading that does not depend on the
stored access token. It exists because of a failure mode this app cannot fix on
its own: Token Tracker only *reads* the token Claude Code saves, and only the CLI
refreshes it, so once that token lapses Claude collection stops until the CLI is
next run. Starting `claude` is normally enough — the refresh token outlives the
access token by weeks — and `/login` is the fix only once that refresh token has
lapsed too. On the machine this was investigated on, the gap was seven weeks of
nothing. See [Claude usage collection and
authentication](claude-usage-auth.md) for why the status line is the only
documented input that avoids it.

Claude Code hands its status-line command a JSON payload on stdin that includes
`rate_limits.five_hour` and `rate_limits.seven_day`, each with `used_percentage`
and `resets_at` (Unix epoch seconds). The
[status-line reference](https://code.claude.com/docs/en/statusline#rate-limit-usage)
documents them, and notes that they appear only for Pro/Max subscribers (or
behind a spend-limit gateway), only after the session's first API response, that
either window may be independently absent, and that Claude Code drops a window
once its `resets_at` passes.

## What installing it does, and does not do

The bridge wraps the user's existing status-line command rather than replacing
it. It reads stdin once, records the usage numbers, then runs the wrapped command
with that same stdin and relays its output. A user who has not installed the
bridge is unaffected in every respect: with no file present, the collector falls
straight through to the behaviour it had before.

It does not provide unattended polling. The status line only runs while a Claude
Code session is running, so when the CLI is closed, or usage happens on another
device, the bridge has nothing new to report — and says so, rather than showing
an old number as the current one.

It also fills only from a session that runs a status line, which is narrower than
"a Claude Code session". Claude Code in the desktop app does not fill it: with
the bridge installed, `written_at` stood still through 180 seconds of an active
desktop-app session's traffic, and through the nine hours before that. Whether
the desktop app runs no `statusLine` command at all or runs one whose payload
carries no `rate_limits` was not determined — the recorder writes nothing in
either case, so the file stays absent and the two look identical from here. The
terminal CLI is what fills it, and only after that session's first API response,
which is when Claude Code starts sending `rate_limits` at all. A user who works
mainly in the desktop app therefore has an empty bridge and no fallback;
`Claude status line record: none` in the diagnostics text is that state.

## Installation

Point `statusLine.command` at the script with the existing command after `--`.

macOS and Linux, in `~/.claude/settings.json`:

```json
{
  "statusLine": {
    "type": "command",
    "command": "\"/path/to/Token tracker/scripts/claude-statusline-bridge.sh\" -- node /your/statusline.js"
  }
}
```

Windows, in `%USERPROFILE%\.claude\settings.json`:

```json
{
  "statusLine": {
    "type": "command",
    "command": "powershell -NoProfile -ExecutionPolicy Bypass -File \"C:\\path\\claude-statusline-bridge.ps1\" -- node C:\\your\\statusline.js"
  }
}
```

Both examples quote the script's path. The command is parsed by a shell, so an
unquoted path containing a space — this repository's own `Token tracker` among
them — splits into two arguments and the status line fails with `No such file or
directory`. The script is committed executable; CI keeps it that way, because
the mode is the difference between the line above working and failing with
`permission denied`.

With nothing after `--` the bridge prints nothing, which is a status line showing
only Claude Code's own footer badges. The Unix script needs `python3` (or
`python`) to parse JSON; without one it records nothing and still runs the
wrapped command, so the status line never breaks.

## The file

`~/Library/Application Support/Token Tracker/claude-statusline.json` on macOS,
`%APPDATA%\Token Tracker\claude-statusline.json` on Windows, mode `0600` where
POSIX permissions apply, written by atomic rename. `TOKEN_TRACKER_STATUSLINE_FILE`
overrides the path; the tests use that.

```json
{
  "version": 1,
  "provider": "claude",
  "measured_at": 1793365950,
  "written_at": 1793366010,
  "rate_limits": {
    "five_hour": { "used_percentage": 23.5, "resets_at": 1793369550 },
    "seven_day": { "used_percentage": 41.2, "resets_at": 1793452350 }
  }
}
```

Two usage percentages, two reset instants, two timestamps. Nothing else from the
payload is stored — no token, no session id, no transcript path, no prompt text,
no `spend_limit`. Epoch seconds throughout, because that is the form the status
line reports them in and it survives two scripting languages without timezone
handling.

## Why there are two timestamps

The whole design turns on one distinction. A status-line command re-runs on the
CLI's own schedule, so **being written again is not evidence that the account was
measured again**. A replayed payload that looked fresh would do exactly what
[PR #38](https://github.com/ChunSam/token-tracker/pull/38) had just fixed:
present a stale number as the current state of the account indefinitely.

So the bridge keeps them apart:

- `measured_at` moves only when a window's numbers actually change.
- `written_at` moves on every run, and is used for diagnostics only.

The collector ages a reading by `measured_at` and ignores `written_at` entirely.
A replay therefore keeps its original age and expires on time.

Deciding novelty from the values is conservative in the right direction: a
genuinely new measurement that happens to report the same percentages is treated
as a replay, so freshness is understated rather than overstated. The status-line
payload carries no measurement timestamp of its own, so there is nothing better
to key on.

Two further rules fall out of the same reasoning:

- **A lower `used_percentage` for the same `resets_at` is an older reading.**
  Within one window instance usage only climbs, so a second session rendering a
  staler copy must not drag the record backwards. A different `resets_at` is a
  different window instance, so it always replaces.
- **A window missing from the payload leaves the recorded one alone.** Absence is
  normal early in a session and on plans without a window; it is not evidence
  that the window is gone. A recorded window whose own `resets_at` has passed is
  dropped, which is what covers the window Claude Code stopped reporting.

When nothing moved, the bridge rewrites the file at most once a minute — the only
field left to refresh is `written_at`, and a status line can re-render several
times a second.

## How the collectors use it

`ClaudeStatusLineBridge` (`Sources/TokenTrackerCore/` and
`windows/TokenTracker.Windows.Core/`, 1:1) parses the file and decides whether it
is current. The Claude client asks the usage endpoint first — only that is a
measurement taken *now* — and falls back to the bridge when the API path yields
nothing, carrying the API's error along so the menu still names the fix.

A reading from the bridge gets its own `UsageSource.statusLine`, and the state
machine is:

| Age of `measured_at` | What the user sees |
| --- | --- |
| Within 30 minutes | The numbers, `Status: From status line`, with the reset countdown |
| Past 30 minutes, within the stale tolerance | The same numbers, `Status: Using cached data`, no countdown |
| Past the stale tolerance (default 12h) | `--` |

The middle row is not new machinery: a stale record yields no reading at all, and
the existing snapshot cache then carries the last value with its own label and
expires it on its own measurement time. Thirty minutes matches
`UsageForecaster.maximumSampleAge`, already this repo's answer to how old a
sample may be and still describe now. It is a constant rather than a setting,
because it is not a preference — it is the span in which a measurement can
honestly be called current.

### Why it is not `UsageSource.api`, and not in history

`.api` means a measurement this app took itself, at a moment it chose. The
history store admits `source == .api` only, and that gate is what keeps the
sparkline, the 24-hour trend and the depletion forecast honest.

A status-line reading is real account data, but it is re-read on every poll and
history timestamps each entry with the poll that recorded it. Admitting it would
append one measurement under a run of fresh timestamps — flattening the sparkline
and telling the forecast that usage had stopped moving. That is the same
fabricated-freshness failure as above, wearing a different hat, so the answer is
the same: the reading shows in the menu bar and the menu, and does not enter the
record. `UsageHistoryPolicy` needed no change to enforce this; it already strips
every source that is not `.api`.

## Tests

The policy is a pure function with `now` injected, and both ports assert the same
truth table (`Sources/TokenTrackerSmokeTests/ClaudeStatusLineTests.swift`,
`windows/TokenTracker.Windows.Tests/Program.cs`): window arithmetic, one window
absent, both absent, an expired window, malformed JSON, an unknown version, a
future timestamp, the replay case, the hand-over to the cache, exclusion from
history, and the menu status and its recovery line.

Both scripts are also driven end to end, because the replay rule lives in them
too and no compiler reads them: that the wrapped command still prints, that the
file carries no part of the payload but the usage, that an unchanged payload does
not advance `measured_at`, that a changed one does, that a lower concurrent
reading does not win, and that a missing window does not erase a recorded one.
The Windows half runs wherever PowerShell is reachable, which in practice means
CI; it skips rather than fails elsewhere.
