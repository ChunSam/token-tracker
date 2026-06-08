# Claude 429 cooldown and Claude plan display

**Date:** 2026-06-06
**Status:** IN PROGRESS
**Bead(s):** none
**Epic:** Token Tracker usage reliability
**Chain:** `claude-usage-stability` seq `2`
**Parent:** `HANDOFF_claude-usage-stability_macos-auth-fallback_2026-06-05.md`
**Prior chain:** `HANDOFF_claude-usage-stability_macos-auth-fallback_2026-06-05.md` > this

---

## Stale References

- `UsageError.httpStatus(code:service:)` — parent seq 1 used the older two-argument case; current code uses `UsageError.httpStatus(code:service:retryAfter:)`.
- `ClaudeUsageClient.fetchFromAPI(token:)` — parent seq 1 named the old one-argument helper; current code uses `fetchFromAPI(token:fallbackPlan:)`.

## Since Last Handoff

- Parent seq 1 ended after improving Claude auth fallback, timeout handling, and error diagnostics, then committing and pushing `c89e86f Improve Claude usage fetch diagnostics`.
- The user then installed the rebuilt macOS app, saw `HTTP 429 from Claude API`, and asked to investigate the live Claude 429 problem.
- The first new finding was that only one `/Applications/Token Tracker.app/Contents/MacOS/TokenTrackerMenuBar` process was running, so duplicate app instances were not the direct cause.
- The rate-limit problem did materialize: a live app refresh produced Claude `source: staleCache` with `error: HTTP 429 from Claude API; retrying after 1m` while Codex remained `source: api`.
- The implementation trajectory shifted from only "diagnose and show errors" to "respect 429 retry timing and avoid repeatedly hitting Claude while rate-limited."
- After the cooldown fix was installed, a later refresh returned Claude `source: api`, confirming the app could recover cleanly.
- The user then reported `claude에 플랜 표시 안됌`; this exposed a separate data parsing gap in `ClaudeUsageClient`.
- The Claude plan gap is fixed locally and installed, but all new changes remain uncommitted in the working tree.

## Reference Documents

- `plans/handoffs/HANDOFF_claude-usage-stability_macos-auth-fallback_2026-06-05.md` — parent handoff for Claude usage reliability, token fallback, timeout, and diagnostic context.
- `WORK_SUMMARY.md` — project summary and intended menu behavior, including provider plan display.
- `agent.md` — project conventions and usage lookup notes for Claude and Codex.
- `README.md` — user-facing Token Tracker behavior and build/install notes.

## The Goal

The active objective is to make Token Tracker's macOS Claude usage display reliable and complete enough for daily menu-bar use.
After seq 1 made failures visible, the user observed real `HTTP 429` behavior from Claude and wanted it handled rather than simply reported every minute.
The session then expanded to fix missing Claude plan display, because the app already showed Codex plan information and the menu had a generic `Plan` row.
The target end state is a locally installed macOS app that shows Claude/Codex remaining usage, source/error state, and plan information without unnecessary Claude API retry pressure.
No commit was requested in this final handoff turn.

## Where We Are

- Repo path is `/Users/jkl/Projects/Token tracker`.
- Active branch is `main`.
- Latest committed project commit at handoff creation is `c89e86f Improve Claude usage fetch diagnostics`.
- Working tree is dirty with four modified files.
- Modified files are `Sources/TokenTrackerCore/ClaudeUsageClient.swift`, `Sources/TokenTrackerCore/HTTPClient.swift`, `Sources/TokenTrackerMenuBar/AppDelegate.swift`, and `Sources/TokenTrackerSmokeTests/main.swift`.
- `git diff --stat` currently reports 4 files, 158 insertions, and 22 deletions.
- The app was rebuilt with `scripts/build_app.sh`.
- The rebuilt app was installed to `/Applications/Token Tracker.app` using `ditto`.
- The installed executable timestamp after the final install is `Jun  6 00:48:42 2026 /Applications/Token Tracker.app/Contents/MacOS/TokenTrackerMenuBar`.
- The app was relaunched successfully after install.
- Process check showed a single app process: PID `83176`, command `/Applications/Token Tracker.app/Contents/MacOS/TokenTrackerMenuBar`.
- Current cache after final install has Claude `source: api`.
- Current cache after final install has Claude `plan: max`.
- Current cache after final install has Claude 5h remaining `40` and 7d remaining `94`.
- Current cache after final install has Codex `source: api`.
- Current cache after final install has Codex `plan: prolite`.
- `swift run TokenTrackerSmokeTests` passed after the 429 cooldown and plan-display changes.
- `swift build` passed after the 429 cooldown and plan-display changes.
- `git diff --check` passed with no whitespace errors.
- `Sources/TokenTrackerCore/HTTPClient.swift` now reads the `Retry-After` header for non-2xx responses.
- `UsageError.httpStatus` now stores an optional `retryAfter: TimeInterval?`.
- `UsageError.rateLimitRetryAfter` returns the retry interval for `HTTP 429` only.
- `UsageError.errorDescription` now formats 429 as `HTTP 429 from Claude API; retrying after 5m` when a retry delay exists.
- `Sources/TokenTrackerCore/ClaudeUsageClient.swift` now stores rate-limit cooldown state in `ClaudeRateLimitState`.
- Claude 429 handling now uses server `Retry-After` when present.
- Claude 429 handling uses a default cooldown of 300 seconds when no `Retry-After` exists.
- Claude 429 handling enforces a minimum cooldown of 120 seconds, so the 60-second timer skips at least one automatic refresh.
- `ClaudeUsageClient` and `ClaudeRateLimitState` are `@MainActor` to satisfy Swift 6 concurrency checking.
- `Sources/TokenTrackerMenuBar/AppDelegate.swift` now tracks an in-flight `refreshTask`.
- `refreshNow()` now returns early if a refresh is already running.
- `Sources/TokenTrackerCore/ClaudeUsageClient.swift` now parses Claude plan information from API/root metadata and credential metadata.
- Claude API plan keys checked are `plan_type`, `planType`, `subscription_type`, `subscriptionType`, `tier`, `rate_limit_tier`, and `rateLimitTier`.
- Keychain fallback metadata uses the existing `Claude Code-credentials` JSON under `claudeAiOauth`.
- The live Keychain metadata contained `claudeAiOauth.subscriptionType` and `claudeAiOauth.rateLimitTier`; token values were not printed or stored.
- `TokenCandidate` now carries both token and optional plan.
- `ClaudeCredential` was added as a private helper struct with `accessToken` and `plan`.
- If Claude API returns a plan field, it wins over local credential metadata.
- If Claude API does not return a plan field, credential metadata can populate `ProviderUsage.plan`.
- The existing menu code in `AppDelegate.addUsage` already displays `Plan` when `usage.plan` is non-nil, so no UI layout change was required for plan display.
- Windows code remains untouched.
- The final app install verified the user-visible effect through cache: Claude now has `plan: max`.

## What We Tried (Chronological)

1. The user reported `claude에서 오류 http 429 오류가 나고있어 확인해줘`.
2. Code search found the active Claude path in `Sources/TokenTrackerCore/ClaudeUsageClient.swift`, the HTTP wrapper in `HTTPClient.swift`, and stale cache logic in `UsageService.swift`.
3. The existing default refresh interval was confirmed as 60 seconds in `Settings.swift`.
4. User defaults for bundle id `local.token-tracker.menubar` were checked; no custom `refreshInterval` was stored, so 60 seconds was active.
5. The app cache was checked at `~/Library/Application Support/Token Tracker/usage-cache.json`.
6. Cache before the 429 fix showed recent successful API data, with Claude and Codex both previously saved from provider APIs.
7. A process check initially failed under sandbox with `operation not permitted`; it was rerun with approved `ps ax`.
8. `ps ax` showed one live Token Tracker app process, not multiple app instances.
9. The first hypothesis, duplicate app instances multiplying requests, was rejected.
10. The remaining hypothesis was that one app polling every 60 seconds plus manual refreshes could keep Claude in a rate-limited state.
11. `HTTPClient` was changed to preserve `Retry-After` for HTTP errors.
12. `UsageError` was expanded to include `retryAfter`.
13. `UsageError.errorDescription` was changed to show a human-readable cooldown for 429 errors.
14. `ClaudeUsageClient` was changed to keep cooldown state after 429.
15. The first cooldown implementation used a minimum of 60 seconds.
16. `swift run TokenTrackerSmokeTests` initially failed after adding state because Swift 6 warned that sending `self.claudeClient` risked data races.
17. `ClaudeUsageClient` was marked `@MainActor` to match the existing main-actor `UsageService` path.
18. The next compile failed because `ClaudeRateLimitState` referenced main-actor-isolated static constants from a nonisolated helper.
19. `ClaudeRateLimitState` was also marked `@MainActor`.
20. Smoke tests then passed.
21. `swift build` then passed.
22. The app was rebuilt with `scripts/build_app.sh`.
23. The app was quit via `osascript -e 'tell application id "local.token-tracker.menubar" to quit'`.
24. The app was copied into `/Applications/Token Tracker.app` using `ditto`.
25. The app was reopened with `open "/Applications/Token Tracker.app"`.
26. A live cache check after install showed Claude still got `HTTP 429 from Claude API; retrying after 1m`.
27. Because the app's timer is 60 seconds, a one-minute cooldown could align exactly with the next scheduled poll.
28. The minimum 429 cooldown was increased from 60 seconds to 120 seconds.
29. Smoke tests and `swift build` passed again.
30. The app was rebuilt, reinstalled, and relaunched again.
31. Final cache after the 429 fix showed Claude `source: api`, proving recovery from the transient 429 state.
32. The user then reported `claude에 플랜 표시 안됌`.
33. Code inspection showed `ClaudeUsageClient` always returned `plan: nil`.
34. `CodexUsageClient` was used as a comparison; Codex reads `object["plan_type"]`.
35. Windows C# parser was checked and also had `Plan` fields, but its Claude parser currently returned `null` for Claude plan.
36. A live direct Swift query to Claude usage API was attempted with token-safe output that only printed status and root keys.
37. That direct query returned `STATUS 429` and `ROOT_KEYS error`, so it could not reveal success-response plan field names.
38. To avoid extending the Claude rate-limit problem, another API query was not repeated.
39. A token-safe Keychain metadata script printed only JSON key paths and types, not token values.
40. Keychain metadata revealed `claudeAiOauth.subscriptionType` and `claudeAiOauth.rateLimitTier`.
41. `ClaudeUsageClient` was changed to read plan from API response keys first, then credential metadata as fallback.
42. `readTokenFromKeychain()` became `readCredentialFromKeychain()`.
43. `readTokenFromFile()` became `readCredentialFromFile()`.
44. `ClaudeCredential` and plan-bearing `TokenCandidate` were added.
45. Smoke tests and `swift build` passed again.
46. The app was rebuilt, reinstalled, and relaunched again.
47. Final cache showed Claude `plan: max`, confirming the plan display fix reached the running app.

## Key Decisions

- Treat real Claude `HTTP 429` as upstream rate limiting, not as an authentication problem.
- Do not retry with the file token on 429, because that would add traffic and was explicitly avoided in seq 1.
- Respect `Retry-After` when Claude returns it.
- Add a default 5-minute cooldown when Claude returns 429 without `Retry-After`.
- Enforce a 2-minute minimum cooldown because the app timer is 60 seconds and a 1-minute retry can collide with the next scheduled refresh.
- Keep the normal refresh interval at 60 seconds; the fix is provider-specific cooldown, not global polling slowdown.
- Keep stale cache behavior unchanged so the menu still shows last-known Claude values during 429.
- Preserve the error line during stale cache so the user can see whether the value is fresh API or cached after a failure.
- Prevent overlapping refreshes in `AppDelegate` because timer ticks and manual `Refresh Now` can otherwise stack provider requests.
- Mark Claude usage client state as `@MainActor` rather than introducing locks or actors, because current app refresh already runs through main-actor UI code.
- Avoid printing or storing tokens while inspecting credential metadata.
- Prefer API response plan fields over credential metadata because provider API data is more authoritative when available.
- Use Keychain `subscriptionType` / `rateLimitTier` only as fallback because current live success response was not safely inspectable during 429.
- Do not change Windows behavior in this session.
- Do not commit automatically, because the latest user request only invoked handoff.

## Evidence & Data

| Git command | Result |
|---|---|
| `git branch --show-current` | `main` |
| `git status -s` | 4 modified files |
| `git diff --stat` | 4 files, 158 insertions, 22 deletions |
| `git log --oneline -20` latest | `c89e86f Improve Claude usage fetch diagnostics` |
| Existing handoff search | `plans/handoffs/HANDOFF_claude-usage-stability_macos-auth-fallback_2026-06-05.md` |

| Validation command | Result | Notes |
|---|---|---|
| `swift run TokenTrackerSmokeTests` | passed | Passed after cooldown work and after plan fallback work |
| `swift build` | passed | Passed after cooldown work and after plan fallback work |
| `scripts/build_app.sh` | passed | Built `.build/Token Tracker.app` |
| `git diff --check` | passed | No whitespace errors |

| Installed app check | Result |
|---|---|
| `osascript -e 'application id "local.token-tracker.menubar" is running'` | `true` |
| `stat -f "%Sm %N" "/Applications/Token Tracker.app/Contents/MacOS/TokenTrackerMenuBar"` | `Jun  6 00:48:42 2026 /Applications/Token Tracker.app/Contents/MacOS/TokenTrackerMenuBar` |
| `ps ax -o pid,etime,command | rg "/Applications/Token Tracker.app/Contents/MacOS/TokenTrackerMenuBar$"` | `83176       00:08 /Applications/Token Tracker.app/Contents/MacOS/TokenTrackerMenuBar` |

| Live cache milestone | Claude source | Claude error | Claude plan | Codex source | Codex plan |
|---|---|---|---|---|---|
| Before cooldown fix verification | `api` | none | absent | `api` | `prolite` |
| During first 429 verification | `staleCache` | `HTTP 429 from Claude API; retrying after 1m` | absent | `api` | `prolite` |
| After final cooldown reinstall | `api` | none | absent | `api` | `prolite` |
| After Claude plan reinstall | `api` | none | `max` | `api` | `prolite` |

Final cache excerpt after plan fix:

```text
"claude" => {
  "plan" => "max"
  "provider" => "claude"
  "remainingPercent5h" => 40
  "remainingPercent7d" => 94
  "source" => "api"
  "updatedAt" => "2026-06-05T15:48:57Z"
}
"codex" => {
  "plan" => "prolite"
  "provider" => "codex"
  "remainingPercent5h" => 41
  "remainingPercent7d" => 57
  "source" => "api"
}
```

Direct Claude usage API probe during investigation:

```text
STATUS 429
ROOT_KEYS error
```

Sanitized Keychain metadata findings:

```text
KEYCHAIN_KEY claudeAiOauth.rateLimitTier __NSCFString
KEYCHAIN_KEY claudeAiOauth.subscriptionType NSTaggedPointerString
```

No token values were printed in the output used for this handoff.

Recent commit log context:

| Hash | Summary |
|---|---|
| `c89e86f` | Improve Claude usage fetch diagnostics |
| `f7e3ee7` | Merge pull request #1 from ChunSam/claude/code-security-audit-iOaYj |
| `afba55a` | Add security audit summary document |
| `88e545c` | Add defensive file-handling hardening |
| `eed7c92` | Harden Windows release workflow |
| `962ffda` | Add app icon to macOS bundle |
| `7e3124a` | Fix Windows tray menu size |
| `4e634b3` | Fix Windows logo fallback warning |
| `f65dd71` | Add Windows provider logo labels |
| `9f9164e` | Improve Windows tray behavior |

## Code Analysis

- `HTTPClient.getJSON(url:headers:timeout:serviceName:)` still performs a simple GET and returns parsed JSON.
- For non-2xx responses, `HTTPClient.getJSON` now extracts `Retry-After` from `HTTPURLResponse`.
- `retryAfterInterval(from:)` supports both numeric seconds and HTTP date format like `EEE, dd MMM yyyy HH:mm:ss z`.
- `UsageError.httpStatus(code:service:retryAfter:)` carries cooldown metadata without changing UI code outside localized descriptions.
- `UsageError.rateLimitRetryAfter` is internal and only returns a value for 429.
- `UsageError.formatRetryAfter` rounds up seconds and formats as seconds, minutes, or hours/minutes.
- `ClaudeUsageClient.fetch()` first asks `rateLimitState.currentError(serviceName:)`; if cooldown is active, it returns `.unavailable(.claude, error: ...)` without hitting the network.
- On successful Claude API fetch, `rateLimitState.clear()` resets cooldown.
- On 429 with a retry delay, `rateLimitState.backOff(for:)` stores the future retry time.
- On 429 without retry delay, `ClaudeUsageClient.defaultRateLimitCooldown` of 300 seconds is used.
- `ClaudeUsageClient.minimumRateLimitCooldown` is 120 seconds.
- `UsageService.refresh()` still handles the unavailable Claude result by applying stale cache when a recent successful cache exists.
- `AppDelegate.refreshNow()` now uses `refreshTask` as an in-flight guard.
- `defer { refreshTask = nil }` ensures the refresh guard clears after the async task completes.
- `ClaudeUsageClient.readPlan(from:)` checks both snake_case and camelCase key variants.
- `normalizedString(_:)` trims whitespace and rejects empty plan strings.
- `readCredentialFromKeychain()` still uses `/usr/bin/security find-generic-password -s "Claude Code-credentials" -w`.
- `readCredentialFromFile()` still reads `AppPaths.claudeCredentials`.
- `TokenCandidate` still deduplicates by token string in `readTokenCandidates()`, preserving prior behavior.
- Menu display did not require a code change because `AppDelegate.addUsage` already adds a `Plan` row when `usage.plan` is non-nil.

## Files Changed

### Source code

- `Sources/TokenTrackerCore/HTTPClient.swift` — added `Retry-After` parsing, expanded `UsageError.httpStatus`, added 429 retry-delay formatting, and exposed `rateLimitRetryAfter`.
- `Sources/TokenTrackerCore/ClaudeUsageClient.swift` — added main-actor rate-limit state, 429 cooldown behavior, default/minimum cooldown constants, and Claude plan extraction from API/credential metadata.
- `Sources/TokenTrackerMenuBar/AppDelegate.swift` — added `refreshTask` and an in-flight guard to avoid overlapping refreshes.

### Tests

- `Sources/TokenTrackerSmokeTests/main.swift` — updated `UsageError.httpStatus` callsites for `retryAfter` and added an assertion for `HTTP 429 from Claude API; retrying after 5m`.

### Installed artifacts

- `.build/Token Tracker.app` — rebuilt release app bundle.
- `/Applications/Token Tracker.app` — overwritten with the rebuilt app bundle and relaunched.

### Unchanged by design

- `Sources/TokenTrackerCore/UsageService.swift` — stale cache behavior already handled unavailable provider results correctly.
- `Sources/TokenTrackerMenuBar/AppDelegate.swift` menu plan row logic — existing `if let plan = usage.plan` already displayed provider plan.
- `Sources/TokenTrackerCore/CodexUsageClient.swift` — Codex plan behavior already worked and was left intact.
- `windows/TokenTracker.Windows.Core/*` — Windows remains unchanged for this macOS-focused session.

## User Feedback & Preferences (REQUIRED — never omit)

- User reported: `claude에서 오류 http 429 오류가 나고있어 확인해줘`.
- User expected direct investigation rather than only explaining what 429 means.
- User accepted app rebuild/reinstall workflow from prior turn and wanted local app behavior fixed.
- User later reported: `claude에 플랜 표시 안됌`.
- User expects Claude and Codex to have similar menu detail completeness where possible.
- User has been working in Korean and expects Korean-facing concise progress updates.
- User previously chose macOS-first scope and Windows untouched for Claude reliability changes.
- User previously chose to keep the 60-second refresh interval.
- User previously chose to keep stale cache but make source/error visible.
- User did not ask for a commit in the final handoff request.
- User explicitly invoked `[$handoff](/Users/jkl/.codex/skills/handoff/SKILL.md)` for this turn.

## Where We're Going

- Keep the current working tree intact; do not revert the four modified files.
- If the user asks to publish, stage the four modified files plus this handoff and commit them together.
- A likely commit message is `Handle Claude rate limits and plan display`.
- After commit, run `swift run TokenTrackerSmokeTests` and `swift build` again if any code changed after this handoff.
- If 429 recurs, check whether the menu shows `Source: staleCache` and whether `Error` includes a retry delay.
- If Claude plan disappears again, inspect cache first, then verify Keychain still has `claudeAiOauth.subscriptionType` or `rateLimitTier`.
- Optional future work: add injectable HTTP/session tests for 429 retry behavior instead of relying on smoke tests and live cache checks.

## Risks & Blockers

- The live Claude API can return 429 during validation, so repeated direct probing can make the condition worse.
- `Retry-After` behavior was validated through code and smoke tests, while live 429 recovery was observed through app cache rather than a deterministic unit test.
- Plan extraction relies on observed Keychain metadata and plausible API field names; the successful API response body was not printed because the live probe hit 429.
- Windows Claude plan display may still be absent because Windows Claude parser returns `null` for plan, but Windows was intentionally left untouched.
- The changes are installed locally but not committed.

## Open Questions

- Does Claude's successful usage API response include `plan_type`, `subscriptionType`, or only usage windows? Unknown because the safe direct probe hit 429.
- Should Windows get the same Claude plan fallback later?
- Should the project add proper unit tests with injected HTTP responses for 429 and plan parsing?
- Should plan strings like `max`/`prolite` be normalized for display casing, or should raw provider strings remain visible?

## Quick Start for Next Session

```bash
# Restore context
git status -sb

# Parent context
sed -n '1,340p' plans/handoffs/HANDOFF_claude-usage-stability_macos-auth-fallback_2026-06-05.md

# Current handoff
sed -n '1,380p' plans/handoffs/HANDOFF_claude-usage-stability_429-cooldown-plan_2026-06-06.md

# Key files to read first
sed -n '1,230p' Sources/TokenTrackerCore/ClaudeUsageClient.swift
sed -n '1,140p' Sources/TokenTrackerCore/HTTPClient.swift
sed -n '1,70p' Sources/TokenTrackerMenuBar/AppDelegate.swift
sed -n '55,75p' Sources/TokenTrackerSmokeTests/main.swift

# Verify current state
swift run TokenTrackerSmokeTests
swift build
plutil -p "$HOME/Library/Application Support/Token Tracker/usage-cache.json" 2>/dev/null

# Next action
If the user wants these changes saved remotely, stage and commit the four modified source/test files plus this handoff file, then push `main`.
```
