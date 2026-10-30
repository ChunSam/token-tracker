# Claude Usage Collection and Authentication

Reviewed on 2026-09-20 against official documentation. The locally installed
Claude Code reports version 2.1.260. No account credentials were inspected,
refreshed, or submitted to a live usage endpoint during this investigation.

## Current implementation

Token Tracker reads Claude Code's stored access token, checks `expiresAt`, and
requests `https://api.anthropic.com/api/oauth/usage`. It does not own a login flow
or refresh credentials. macOS tries Keychain before the credentials file;
Windows uses the credentials file. Expired credentials require the external
credential owner to supply a valid token.

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

Proposed implementation, not included in this change:

1. Integrate a small bridge with the user's existing status-line command.
2. Write only usage percentages, reset times, and measurement metadata to a
   user-private local file, atomically. Do not store tokens or the full session
   payload.
3. Read that file from the macOS and Windows collectors, preserving the
   observation timestamp and displaying stale/unavailable states when needed.
4. Preserve existing status-line output and handle missing windows and multiple
   sessions. Do not replace a user's configured script silently.

The status-line command can run on a timer, but that alone does not establish
that a new account measurement occurred. Replayed data must not extend cache
freshness. When the CLI is closed or inactive, or usage occurs only on other
devices, this bridge cannot promise current account usage. It reduces token
handling and repeated login demands; it does not provide permanent unattended
polling of a personal subscription.
