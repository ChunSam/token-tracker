# Claude Usage Collection and Authentication

Reviewed on 2026-09-20 against official documentation. The locally installed
Claude Code reports version 2.1.260. No account credentials were inspected,
refreshed, or submitted to a live usage endpoint during this investigation.

## Current implementation

Token Tracker reads Claude Code's stored access token, checks `expiresAt`, and
requests `https://api.anthropic.com/api/oauth/usage`. It does not own a login flow
and never spends a refresh token. macOS tries Keychain before the credentials
file; Windows uses the credentials file. An expired token is renewed by the
credential owner: since 2026-11-03 the app starts the unmodified Claude Code to
do it (see *CLI-delegated renewal* below).

Cache lifetime now starts at each provider's actual measurement time, not the
latest poll attempt. The versioned cache discards older records whose timestamps
were overwritten by failed polls. A Claude response needs at least one finite
usage value; an absent second window is permitted. Empty or unusable responses
are failures, not successful measurements.

## Available approaches

| Approach | What it provides | Limitation for this application |
| --- | --- | --- |
| Claude Code-managed login | Existing native login and renewal | A login that expires and cannot be refreshed still needs `/login`; there is no permanent-login guarantee. |
| `claude setup-token` | A one-year token for unattended model requests | Official documentation limits this token to model requests. It is not a replacement credential for subscription usage polling. |
| Claude Code status-line data | 5-hour and 7-day usage percentages and reset times without Token Tracker reading credentials | Requires a supporting CLI session and data availability; it is not an independent background account poller. |
| Usage and Cost Admin API | Organization API consumption and billing data | This reports a different product's usage, not personal Pro/Max subscription window percentages. |
| Application-owned refresh-token flow | Could renew short-lived access credentials in an OAuth system | No supported third-party subscription-usage login/refresh integration was established by this research. |

Claude Code's [authentication documentation](https://code.claude.com/docs/en/authentication#generate-a-long-lived-token)
describes the one-year token and its model-request restriction. Its
[login renewal guidance](https://code.claude.com/docs/en/authentication#renew-an-expiring-login)
also documents sessions that require a new login. The
[scope error reference](https://code.claude.com/docs/en/errors#oauth-scope-requirement)
identifies `user:profile` as a permission needed by usage features.

The [Usage and Cost API](https://platform.claude.com/docs/en/manage-claude/usage-cost-api)
is an organization reporting API. Its API-key authentication should not be
confused with access to the current application's subscription endpoint.

The provider's [credential-use documentation](https://code.claude.com/docs/en/legal-and-compliance#authentication-and-credential-use)
does not authorize third-party applications to offer their own Claude.ai login
or intermediate subscription credentials. A custom refresh flow is therefore
not a documented supported distribution path for this product. This research
does not establish an exception for a read-only usage tracker.

## Recommended next integration

Use the official status-line data as a local input source, with authentication
remaining in Claude Code. The [status-line reference](https://code.claude.com/docs/en/statusline#rate-limit-usage)
documents `rate_limits.five_hour` and `rate_limits.seven_day`, each carrying
`used_percentage` and `resets_at`. This requires Claude Code 2.1.251 or later;
the documentation lists these subscription windows for Pro/Max after the first
API response. Either window can be absent. Do not assume the same fields exist
for every plan or for Claude Desktop.

The status-line command can run on a timer, but that alone does not establish
that a new account measurement occurred. Replayed data must not extend cache
freshness. When the CLI is closed or inactive, or usage occurs only on other
devices, this bridge cannot promise current account usage. It reduces token
handling and repeated login demands; it does not provide permanent unattended
polling of a personal subscription.

## Implemented integration

This integration has shipped. `scripts/claude-statusline-bridge.sh` and its
Windows counterpart wrap the user's existing status-line command, record only the
two usage percentages, their reset instants and two timestamps to a user-private
local file by atomic rename, and relay the wrapped command's output unchanged. No
token and no part of the session payload is stored. Installing nothing changes
nothing: with no file present the collectors behave exactly as before.

`ClaudeStatusLineBridge` in both Cores reads that file, and the reading carries
its own `UsageSource.statusLine` rather than `.api`. The replay hazard above is
answered by writing two separate instants: `measured_at`, which moves only when
the reported numbers change, and `written_at`, which moves on every run and is
never used for freshness. A reading older than 30 minutes is handed to the
existing stale-cache path instead of being presented as current, and no
status-line reading enters the history that feeds the trend, sparkline and
forecast — those still admit `source == .api` only.

[Claude status-line bridge](claude-statusline-bridge.md) documents the file
format, the installation, and the reasoning behind each of those rules.

## CLI-delegated renewal

Added on 2026-11-03, after comparing how other usage trackers keep the token
alive. Refreshing the token in the app is ruled out twice over: Anthropic's
refresh tokens are single-use, so an app that spends Claude Code's copy signs the
CLI out (CodexBar shipped this as its issue #1161 and backed it out), and the
credential-use terms above bar third-party logins and credential handling.
Session cookies fall under the same terms.

What stays inside them is running the unmodified CLI, which renews its own store
as it starts. Measured with 2.1.314 on macOS, an interactive launch rewrote the
expired keychain token about 0.7 s after start, before its first screen, with no
model request; `claude auth status` did not renew at all. So when every stored
token has lapsed, `ClaudeCLIRefresher` starts `claude` once in a folder Claude
Code has never trusted, so the launch stops at the trust prompt before hooks,
plugins or a session, waits for the store to move, and reads it again. The
launch details are in `WORK_SUMMARY.md`; the Windows run is in
[Windows VM testing](windows-vm-testing.md). This keeps a token alive for users
who mostly work in Claude Desktop, which never writes this store. It does not
replace `/login` once the refresh token itself has lapsed.
