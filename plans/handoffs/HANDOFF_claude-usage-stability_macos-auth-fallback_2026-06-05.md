# Claude usage stability and macOS auth fallback

**Date:** 2026-06-05
**Status:** COMPLETED
**Bead(s):** none
**Epic:** Token Tracker usage reliability
**Chain:** `claude-usage-stability` seq `1`
**Parent:** `none — first in chain`
**Prior chain:** none — first in chain

---

## Reference Documents

- `WORK_SUMMARY.md` — project summary, usage lookup flow, and current macOS/Windows architecture notes.
- `agent.md` — project conventions and usage lookup notes for Claude and Codex.
- `README.md` — user-facing Token Tracker behavior and feature list.

## The Goal

The user wanted to understand how Claude and Codex usage are tracked, then asked why Claude usage is sometimes not read immediately.
The practical goal became improving the macOS app's Claude usage reliability without changing the user-facing refresh model.
The key problem was not raw token counting; Token Tracker reads provider usage APIs and displays remaining percentages.
The final implementation reduces avoidable Claude failures and makes unavoidable failures visible in the menu through better error text.
The user then requested this handoff plus a commit and push.

## Where We Are

- Repo path is `/Users/jkl/Projects/Token tracker`.
- Active branch before commit is `main`.
- Remote is `origin https://github.com/ChunSam/token-tracker.git`.
- No prior `HANDOFF_*.md` or `PLAN_*.md` files were found with the handoff skill search.
- No `bd` command was installed in this environment.
- The workstream chain is `claude-usage-stability`, seq `1`.
- The feature implementation is done in macOS Swift code only.
- Windows code was intentionally left untouched.
- `Sources/TokenTrackerCore/HTTPClient.swift` now returns more precise `UsageError` values.
- `HTTPClient.getJSON` gained optional `serviceName`.
- `HTTPClient.getJSON` now maps URL timeout to `UsageError.timedOut(service:)`.
- `HTTPClient.getJSON` now maps non-2xx HTTP responses to `UsageError.httpStatus(code:service:)`.
- `HTTPClient.getJSON` now maps other URL/session failures to `UsageError.network(message:service:)`.
- `UsageError` is now `public`, `Equatable`, and still conforms to `LocalizedError`.
- `UsageError.errorDescription` now emits displayable strings such as `HTTP 401 from Claude API`.
- `UsageError.isAuthenticationFailure` returns true only for HTTP `401` and `403`.
- `Sources/TokenTrackerCore/ClaudeUsageClient.swift` now stores the Claude usage URL in `usageURL`.
- `ClaudeUsageClient.fetchFromAPI()` now reads token candidates instead of a single token.
- Token candidate order is Keychain first, then `~/.claude/.credentials.json`.
- Duplicate token strings are deduplicated before any network call.
- Empty or whitespace-only tokens are ignored by `TokenCandidate.init?`.
- Claude usage API calls now pass `serviceName: "Claude API"`.
- Claude usage API calls now use a 10 second timeout instead of the default 5 seconds.
- If the Keychain token gets HTTP `401` or `403`, the client retries once with the credentials-file token if present and different.
- If the Keychain token fails for non-auth reasons such as timeout, 429, or 500, the client does not retry with the file token.
- `Sources/TokenTrackerSmokeTests/main.swift` now verifies stale cache display behavior.
- `Sources/TokenTrackerSmokeTests/main.swift` now verifies error descriptions for HTTP status, timeout, and generic network errors.
- `UsageService` already preserved stale-cache behavior and did not require code changes.
- Existing stale cache behavior remains: if a provider fetch is unavailable and a cached successful snapshot is less than 3600 seconds old, the cached usage is shown as `staleCache`.
- Existing menu behavior remains: source and error lines are displayed for each provider.
- `swift run TokenTrackerSmokeTests` passed after changes.
- `swift build` passed after changes.
- As of handoff creation, changed files are `Sources/TokenTrackerCore/ClaudeUsageClient.swift`, `Sources/TokenTrackerCore/HTTPClient.swift`, `Sources/TokenTrackerSmokeTests/main.swift`, and this handoff file.

## What We Tried (Chronological)

1. The user first asked how Claude and Codex usage are tracked.
2. Repo search found macOS Swift and Windows C# implementations.
3. Codex tracking was identified as API-based, using `~/.codex/auth.json`.
4. Codex API endpoint was identified as `https://chatgpt.com/backend-api/wham/usage`.
5. Codex response fields were identified as `rate_limit.primary_window.used_percent` and `rate_limit.secondary_window.used_percent`.
6. Codex remaining percentage was confirmed as `100 - used_percent`.
7. Claude tracking was identified as API-based, not local token counting.
8. Claude macOS auth order was identified as Keychain first, credentials file second.
9. Claude Keychain item was identified as `Claude Code-credentials`.
10. Claude fallback file was identified as `~/.claude/.credentials.json`.
11. Claude API endpoint was identified as `https://api.anthropic.com/api/oauth/usage`.
12. Claude response fields were identified as `five_hour.utilization` and `seven_day.utilization`.
13. Claude remaining percentage was confirmed as `100 - utilization`.
14. `CodexLogReader.swift` was discovered, but it is not connected to the active refresh path.
15. The user then asked whether we could predict where Claude read failures happen.
16. The main hypotheses were API reflection delay, refresh interval, stale Keychain token, 5 second timeout, and stale cache masking.
17. Code inspection showed `HTTPClient.getJSON` returned only `HTTP request failed` for all non-2xx responses.
18. Code inspection showed timeout was defaulted to 5 seconds.
19. Code inspection showed Claude token reading returned Keychain token immediately and never retried with the file token after API auth failure.
20. Code inspection showed `UsageService` already preserves errors while replacing unavailable provider usage with stale cache.
21. The user asked for a modification plan based on those predictions.
22. A plan was drafted to scope the work to macOS first.
23. The user selected `macOS 우선 (Recommended)` for scope.
24. The user selected `유지+명확화 (Recommended)` for stale cache behavior.
25. The user selected `60초 유지 (Recommended)` for refresh interval.
26. The final plan specified Keychain-to-file retry only on HTTP `401` or `403`.
27. The plan explicitly kept stale cache and the 60 second refresh interval.
28. The user then requested implementation of the plan.
29. `HTTPClient.swift` was changed first to introduce typed error cases.
30. `ClaudeUsageClient.swift` was changed next to add token candidates and a Claude-specific 10 second timeout.
31. `TokenTrackerSmokeTests/main.swift` was changed last to verify the new behavior without relying on live network calls.
32. `swift run TokenTrackerSmokeTests` was run and passed.
33. `swift build` was run and passed.
34. The user then requested handoff plus commit and push.
35. The handoff skill was invoked with a Deep mining pass.
36. Git state, prior handoffs, recent notes, remote, diff, and validation instructions were gathered before writing this file.

## Key Decisions

- Keep tracking based on provider APIs rather than trying to compute Claude usage locally.
- Keep the default 60 second refresh interval because the user chose not to increase polling frequency.
- Keep stale cache enabled because it prevents temporary outages from removing useful last-known values.
- Improve stale cache transparency by preserving the fetch error in the existing menu error line.
- Scope the implementation to macOS Swift code only; Windows was intentionally excluded.
- Retry the file token only for Keychain HTTP `401` or `403`, because those indicate likely token invalidity.
- Do not retry the file token for timeout, `429`, or server errors, because that would double traffic without evidence of credential failure.
- Deduplicate identical Keychain and file tokens to avoid unnecessary duplicate Claude API calls.
- Do not expose token values in any error string, UI string, test, or handoff.
- Make `UsageError` public so the smoke test executable can assert localized descriptions.
- Preserve `CodexUsageClient` behavior by keeping `HTTPClient.getJSON` defaults compatible.
- Avoid touching `UsageService` because it already carries stale-cache error context.
- Avoid live Claude API tests because they would depend on personal credentials and network state.

## Evidence & Data

| Command | Result |
|---|---|
| `git branch --show-current` | `main` |
| `git status -s` before handoff | 3 modified Swift files |
| `git diff --stat` before handoff | 3 files, 107 insertions, 18 deletions |
| `git remote -v` | `origin https://github.com/ChunSam/token-tracker.git` |
| `command -v bd` | exit 1, no output |

| Test command | Result | Notes |
|---|---|---|
| `swift run TokenTrackerSmokeTests` | passed | Built and ran `TokenTrackerSmokeTests` |
| `swift build` | passed | Built `TokenTrackerMenuBar` debug target |

Raw smoke test output summary:

```text
Build of product 'TokenTrackerSmokeTests' complete! (1.34s)
TokenTrackerSmokeTests passed
```

Raw build output summary:

```text
Build complete! (1.19s)
```

Recent commit log before this work:

| Hash | Summary |
|---|---|
| `962ffda` | Add app icon to macOS bundle |
| `7e3124a` | Fix Windows tray menu size |
| `4e634b3` | Fix Windows logo fallback warning |
| `f65dd71` | Add Windows provider logo labels |
| `9f9164e` | Improve Windows tray behavior |
| `5873515` | Fix Windows publish target |
| `e1585b5` | Add Windows tray app |
| `bd85a9c` | Add Claude-only display mode |
| `dfcc5fb` | Add usage README |
| `6642382` | Fix menu colors and release build script |
| `6582d4b` | Improve menu bar usage display |
| `e7df789` | Add language selection with Korean |
| `cf60aa8` | Initial Token Tracker menu bar app |

Diff stat before adding this handoff:

```text
Sources/TokenTrackerCore/ClaudeUsageClient.swift | 61 ++++++++++++++++++++----
Sources/TokenTrackerCore/HTTPClient.swift        | 56 ++++++++++++++++++----
Sources/TokenTrackerSmokeTests/main.swift        |  8 ++++
3 files changed, 107 insertions(+), 18 deletions(-)
```

Important expected UI error strings:

| Scenario | Expected error string |
|---|---|
| Claude 401 | `HTTP 401 from Claude API` |
| Claude 403 | `HTTP 403 from Claude API` |
| Claude 429 | `HTTP 429 from Claude API` |
| Timeout | `Timed out contacting Claude API` |
| Generic network error | `Network error from Claude API: {message}` |
| Missing all tokens | `Missing credentials` |

Behavior matrix:

| Condition | Token used | Retry? | Source on success | Source on failure with cache |
|---|---|---:|---|---|
| Keychain token succeeds | Keychain | No | `api` | not applicable |
| Keychain missing, file succeeds | File | No | `api` | not applicable |
| Keychain 401/403, file different and succeeds | File | Yes | `api` | not applicable |
| Keychain 401/403, file missing | Keychain only | No successful retry | unavailable before cache | `staleCache` |
| Keychain timeout | Keychain | No | unavailable before cache | `staleCache` |
| Keychain 429/500 | Keychain | No | unavailable before cache | `staleCache` |
| Keychain and file token identical | Keychain once | No duplicate | `api` if success | `staleCache` if failure and cache exists |

## Code Analysis

- `UsageService.refresh()` is the integration point that calls `claudeClient.fetch()` and `codexClient.fetch()`.
- `UsageService.refresh()` applies stale cache only when the fresh provider result is not available and cached provider usage is available.
- `ProviderUsage.isAvailable` is true if either `remainingPercent5h` or `remainingPercent7d` is non-nil.
- `ProviderUsage.unavailable` stores the fetch error and sets `source: .unavailable`.
- `UsageService.markStale` copies the cached provider usage, changes `source` to `.staleCache`, preserves the new failure error, and updates `updatedAt`.
- `AppDelegate.addUsage` already prints `Source` and `Error` lines in the menu.
- `HTTPClient.getJSON` remains a small generic GET JSON wrapper used by both Claude and Codex clients.
- `HTTPClient.getJSON` default timeout remains 5 seconds so Codex behavior is unchanged.
- Claude passes `timeout: 10` explicitly.
- Claude passes `serviceName: "Claude API"` explicitly so UI errors identify the failing upstream.
- `UsageError.isAuthenticationFailure` is internal to the module and used by `ClaudeUsageClient`.
- `UsageError.errorDescription` is public because `LocalizedError.localizedDescription` is asserted from the smoke test executable.
- `ClaudeUsageClient.fetch()` still exposes the same behavior to callers: it returns `ProviderUsage` rather than throwing.
- `ClaudeUsageClient.fetchFromAPI(token:)` contains the actual HTTP request and parsing.
- `ClaudeUsageClient.readTokenCandidates()` preserves auth precedence while allowing retry on selected failure modes.
- `TokenCandidate` and `TokenSource` are private implementation details.
- `CodexUsageClient` compiles unchanged with the expanded `HTTPClient.getJSON` signature.

## Files Changed

### Source code

- `Sources/TokenTrackerCore/HTTPClient.swift` — replaced generic HTTP failure text with typed usage errors for HTTP status, timeout, and network failures.
- `Sources/TokenTrackerCore/ClaudeUsageClient.swift` — added Keychain/file token candidate fallback and Claude-specific 10 second timeout.

### Tests

- `Sources/TokenTrackerSmokeTests/main.swift` — added assertions for stale cache display behavior and `UsageError` localized descriptions.

### Documentation / handoff

- `plans/handoffs/HANDOFF_claude-usage-stability_macos-auth-fallback_2026-06-05.md` — this continuity document.

### Unchanged by design

- `windows/TokenTracker.Windows.Core/UsageClient.cs` — Windows behavior intentionally unchanged.
- `Sources/TokenTrackerCore/UsageService.swift` — stale cache behavior already matched the plan.
- `Sources/TokenTrackerMenuBar/AppDelegate.swift` — menu already shows source and error lines.
- `Sources/TokenTrackerCore/CodexUsageClient.swift` — Codex behavior intentionally unchanged.

## User Feedback & Preferences (REQUIRED — never omit)

- User asked in Korean: `claude 와 codex 사용량 어떻게 추적하고 있는지 알려줘`.
- User wanted a practical explanation of current tracking, not speculation.
- User asked: `claude 사용량을 바로바로 못읽어오는 경우가 있는데 어느 부분에서 문제인지 예측 가능해?`.
- User accepted that there are separate cases: usage API reflection delay versus app read failure.
- User asked for a plan based on the predictions: `예측사항으로 수정계획 세워줘`.
- User chose `macOS 우선 (Recommended)` for implementation scope.
- User chose `유지+명확화 (Recommended)` for stale cache handling.
- User chose `60초 유지 (Recommended)` for refresh interval.
- User explicitly requested implementation: `PLEASE IMPLEMENT THIS PLAN`.
- User specified the plan should keep Windows untouched.
- User specified stale cache should remain but show clearer source/error information.
- User specified Claude timeout should become 10 seconds.
- User specified Keychain-to-file fallback only when Keychain token gets `401` or `403`.
- User requested this handoff and a commit/push: `handoff 하고 커밋 푸쉬`.

## Where We're Going

- Finish this request by staging the Swift changes and this handoff file.
- Commit with a message focused on Claude usage stability.
- Push `main` to `origin`.
- In a future session, optionally add dependency-injected HTTP tests for retry behavior if the project grows beyond smoke tests.
- In a future session, optionally apply equivalent diagnostic HTTP errors to Windows, but only if the user asks or Windows failures are observed.
- In a future session, manually verify a real stale Keychain token scenario if the user can reproduce one locally.

## Risks & Blockers

- The retry path for actual `401/403` was not covered by a live API test because it requires manipulating personal Claude credentials.
- The smoke test validates error descriptions and stale cache formatting but not network retry sequencing.
- Claude usage API may still reflect usage with delay; this implementation only improves app-side fetch reliability and diagnostics.
- `UsageError` became public for test visibility, which is a small API surface expansion of `TokenTrackerCore`.
- Push may require GitHub credentials/network access outside the local sandbox.

## Open Questions

- Does the user's local failure mode show `Source: staleCache` with an HTTP error after this change, or does it remain `Source: api` with delayed usage values?
- Should the project eventually introduce a proper test target with injectable URL session mocks instead of relying on smoke tests?
- Should Windows get matching HTTP status diagnostics later?

## Quick Start for Next Session

```bash
# Restore context
git status -sb

# Reference docs
sed -n '1,220p' WORK_SUMMARY.md
sed -n '60,90p' agent.md

# Key files to read first
sed -n '1,170p' Sources/TokenTrackerCore/ClaudeUsageClient.swift
sed -n '1,130p' Sources/TokenTrackerCore/HTTPClient.swift
sed -n '1,90p' Sources/TokenTrackerCore/UsageService.swift
sed -n '1,90p' Sources/TokenTrackerSmokeTests/main.swift

# Verify current state
swift run TokenTrackerSmokeTests
swift build

# Next action
If the user reports another Claude read failure, ask them for the menu's Claude Source and Error lines, then map that exact string to HTTP/auth/cache behavior.
```
