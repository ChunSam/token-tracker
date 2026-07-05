# Reduce Claude 429 pressure: longer polling interval + persisted 429 cooldown (macOS + Windows)

**Date:** 2026-07-05
**Status:** COMPLETED (implemented + verified; committed/pushed via PR in this handoff turn)
**Bead(s):** none (bd unavailable in this environment)
**Epic:** Token Tracker usage reliability
**Chain:** `claude-usage-stability` seq `3`
**Parent:** `HANDOFF_claude-usage-stability_429-cooldown-plan_2026-06-06.md`
**Prior chain:** `HANDOFF_claude-usage-stability_macos-auth-fallback_2026-06-05.md` > `HANDOFF_claude-usage-stability_429-cooldown-plan_2026-06-06.md` > this

---

## Stale References

Parent seq 2 identifiers, checked against the current codebase (a month of intervening refactors happened on other chains):

- `@MainActor ClaudeRateLimitState` — parent described this type as `@MainActor`. It is now a standalone `private actor ClaudeRateLimitState` in `ClaudeUsageClient.swift` (moved to an actor by the later `platform-optimization` chain). Still exists; its isolation changed.
- `AppDelegate.addUsage` — parent seq 2 referenced this menu-building method for the `Plan` row. It no longer exists; menu construction was extracted to `Sources/TokenTrackerMenuBar/StatusMenuBuilder.swift` by the `macos-menubar-refactor` chain.
- Still present and used this session: `ClaudeUsageClient.defaultRateLimitCooldown` (300s), `ClaudeUsageClient.minimumRateLimitCooldown` (120s), `fetchFromAPI(token:fallbackPlan:)`, `readCredentialFromKeychain()`, `readCredentialFromFile()`, `HTTPClient.getJSON(...)`, `AppDelegate.refreshTask` in-flight guard.

## Related Handoffs

Same repo, different work streams (reference only, not chain parents):
- `HANDOFF_platform-optimization_macos-windows-hardening_2026-06-09.md` — added the Windows C# port's `ClaudeRateLimitState`, Retry-After handling, and moved macOS rate-limit state to an actor. Directly relevant background for this session's Windows parity work.
- `HANDOFF_macos-usage-ux_windows-parity_2026-06-22.md` — Windows parity for usage UX.
- `HANDOFF_macos-menubar-refactor_appdelegate-modularization_2026-06-15.md` — extracted `StatusMenuBuilder`, `DiagnosticsReporter`; explains where the interval-warning menu row now lives.

## Since Last Handoff

- Parent seq 2 (2026-06-06) left the 429 cooldown + Claude plan work uncommitted; it was later committed and, per the `platform-optimization` chain, `ClaudeRateLimitState` was converted from `@MainActor` to an `actor`, and the Windows C# port gained its own `ClaudeRateLimitState` + Retry-After handling.
- ~1 month and several unrelated chains later (m4-menubar-stability, macos-usage-ux, macos-menubar-refactor, platform-optimization), the user hit `HTTP 429` from Claude again and re-opened the investigation from scratch: `현재 프로젝트 확인해서 claude http 429 에러 나오는 이유 확인해줘`.
- Parent's open question "should the project add proper unit tests with injected HTTP responses for 429?" was partially advanced: the Windows suite now injects a mock handler to prove the persisted cooldown survives a simulated restart (0 HTTP calls). macOS still has no HTTP mock; its new coverage tests the persistence store directly.
- Parent kept the refresh interval at 60s deliberately ("the fix is provider-specific cooldown, not global polling slowdown"). This session **reversed that call** for the default/floor because 429 recurred: the account-level limit is shared with Claude Code and other clients, so a slower default is now warranted.
- Parent's "cooldown state in memory only" (also reaffirmed in the platform-optimization handoff: "Keep Windows cooldown state in memory only; no persisted rate-limit state") was **deliberately reversed** this session — the in-memory-only cooldown was identified as a cause of repeated 429 on relaunch.

## Reference Documents

- `agent.md` — project conventions; line 78 documents the Claude usage API endpoint.
- `WORK_SUMMARY.md` — line 82 documents the `/api/oauth/usage` call.
- `README.md` — user-facing behavior and settings.
- `/Users/jkl/.claude/CLAUDE.md` — global conventions: Korean to user / English artifacts; verification discipline (CI-equivalent checks must pass locally); never push directly to a protected default branch (branch + PR).

## The Goal

Token Tracker is a menu-bar (macOS Swift) + system-tray (Windows C#/WinForms) app that displays Claude and Codex remaining usage. The user repeatedly sees `HTTP 429 from Claude API` because the app polls Anthropic's per-account, non-public `/api/oauth/usage` endpoint. The objective this session was to (1) explain the root cause and (2) reduce the app's contribution to that rate limit without removing the feature. The end state: a lower default polling rate on both platforms and a 429 cooldown that survives app restarts, so relaunching during a cooldown no longer immediately re-triggers 429.

## Where We Are

- Repo: `/Users/jkl/Projects/Token tracker`, branch `main` at `49a023c Tighten macOS menu bar icon spacing` (HEAD at session start).
- Implementation is COMPLETE on both platforms and verified. Committed + pushed via PR in this handoff turn (see Where We're Going for the exact commands/outcome).
- `git diff --stat` (before commit): **13 files changed, 204 insertions(+), 28 deletions(-)**, plus 1 new untracked file `Sources/TokenTrackerCore/ClaudeRateLimitStore.swift`.
- **Root cause diagnosed (three compounding factors):**
  1. Short polling of a per-account-rate-limited endpoint: default 60s (`Settings.swift:93`), min selectable 30s (`PreferencesWindowController.swift:119`), timer floor `max(15, …)` (`AppDelegate.swift:53`).
  2. Shared per-account budget: the same OAuth token (`Claude Code-credentials` keychain) is used by Claude Code itself, by any duplicate app instance (`runningInstanceCount()` is tracked), and by the Windows twin (`UsageClient.cs:9` hits the identical URL).
  3. In-memory-only cooldown: `ClaudeRateLimitState` held `retryAllowedAt` in memory, and `applicationDidFinishLaunching` calls `refreshNow()` immediately, so quitting/relaunching during a cooldown re-fired a still-rate-limited request.
- The app's existing 429 handling is otherwise defensive (no retry storm): honors `Retry-After`, else 300s default, min 120s; serves stale cache during cooldown.
- **macOS polling changes:** default `refreshInterval` 60→**300s**; timer floor `max(15,…)`→`max(60,…)`; interval options `30s/1m/5m`→`1m/5m/15m`; interval-warning threshold `< 60`→`< 300`.
- **Windows polling changes (parity):** `AppSettings.RefreshIntervalSeconds` 60→**300**; two `Math.Max(15,…)`→`Math.Max(60,…)` (`TrayAppContext.cs:39,381`); options `30s/1m/5m`→`1m/5m/15m` (`SettingsForm.cs`); warning `< 60`→`< 300` (`TrayAppContext.cs:230`).
- **macOS persistence:** new `ClaudeRateLimitStore` (public struct) writes `{retryAllowedAt}` ISO8601 JSON to `AppPaths.claudeRateLimit` (`~/Library/Application Support/Token Tracker/claude-rate-limit.json`, 0600). `ClaudeRateLimitState` actor now seeds from disk on first use, saves on backoff, clears on success/expiry.
- **Windows persistence (parity):** new internal `ClaudeRateLimitStore` writes to `AppPaths.ClaudeRateLimitStatePath` (`%AppData%/Token Tracker/claude-rate-limit.json`). `ClaudeRateLimitState` gained a constructor taking the store, `EnsureLoaded()`, and save/clear on backoff/clear. `UsageClient` gained an optional 4th ctor param `rateLimitStatePath` (backward compatible — main app still calls `new UsageClient()`).
- **Tests:** macOS smoke test added a `ClaudeRateLimitStore` round-trip test (future/expired/clear). Windows 429 test rewritten to use a temp state path and assert a fresh client honors the persisted cooldown with **0 HTTP calls** (simulated restart).
- **Verification passed:** macOS `swift build` OK + smoke `TokenTrackerSmokeTests passed`; Windows Core+Tests `TokenTracker.Windows.Tests passed` (via a locally bootstrapped .NET 10 SDK, since `dotnet` is not installed on this machine).
- **Out-of-scope fix:** a pre-existing date-bomb in the Windows test (`now` hardcoded to `2026-05-27`, `CacheStore.Load` compares to the real clock) was failing at `Program.cs:220`; fixed minimally so the suite goes green.
- WinForms main-app files (`net10.0-windows`) cannot compile on macOS; changes there were literal-only and hand-reviewed.
- A memory was saved: `~/.claude/projects/-Users-jkl-Projects-Token-tracker/memory/local-verification.md` (how to bootstrap dotnet + the date-bomb caveat).

## What We Tried (Chronological)

1. User (Korean): investigate why the current project throws Claude HTTP 429.
2. Surveyed repo: Swift macOS app under `Sources/` + Windows C# port under `windows/`. Grepped for `429|rate.?limit` → hits in `ClaudeUsageClient.swift`, `HTTPClient.swift`, `UsageClient.cs`, etc.
3. Read `ClaudeUsageClient.swift` + `HTTPClient.swift`: confirmed the app GETs `https://api.anthropic.com/api/oauth/usage` with the `Claude Code-credentials` OAuth bearer + `anthropic-beta: oauth-2025-04-20`.
4. Traced the scheduler: `AppDelegate.scheduleTimer()` uses `max(15, settings.refreshInterval)`; `Settings` default 60s; `PreferencesWindowController` offers 30s/1m/5m.
5. Read `ClaudeRateLimitState` (macOS actor) + Windows `ClaudeRateLimitState` (C# lock): both stored `retryAllowedAt` in memory only.
6. Identified the restart re-fire: `applicationDidFinishLaunching` → `refreshNow()` immediately; memory-only cooldown is lost on relaunch.
7. Confirmed shared per-account budget: keychain service `Claude Code-credentials` (same token Claude Code uses); Windows `UsageClient.cs:9` hits the identical URL; `runningInstanceCount()` tracked (duplicate instances).
8. Delivered a Korean diagnosis + 4 mitigation options; recommended #1 (raise interval) + #2 (persist cooldown). Deferred #3 (single-instance guard) and #4 (exponential backoff + jitter).
9. User: `추천 조합으로 진행` (proceed with the recommended combo).
10. Gathered all edit sites across both platforms (settings, timer, prefs UI, warning threshold, paths, tests) before editing, to keep macOS/Windows parity.
11. macOS interval edits: `Settings.swift` 60→300; `AppDelegate.swift` floor 15→60; `PreferencesWindowController.swift` options → 1m/5m/15m; `StatusMenuBuilder.swift` warning `< 60`→`< 300`.
12. macOS persistence: added `AppPaths.claudeRateLimit`; created `ClaudeRateLimitStore.swift`; rewired the `ClaudeRateLimitState` actor with `loadIfNeeded()`, save-on-backoff, clear-on-success/expiry.
13. macOS test: added a store round-trip smoke test (save future → load ≈equal; save past → load nil; clear → load nil).
14. `swift build` → OK (39s); `swift run TokenTrackerSmokeTests` → `TokenTrackerSmokeTests passed`.
15. Windows interval edits (parity): `SettingsStore.cs` 60→300; `TrayAppContext.cs` two `Math.Max(15…)`→60 (replace_all) + warning `< 60`→`< 300`; `SettingsForm.cs` options → 1m/5m/15m.
16. Windows persistence: added `AppPaths.ClaudeRateLimitStatePath`; added internal `ClaudeRateLimitStore` (System.Text.Json, future-only load, self-cleaning); rewired `ClaudeRateLimitState` with a store ctor + `EnsureLoaded()`; added optional `rateLimitStatePath` ctor param to `UsageClient`; added `using System.Text.Json;`.
17. Windows test: rewrote the 429 block to inject a temp state path and assert a **second** `UsageClient` (simulated restart) returns Unavailable with `CallCount == 0`; added `File.Exists(rateLimitStatePath)` assertion; wrapped in try/finally cleanup.
18. Checked `dotnet` availability → **not installed**. Verified Core+Tests target `net10.0` (cross-platform) while the main app targets `net10.0-windows`.
19. Bootstrapped .NET 10 SDK without sudo: `curl https://dot.net/v1/dotnet-install.sh` → `--channel 10.0 --install-dir <scratchpad>/dotnet` (installed `10.0.301`).
20. First `dotnet run` of the Windows tests **failed** at `Program.cs:220` `Cache loads saved snapshot` — NOT my code: `now = new DateTimeOffset(2026,5,27,…)` is 39 days before the real clock (2026-07-05), so `CacheStore.Load(1h)` treated the cached snapshot as expired. My new 429 persistence test (earlier in the file, ~line 130-155) had already passed before the failure.
21. Fixed the date-bomb minimally: `cacheStore.Save(staleSnapshot with { UpdatedAt = DateTimeOffset.Now })` so only the freshness-sensitive snapshot is stamped at real time.
22. Re-ran Windows tests → `TokenTracker.Windows.Tests passed`.
23. Visually re-checked `SettingsForm.cs` array syntax (3 `Option<int>` entries, no trailing-comma break) since it can't compile locally.
24. Saved `local-verification.md` memory + `MEMORY.md` index entry.
25. User invoked `/handoff` with args `하고 푸시 해줘` (write handoff and push).

## Key Decisions

- **Chose interval-up + cooldown-persistence** (user-approved). Deferred single-instance guard and exponential-backoff+jitter to a future session.
- **Default 5m, min 1m, added 15m; removed the 30s option** — 30s (120 req/h) against a shared per-account endpoint was the most aggressive contributor.
- **Kept the "short interval" warning meaningful** by raising its threshold from `< 60` to `< 300`, so selecting the new floor (1m) still warns. Otherwise the warning could never fire (min is now 60).
- **Load returns future-only** (`ClaudeRateLimitStore.load()` filters expired to nil) so a stale past record can't be mistaken for an active cooldown; the actor still re-checks `remaining <= 0` defensively.
- **`ClaudeRateLimitStore` made `public` on Swift** solely so the separate `TokenTrackerSmokeTests` target can exercise it (macOS has no HTTP mock harness, so the store is the only unit-testable seam). Kept `internal` on Windows because the test only touches the public `UsageClient`.
- **Added an optional `rateLimitStatePath` param to Windows `UsageClient`** so tests write to a temp file instead of the real `%AppData%` (avoids cross-run state leakage / flakiness). Kept it optional → `new UsageClient()` in the main app is unchanged.
- **Fixed the pre-existing date-bomb minimally** (only the freshness snapshot) rather than changing the global test `now` — changing `now` (a fixed `TimeSpan.Zero` offset used by many assertions) risked wider breakage.
- **Bootstrapped .NET locally** rather than skipping Windows verification, honoring the global "CI-equivalent checks must pass locally" rule.
- **Did not migrate legacy stored intervals** (e.g. a saved 30s value): the timer floor `max(60,…)` already clamps the effective poll rate; only cosmetic (popup shows no matching selection).
- **Push via feature branch + PR, not direct to `main`** — global convention forbids pushing to a protected default branch even though the repo's history is all direct-to-main.

## Evidence & Data

`git diff --stat` at handoff time (pre-commit):

| File | +/- |
|---|---|
| Sources/TokenTrackerCore/ClaudeUsageClient.swift | 27 |
| Sources/TokenTrackerCore/Paths.swift | 4 |
| Sources/TokenTrackerCore/Settings.swift | 2 |
| Sources/TokenTrackerMenuBar/AppDelegate.swift | 2 |
| Sources/TokenTrackerMenuBar/PreferencesWindowController.swift | 2 |
| Sources/TokenTrackerMenuBar/StatusMenuBuilder.swift | 2 |
| Sources/TokenTrackerSmokeTests/main.swift | 19 |
| windows/TokenTracker.Windows.Core/AppPaths.cs | 3 |
| windows/TokenTracker.Windows.Core/SettingsStore.cs | 2 |
| windows/TokenTracker.Windows.Core/UsageClient.cs | 107 |
| windows/TokenTracker.Windows.Tests/Program.cs | 52 |
| windows/TokenTracker.Windows/SettingsForm.cs | 4 |
| windows/TokenTracker.Windows/TrayAppContext.cs | 6 |
| **new** Sources/TokenTrackerCore/ClaudeRateLimitStore.swift | (untracked) |

Total tracked: 13 files, 204 insertions, 28 deletions.

Polling behavior — before vs after (both platforms):

| Knob | Before | After |
|---|---|---|
| Default interval | 60s | **300s (5m)** |
| Timer floor (effective min) | 15s | **60s** |
| Selectable options | 30s / 1m / 5m | **1m / 5m / 15m** |
| "Short interval" warning fires when | `< 60s` | `< 300s` |

Verification results:

| Check | Command | Result |
|---|---|---|
| macOS build | `swift build` | Build complete (~39s) |
| macOS smoke | `swift run TokenTrackerSmokeTests` | `TokenTrackerSmokeTests passed` |
| Windows Core+Tests | `<scratchpad>/dotnet/dotnet run --project windows/TokenTracker.Windows.Tests/…csproj` | `TokenTracker.Windows.Tests passed` |
| dotnet SDK (bootstrapped) | `dotnet --version` | `10.0.301` |
| WinForms main app | (net10.0-windows) | Not compilable on macOS — hand-reviewed only |

Pre-existing date-bomb (fixed this session):

```text
Unhandled exception. System.InvalidOperationException: Cache loads saved snapshot
   at Program.<…>g__Expect|0_1(Boolean condition, String message) in …/Program.cs:line 16
   at Program.<Main>$(String[] args) in …/Program.cs:line 220
```
Root: `var now = new DateTimeOffset(2026, 5, 27, 0, 0, 0, TimeSpan.Zero);` (Program.cs:20) vs `CacheStore.Load` comparing `DateTimeOffset.Now - snapshot.UpdatedAt > maxAge` against the real clock (2026-07-05). Fix: stamp the cached snapshot with `DateTimeOffset.Now`.

Persistence file (both platforms), example content:
```json
{"retryAllowedAt":"2026-07-05T15:10:00Z"}
```
macOS path: `~/Library/Application Support/Token Tracker/claude-rate-limit.json` (0600).
Windows path: `%AppData%/Token Tracker/claude-rate-limit.json`.

The four mitigation options presented (user picked #1 + #2):

| # | Option | Effect | Status |
|---|---|---|---|
| 1 | Raise default/min polling interval | Fewer requests/hour — the largest single lever | **Done** |
| 2 | Persist 429 cooldown to disk | Relaunch during cooldown no longer re-fires 429 | **Done** |
| 3 | Single-instance guard | Stop a duplicate instance from doubling the request rate | Deferred |
| 4 | Exponential backoff + jitter on repeat 429 | Smoother recovery than a flat cooldown | Deferred |

Request the app sends to `https://api.anthropic.com/api/oauth/usage` (GET, 10s timeout, `ClaudeUsageClient.fetchFromAPI`):
- `Accept: application/json`, `Content-Type: application/json`
- `Authorization: Bearer <oauth accessToken>` — from `Claude Code-credentials` keychain (`/usr/bin/security find-generic-password -s "Claude Code-credentials" -w`), else `~/.claude/.credentials.json` → `claudeAiOauth.accessToken`
- `anthropic-beta: oauth-2025-04-20`
- `User-Agent: TokenTrackerMenuBar/1.0` (Windows: `TokenTrackerWindows/1.0`)

Response shape consumed: `five_hour.utilization`, `five_hour.resets_at`, `seven_day.utilization`, `seven_day.resets_at`; remaining% = `remainingPercent(fromUsed:)`; plan from any of `plan_type / planType / subscription_type / subscriptionType / tier / rate_limit_tier / rateLimitTier`, else credential metadata.

Approximate request rate per client (one request per refresh), showing why 30s was the worst contributor:

| Interval | Requests/hour |
|---|---|
| 30s (removed) | 120 |
| 60s (old default / new floor) | 60 |
| 300s (new default) | 12 |
| 900s (new max) | 4 |

Effective load = (per-interval rate) × (# app instances) + Claude Code's own usage checks + the Windows twin — all against one per-account limit.

Core persistence logic (macOS `ClaudeRateLimitStore.load()`, the ground-truth "future-only" filter):
```swift
public func load() -> Date? {
    guard
        let data = try? Data(contentsOf: url),
        let record = try? decoder.decode(Record.self, from: data),
        record.retryAllowedAt.timeIntervalSinceNow > 0   // expired/missing → nil
    else { return nil }
    return record.retryAllowedAt
}
```

## Code Analysis

- `ClaudeRateLimitStore.load()` (Swift) returns the persisted `Date` only when `retryAllowedAt.timeIntervalSinceNow > 0`; missing/expired/parse-fail → `nil`. `save()` creates the dir (0700), atomic-writes, re-applies 0600. `clear()` removes the file.
- `ClaudeRateLimitState` actor (Swift): `loadIfNeeded()` seeds `retryAllowedAt` from the store once (`didLoad` guard). `currentError` clears the store when the cooldown has elapsed. `backOff` computes `max(minimumRateLimitCooldown=120, retryAfter)` and persists. `clear` wipes memory + store.
- Because `fetch()` returns early while `currentError` is non-nil, `backOff` is never re-invoked during an active cooldown → the Windows test still asserts `CallCount == 1` on repeat calls within one process (matches parent's behavior).
- Windows `ClaudeRateLimitStore` mirrors this with `System.Text.Json`; `Load()` returns `null` when `record.RetryAllowedAt <= DateTimeOffset.Now`. The positional `record Record(DateTimeOffset RetryAllowedAt)` round-trips under default STJ options (PascalCase property ↔ case-insensitive ctor-param match).
- Windows `UsageClient` ctor now: `new ClaudeRateLimitState(new ClaudeRateLimitStore(rateLimitStatePath ?? AppPaths.ClaudeRateLimitStatePath))`. All ctor params remain optional.
- The interval-warning row lives in `StatusMenuBuilder.swift:96` (macOS) and `TrayAppContext.cs:230` (Windows) — both gated on the interval threshold.
- macOS smoke assertions (new): empty store → `nil`; `save(+300s)` → `load()` within 1s of the saved instant; `save(-1s)` → `nil` (expired filtered); `save` then `clear()` → `nil`. Uses a temp URL in `FileManager.default.temporaryDirectory` with a `defer` cleanup.
- Windows test flow (new): 429 response (Retry-After 300) → first fetch Unavailable, `CallCount==1` → repeat within same process still `CallCount==1` (cooldown short-circuits) → assert `File.Exists(rateLimitStatePath)` → construct a **second** `UsageClient` with a fresh OK handler → fetch returns Unavailable with `CallCount==0` (persisted cooldown honored) → `finally` deletes the temp state file and the temp home dir.
- Token candidate handling is unchanged: `readTokenCandidates()` dedups the keychain token vs the file token by string; on `401/403` from the keychain source it falls through to the file token, but a `429` is not an auth failure so it does not multiply requests across candidates.
- `applicationDidFinishLaunching` order (macOS): `refreshNow()` (immediate) → `scheduleTimer()`. This immediate first fetch is exactly why the in-memory-only cooldown re-fired 429 on every relaunch, and why persistence matters.
- Defensive-by-design (unchanged this session): `fetch()` makes at most one network call per refresh; `AppDelegate.refreshTask` blocks overlapping refreshes; so the app itself never retry-storms — it only surfaces the server's 429.
- `UsageService.refresh()` fetches Claude and Codex concurrently via `async let`, then `UsageSnapshotCachePolicy.apply(current:stale:…)` replaces an unavailable provider with the last good cache (`cacheStore.load(maxAge: 3600)`) tagged `.staleCache`, preserving the error string — so during a 429 the menu still shows last-known values plus the retry message.
- `HTTPClient.getJSON` throws `UsageError.httpStatus(code:service:retryAfter:)` for non-2xx; `retryAfterInterval(from:)` parses numeric seconds or the HTTP-date form `EEE, dd MMM yyyy HH:mm:ss z`.
- macOS `ClaudeUsageClient` is a `struct` holding `private let rateLimitState = ClaudeRateLimitState(store: ClaudeRateLimitStore(url: AppPaths.claudeRateLimit))`; the actor is file-private and the store is `public` only to reach the smoke-test target.

## Files Changed

### Source — macOS
- `Sources/TokenTrackerCore/ClaudeRateLimitStore.swift` — **new**; persistent 429 cooldown store (public for smoke-test access).
- `Sources/TokenTrackerCore/ClaudeUsageClient.swift` — `ClaudeRateLimitState` actor now takes a store, loads on first use, saves on backoff, clears on success/expiry.
- `Sources/TokenTrackerCore/Paths.swift` — added `claudeRateLimit` URL.
- `Sources/TokenTrackerCore/Settings.swift` — default `refreshInterval` 60→300.
- `Sources/TokenTrackerMenuBar/AppDelegate.swift` — timer floor `max(15…)`→`max(60…)`.
- `Sources/TokenTrackerMenuBar/PreferencesWindowController.swift` — interval options → 1m/5m/15m.
- `Sources/TokenTrackerMenuBar/StatusMenuBuilder.swift` — warning threshold `< 60`→`< 300`.

### Source — Windows
- `windows/TokenTracker.Windows.Core/UsageClient.cs` — new `ClaudeRateLimitStore`; `ClaudeRateLimitState` persists; `UsageClient` optional `rateLimitStatePath`; `using System.Text.Json;`.
- `windows/TokenTracker.Windows.Core/AppPaths.cs` — added `ClaudeRateLimitStatePath`.
- `windows/TokenTracker.Windows.Core/SettingsStore.cs` — default `RefreshIntervalSeconds` 60→300.
- `windows/TokenTracker.Windows/TrayAppContext.cs` — two timer floors →60; warning threshold →300.
- `windows/TokenTracker.Windows/SettingsForm.cs` — interval options → 1m/5m/15m.

### Tests
- `Sources/TokenTrackerSmokeTests/main.swift` — `ClaudeRateLimitStore` round-trip (future/expired/clear).
- `windows/TokenTracker.Windows.Tests/Program.cs` — 429 test uses temp state path + restart-persistence (0 HTTP calls) assertion; fixed pre-existing CacheStore date-bomb.

### Memory / tooling (not in repo)
- `~/.claude/projects/-Users-jkl-Projects-Token-tracker/memory/local-verification.md` (+ `MEMORY.md` index) — dotnet bootstrap + date-bomb caveat.
- `<scratchpad>/dotnet/` — locally installed .NET 10 SDK (10.0.301), scratchpad-isolated.

## User Feedback & Preferences (REQUIRED — never omit)

- `현재 프로젝트 확인해서 claude http 429 에러 나오는 이유 확인해줘` — wanted a real root-cause investigation of the live 429, not a definition.
- `추천 조합으로 진행` — accepted the recommended combo (#1 interval-up + #2 cooldown-persistence); implicitly deferred the other two options.
- `/handoff 하고 푸시 해줘` — write the handoff AND push.
- Works in Korean; expects Korean-facing replies with English code/artifacts (global convention).
- Established preferences from this chain: keep the feature (don't disable Claude polling); keep stale cache visible; macOS/Windows parity matters (the Windows port must track macOS changes).

## Where We're Going

1. **This handoff turn: commit + push via PR.** Global convention forbids direct push to `main`, so: create a feature branch, commit all 13 changes + the new store file + this handoff, push the branch, open a PR. (Repo history is otherwise all direct-to-main; if the user prefers that, they can merge the PR or ask for a direct push.)
2. Suggested commit message: `Reduce Claude 429 pressure: longer poll interval + persisted cooldown`.
3. Future option #3 — single-instance guard (`runningInstanceCount()` already exists; make a second launch exit or no-op its poller).
4. Future option #4 — exponential backoff + jitter on repeated 429 (currently a flat `max(retryAfter,120)` / 300s default).
5. Consider migrating legacy stored `refreshInterval < 60` values up to 60 (currently only clamped by the timer floor; the prefs popup shows no selection for a stale 30).
6. Windows WinForms changes (`TrayAppContext.cs`, `SettingsForm.cs`) are hand-reviewed only — the CI `windows-release.yml` (`dotnet run` tests + `dotnet publish`) will compile them; watch that run.

## Risks & Blockers

- WinForms main-app files can't be compiled on this macOS machine (`net10.0-windows` targeting pack unavailable). The edits are literal-only, but only CI or a Windows box truly verifies them.
- 429 is fundamentally server-side and per-account-shared. These mitigations lower the app's own contribution but cannot prevent 429 if Claude Code (or another client on the same account) is independently hammering `/api/oauth/usage`.
- The bootstrapped dotnet lives in the session scratchpad; a future session must re-bootstrap (see `local-verification.md`) to re-run Windows tests locally.
- Pushing to `main` may be blocked by branch protection (unknown); the PR route sidesteps this.

## Open Questions

- Should legacy stored `refreshInterval` values (< 60) be migrated up, or is the timer-floor clamp sufficient?
- Do the users want option #3/#4 next, or is this combo enough for now?
- Should the repo standardize on direct-to-main (its historical pattern) vs the PR flow this session used?

## Quick Start for Next Session

```bash
# Restore context
cd "/Users/jkl/Projects/Token tracker" && git status -sb && git log --oneline -6

# Prior chain (read parent first)
sed -n '1,120p' plans/handoffs/HANDOFF_claude-usage-stability_429-cooldown-plan_2026-06-06.md
sed -n '1,200p' plans/handoffs/HANDOFF_claude-usage-stability_polling-cooldown-persistence_2026-07-05.md

# Key files to read first
sed -n '1,80p'  Sources/TokenTrackerCore/ClaudeRateLimitStore.swift
sed -n '1,70p'  Sources/TokenTrackerCore/ClaudeUsageClient.swift   # ClaudeRateLimitState actor at bottom
sed -n '175,300p' windows/TokenTracker.Windows.Core/UsageClient.cs # ClaudeRateLimitState + Store

# Verify current state — macOS
swift build && swift run TokenTrackerSmokeTests

# Verify current state — Windows (dotnet not installed; bootstrap per memory)
# curl -fsSL https://dot.net/v1/dotnet-install.sh | bash -s -- --channel 10.0 --install-dir <scratchpad>/dotnet
# <scratchpad>/dotnet/dotnet run --project windows/TokenTracker.Windows.Tests/TokenTracker.Windows.Tests.csproj

# Next action
# If not already merged: review/merge the PR opened this handoff turn.
# Then, if the user wants more 429 hardening: implement option #3 (single-instance guard) and/or #4 (backoff+jitter).
```

## Session Closed

**Closed at:** 2026-07-06 00:05 KST
**Branch:** `claude-429-poll-cooldown` (pushed) → PR against `main` (see PR link in the session report)
**Commit:** single commit on the branch; run `git log --oneline -1 claude-429-poll-cooldown` for the hash
**Session status:** Handed off to next session
