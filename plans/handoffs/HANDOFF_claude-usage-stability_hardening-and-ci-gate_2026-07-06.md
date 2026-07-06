# Complete deferred 429 hardening (backoff+jitter, single-instance guard, interval migration) + add PR CI gate + persist backoff level

**Date:** 2026-07-06
**Status:** COMPLETED (implemented, verified, committed, merged to `main` via two PRs; branches deleted)
**Bead(s):** none (bd unavailable in this environment)
**Epic:** Token Tracker usage reliability
**Chain:** `claude-usage-stability` seq `4`
**Parent:** `HANDOFF_claude-usage-stability_polling-cooldown-persistence_2026-07-05.md` (seq 3)
**Prior chain:** `HANDOFF_claude-usage-stability_macos-auth-fallback_2026-06-05.md` > `HANDOFF_claude-usage-stability_429-cooldown-plan_2026-06-06.md` > `HANDOFF_claude-usage-stability_polling-cooldown-persistence_2026-07-05.md` > this

---

## Stale References

Parent seq 3 identifiers, re-checked against the current codebase. Most still exist; two changed this session:

- `ClaudeUsageClient.minimumRateLimitCooldown` (was 120s constant) — **REMOVED** this session. The 120s floor moved into the new `RateLimitBackoff.minimumCooldown`. `ClaudeUsageClient.defaultRateLimitCooldown` (300s, headerless-429 arg) still exists.
- `ClaudeRateLimitStore.save(retryAllowedAt:)` / `load() -> Date?` (macOS) — **SIGNATURE CHANGED**. Now `save(_ state: State)` / `load() -> State?` where `State = {retryAllowedAt, failureCount}`. Windows `ClaudeRateLimitStore.Save(DateTimeOffset)` / `Load() -> DateTimeOffset?` likewise became `Save(DateTimeOffset, int)` / `Load() -> ClaudeRateLimitSnapshot?`.
- Still present & used: `ClaudeRateLimitState` actor (macOS) / `internal sealed class` (Windows), `AppPaths.claudeRateLimit` / `AppPaths.ClaudeRateLimitStatePath`, `AppDelegate.runningInstanceCount()`, `scripts/build_app.sh`, `UsageClient.DefaultClaudeRateLimitCooldown` (5m).

## Related Handoffs

Same repo, other work streams (reference only, not chain parents):
- `HANDOFF_platform-optimization_macos-windows-hardening_2026-06-09.md` — added the Windows `ClaudeRateLimitState`, Retry-After handling, moved macOS rate-limit state to an actor.
- `HANDOFF_macos-menubar-refactor_appdelegate-modularization_2026-06-15.md` — extracted `StatusMenuBuilder` / `DiagnosticsReporter`; explains where menu construction now lives.

## Since Last Handoff

Parent seq 3 (2026-07-05) shipped the interval-up + persisted-cooldown work and left PR #2 (`claude-429-poll-cooldown`) OPEN, deferring options #3 (single-instance guard) and #4 (exponential backoff + jitter). This session:

- **Merged parent's PR #2** and then **completed both deferred options plus the legacy-interval migration** the parent listed as future work. All three landed in PR #2's branch as a second commit before merge.
- **Discovered the Windows single-instance guard already existed** (named Mutex in `windows/TokenTracker.Windows/Program.cs`), so option #3 collapsed to a macOS-only task for parity — smaller than the parent anticipated.
- **Answered parent's open questions:** legacy `refreshInterval < 60` values ARE now migrated (up to 60); options #3/#4 were wanted (done); the repo used the PR-flow (not direct-to-main) twice and the user merged both via `gh` after explicit approval.
- **Closed a gap the parent flagged as risk #6** ("WinForms only compiled by release CI") — this session found there was NO `pull_request`/`push` CI at all, and added one (`.github/workflows/ci.yml`). The WinForms app is now compiled on every PR; the first CI run proved it compiles.
- **Extended the persistence** the parent introduced: the 429 cooldown record now also stores `failureCount`, so exponential-backoff escalation survives a restart (parent persisted only `retryAllowedAt`).
- **Verified the macOS single-instance guard end-to-end** with a real `.app` two-instance launch (parent's option was only a plan).

## Reference Documents

- `agent.md` — project conventions (line ~78 documents the Claude usage API endpoint).
- `WORK_SUMMARY.md` — line ~82 documents the `/api/oauth/usage` call.
- `README.md` — user-facing behavior; does NOT document polling internals (grep for interval/429/cooldown returned nothing).
- `/Users/jkl/.claude/CLAUDE.md` — global conventions: Korean to user / English artifacts; CI-equivalent checks must pass locally; never push to a protected default branch (branch + PR).
- `~/.claude/projects/-Users-jkl-Projects-Token-tracker/memory/local-verification.md` — how to run macOS + Windows tests locally; UPDATED this session to note CI now gates PRs.

## The Goal

Token Tracker is a macOS menu-bar (Swift) + Windows system-tray (C#/WinForms) app showing Claude and Codex remaining usage. It repeatedly hit `HTTP 429 from Claude API` because it polls Anthropic's per-account, non-public `/api/oauth/usage` endpoint whose budget is shared with Claude Code and any other client on the same OAuth token. The multi-session objective is to minimize the app's own contribution to that rate limit without removing the feature. Parent shipped the two biggest levers (slower polling + persisted cooldown). This session finished the remaining mitigations (single-instance guard, exponential backoff+jitter, legacy-interval migration), made the backoff level survive restarts, and — the durable infrastructure win — added a real CI gate so future changes (especially the WinForms port that can't compile on the dev Mac) are validated automatically on every PR.

## Where We Are

- Repo `/Users/jkl/Projects/Token tracker`, branch **`main`** at `e072d10` (HEAD), working tree **clean**. Everything committed and merged.
- **Two PRs merged this session**, both rebase-merged (linear history) then branch-deleted:
  - **PR #2** `Reduce Claude 429 pressure…` → base commit `0330975`, hardening commit `daf8b2c`. Branch `claude-429-poll-cooldown` deleted (local + remote).
  - **PR #3** `Add CI gate, persist backoff level, verify single-instance guard` → `e072d10`. Branch `claude-429-ci-and-persistence` deleted (local + remote).
- **#4 Exponential backoff + jitter** (macOS + Windows): new pure `RateLimitBackoff` (`RateLimitBackoff.swift` / `RateLimitBackoff.cs`). `cooldown(retryAfter, failureCount, jitter)` = `max(base, min(1800, base·2^failureCount)) + base·jitter`, `base = max(120, retryAfter)`, jitter clamped `0…0.2`. Wired into both `ClaudeRateLimitState` implementations with a `failureCount` field (increment on `backOff`, reset to 0 on `clear`/success). First-failure behavior preserved (headerless 429 still ≈300s via `defaultRateLimitCooldown`).
- **#3 macOS single-instance guard**: new pure `InstanceArbiter.shouldYield(current:others:)` (`InstanceArbiter.swift`) + `AppDelegate.terminateIfDuplicateInstance()` using `NSRunningApplication`. A duplicate launch calls `NSApp.terminate` before setting up the status item / timer. **Windows already had a named-Mutex guard** in `Program.cs` — no change needed there.
- **#5 Legacy interval migration**: macOS `Settings.migrateLegacyRefreshInterval()` (one-time write) raises a stored `refreshInterval` in `(0, 60)` to 60; Windows `SettingsStore.Load()` clamps `RefreshIntervalSeconds < 60` to 60 on load. Fixes the "prefs popup shows no selection for a stale 30s" cosmetic issue and bounds the effective rate.
- **failureCount persistence**: `ClaudeRateLimitStore` record gained `failureCount` on both platforms (macOS `State` struct; Windows `ClaudeRateLimitSnapshot` record struct). Seeded on first load, saved on backoff. **Backward compatible** — a legacy retry-only record loads with `failureCount = 0` (Swift `Int?` + `?? 0`; C# STJ missing → default 0).
- **CI gate**: `.github/workflows/ci.yml` on `pull_request` + `push:main`. macOS job (`macos-latest`): `swift build` + `swift run TokenTrackerSmokeTests`. Windows job (`windows-latest`): `dotnet run` the Core tests + `dotnet build` the WinForms app. The two release workflows (`release.yml`, `windows-release.yml`) remain tag/`workflow_dispatch`-only — CI is the new PR gate.
- **All verification green** (local + CI): macOS `swift build` complete; `TokenTrackerSmokeTests passed`; `TokenTracker.Windows.Tests passed` (via reused scratchpad dotnet 10.0.301); guard demo original PID survived; **PR #3 CI passed** (macOS 20s, Windows 1m7s — the first-ever automated WinForms compile).
- No WinForms-only (`net10.0-windows`) source was edited this session — all Windows changes are in the cross-platform Core (`net10.0`), so everything was locally testable; the CI WinForms build is the belt-and-braces check.
- PR #2 merged 2026-07-05T23:26Z; PR #3 merged 2026-07-06T02:52Z. Both `MERGEABLE`/`CLEAN` at merge; PR #3 additionally had passing CI (PR #2 predated `ci.yml`, so it merged on local verification only).
- `AppDelegate.runningInstanceCount()` (bundle-id count) is unchanged and still feeds the diagnostics menu row; the new guard uses the same bundle id (`local.token-tracker.menubar`) but a pid-filtered comparison via `InstanceArbiter`.
- The Claude fetch path is unchanged except for backoff wiring: `fetch()` returns early on active cooldown, `backOff(for: retryAfter)` on Retry-After present, `backOff(for: defaultRateLimitCooldown=300)` on a headerless 429; both now route through `RateLimitBackoff`.
- Remaining remote branch `origin/claude/code-security-audit-iOaYj` is unrelated to this chain (a separate security-audit stream); left untouched.
- `swift build` after all changes rebuilds and links `TokenTrackerMenuBar` (the app target, which depends on the edited Core) cleanly — confirming the `AppDelegate` guard + Core store changes compile together, not just the smoke target.

## What We Tried (Chronological)

1. Onboarded from parent seq 3 (paste prompt: "continue from Where We're Going"). Confirmed PR #2 OPEN/MERGEABLE, no CI checks (`statusCheckRollup: []`).
2. Ran baselines: `swift build` (exit 0), `swift run TokenTrackerSmokeTests` (passed). Found the prior session's dotnet 10.0.301 still present in its scratchpad; `curl|bash` re-bootstrap was **blocked by the sandbox classifier** ("code from external"). Reused the existing install → `TokenTracker.Windows.Tests passed`.
3. Read `AppDelegate.swift`, `windows/.../UsageClient.cs`, both CI workflows, `Program.cs`. **Discovered the Windows single-instance Mutex already exists** and **neither CI workflow triggers on PR/push** (both tag/dispatch-only).
4. Reported onboarding + the CI-trigger gap; offered (a) verify+merge PR #2 vs (b) add deferred #3/#4/#5 then merge. User: **"b 진행"**.
5. **#5** first (smallest): `Settings.migrateLegacyRefreshInterval()` + `SettingsStore.Load` clamp + tests. `object(forKey:)`-returns-registered-300 concern turned out fine (registration domain doesn't false-trigger `< 60`). macOS smoke passed.
6. **#4**: wrote `RateLimitBackoff` (Swift + C#), added `failureCount` to both `ClaudeRateLimitState`, removed macOS `minimumRateLimitCooldown` constant, added escalation/cap/jitter/honor-longer-Retry-After tests (jitter=0 → exact values; jitter=ceiling → range). Both suites passed.
7. **#3**: wrote `InstanceArbiter` (strict total order: oldest launch wins, PID tie-break, nil-date sorts oldest) + `terminateIfDuplicateInstance()` in `AppDelegate` + 5 smoke assertions. Dropped `NSRunningApplication.activate()` (deprecation/API-availability risk; a menu-bar accessory app has nothing to activate). `swift build` (full, incl. app target) + smoke passed.
8. Verified all green; committed `cd0559f`; pushed; updated PR #2 body; **merged PR #2 (rebase)** after the classifier first blocked a bare merge and the user said **"머지해"**. Synced local `main`. User: **"삭제해"** → deleted branch `claude-429-poll-cooldown` (local + remote).
9. User: **"남은 작업 있으면 알려줘"**. Reported: (1) CI gap [worth doing], (2) guard end-to-end demo [optional], (3) persist failureCount [optional], (4) real-world 429 observation [not code].
10. User: **"ci 추가해. 2,3번 진행해"** (items 1+2+3).
11. Kicked off a background release `.app` build (`scripts/build_app.sh`, host arch). Wrote `ci.yml`.
12. **failureCount persistence**: reworked `ClaudeRateLimitStore` (macOS `State` struct / Windows `ClaudeRateLimitSnapshot`), backward-compatible decode, seeded/saved in both states, updated smoke round-trip + legacy-record test + a Windows black-box assertion (`"FailureCount":1` in the state file after one 429). Both suites passed.
13. **Guard demo**: `.build/Token Tracker.app` (bundle id `local.token-tracker.menubar`, LSUIElement). `pkill` clean slate → `open -n` #1 (count=1, pid 71791) → `open -n` #2 → count stayed 1, survivor = 71791 (the original). `pkill` cleanup → 0 strays. **Proved the NSRunningApplication wiring**, not just the pure arbiter.
14. Full `swift build` (incl. menu-bar app target) green. Branched `claude-429-ci-and-persistence` (never commit to `main`), committed `235a5ee`, pushed, opened **PR #3**.
15. Watched CI on PR #3 → **both jobs pass** (macOS 20s, Windows 1m7s). First automated WinForms `dotnet build` succeeded.
16. User: **"머지해"** → merged PR #3 (rebase, delete-branch) → `main` `e072d10`. Synced local `main`, pruned. Updated `local-verification.md` memory (CI now gates PRs).

## Key Decisions

- **Backoff escalates a preserved base, not a reset one.** `base = max(120, retryAfter)`; caller still passes 300 for headerless 429 → first-failure cooldown ≈300s unchanged. Escalation is `base·2^failureCount` capped at 1800, but `max(base, …)` ensures a longer explicit `Retry-After` (e.g. 3600) is never clipped below the server's instruction. Jitter is **additive only** (`+ base·jitter`), so it never dips below the honored wait.
- **Jitter kept out of the deterministic core.** `RateLimitBackoff.cooldown` takes `jitter` as a parameter; the actor/state supplies `Double.random(0…0.2)` / `Random.Shared.NextDouble()·0.2`. Tests call the pure function with `jitter=0` (exact asserts) and `jitter=ceiling` (range assert). Keeps escalation unit-testable on both platforms without an HTTP mock.
- **Single-instance guard is a strict total order.** Oldest `launchDate` wins; ties (identical dates or missing dates) break on lower PID; a dateless instance sorts as oldest. Guarantees exactly one survivor even on simultaneous launch — no race where both terminate.
- **failureCount NOT reset on natural cooldown expiry** (only on a successful fetch via `clear`). So repeated 429s across successive cooldowns keep escalating within a session. It IS dropped on a restart that happens *after* expiry (the store is cleared on expiry), which is acceptable — a fully-elapsed cooldown resets the ladder.
- **CI Windows job runs on `windows-latest`, not ubuntu.** The Core tests are `net10.0` (would run on ubuntu), but compiling the WinForms app needs `net10.0-windows` → windows-latest. One job does both (`dotnet run` tests + `dotnet build` WinForms) to close the compile gap in a single runner.
- **CI triggers `pull_request` + `push:main`** (not `push: ["**"]`) to avoid double runs on feature branches; PRs are validated via the `pull_request` event using the head-branch workflow file (so PR #3 was gated by its own new `ci.yml`).
- **Reused the prior session's dotnet** rather than re-bootstrapping — the `curl … | bash` install is blocked by the sandbox classifier. Documented in the memory that a future session must reuse the scratchpad install or have the user run the bootstrap.
- **Respected the merge/curl guardrails, did not work around them.** The auto-mode classifier blocked a bare `gh pr merge` until explicit user approval and blocked `curl|bash`; both were surfaced to the user, not bypassed.
- **Rebase-merge both PRs** to keep the repo's linear history; deleted merged branches on user request.
- **No README/doc change** — README documents no polling internals (grep confirmed), so the new behaviors need no user-facing doc edit.

## Evidence & Data

Commits landed on `main` (both PRs rebase-merged):

| Commit | Origin | Summary |
|---|---|---|
| `daf8b2c` | PR #2 branch `cd0559f` | Harden 429: backoff+jitter, macOS single-instance guard, interval migration |
| `0330975` | PR #2 base | Reduce 429 pressure: longer poll interval + persisted cooldown (parent seq 3's work) |
| `e072d10` | PR #3 branch `235a5ee` | Add CI gate, persist backoff level, verify single-instance guard |

PR #2 hardening diff (commit `cd0559f`): 7 files changed, +105/−7, plus 3 new files.
PR #3 diff (commit `235a5ee`): 6 files changed, +110/−21 (incl. new `ci.yml`).

`RateLimitBackoff.cooldown` truth table (jitter=0), verified by tests on both platforms:

| retryAfter | failureCount | result (s) | rationale |
|---|---|---|---|
| 300 | 0 | 300 | headerless-429 default, unchanged |
| 0 | 0 | 120 | absent Retry-After → 120s floor |
| 300 | 2 | 1200 | 300·2² escalation |
| 300 | 5 | 1800 | capped at 30m |
| 3600 | 0 | 3600 | explicit longer Retry-After honored above cap |
| 300 | 0 | (300, 360] | with jitter = 0.2 ceiling → +≤20% |

Single-instance guard demo (real `.app`, `open -n` ×2):

```
after launch #1: count=1  pid=71791
after launch #2: count=1  survivors=[71791]
original instance (71791) survived: YES
cleanup: killed remaining instances   (stray instances: 0)
```

Verification matrix:

| Check | Command | Result |
|---|---|---|
| macOS build | `swift build` | Build complete |
| macOS smoke | `swift run TokenTrackerSmokeTests` | `TokenTrackerSmokeTests passed` |
| Windows Core+Tests | `<scratchpad>/dotnet/dotnet run --project windows/TokenTracker.Windows.Tests/…csproj` | `TokenTracker.Windows.Tests passed` |
| Guard demo | `open -n ".build/Token Tracker.app"` ×2 + `pgrep` | original survived, count=1 |
| CI PR #3 macOS | GitHub Actions | pass (20s) |
| CI PR #3 Windows | GitHub Actions (incl. WinForms `dotnet build`) | pass (1m7s) |

CI run: https://github.com/ChunSam/token-tracker/actions/runs/28763918238

Persistence record shape (both platforms, example):
```json
{"retryAllowedAt":"2026-07-06T02:52:00Z","failureCount":1}
```
macOS: `~/Library/Application Support/Token Tracker/claude-rate-limit.json` (0600). Windows: `%AppData%/Token Tracker/claude-rate-limit.json`.

dotnet (reused, not re-bootstrapped): `/private/tmp/claude-501/-Users-jkl-Projects-Token-tracker/fc637fd9-00b5-4ca7-a40b-498dfdb2e3e0/scratchpad/dotnet/dotnet` → `10.0.301`.

Mitigation status across the whole `claude-usage-stability` chain (parent's four options + this session's additions):

| # | Mitigation | Effect | Landed |
|---|---|---|---|
| 1 | Raise default/min polling interval | Fewer requests/hour — biggest lever | parent seq 3 (`0330975`) |
| 2 | Persist 429 cooldown to disk | Relaunch during cooldown no longer re-fires | parent seq 3 (`0330975`) |
| 3 | Single-instance guard | Stop a duplicate instance doubling the rate | **this session** — Windows pre-existing (Mutex), macOS added (`daf8b2c`) |
| 4 | Exponential backoff + jitter | Smoother recovery, de-synced clients | **this session** (`daf8b2c`) |
| 5 | Legacy interval migration | Stale <60s value clamped to floor | **this session** (`daf8b2c`) |
| 6 | Persist backoff level | Escalation survives restart | **this session** (`e072d10`) |
| 7 | CI gate (PR/push) | Auto-compile+test incl. WinForms | **this session** (`e072d10`) |

Polling knobs (parent seq 3, still in effect — unchanged this session), both platforms:

| Knob | Before parent | Now |
|---|---|---|
| Default interval | 60s | 300s (5m) |
| Timer floor (effective min) | 15s | 60s |
| Selectable options | 30s / 1m / 5m | 1m / 5m / 15m |
| "Short interval" warning fires when | < 60s | < 300s |

CI trigger comparison (why the gap existed and is now closed):

| Workflow | Trigger | Compiles WinForms? |
|---|---|---|
| `release.yml` | `push: tags v*`, `workflow_dispatch` | only on release/tag |
| `windows-release.yml` | `workflow_dispatch` only | only on manual dispatch |
| `ci.yml` (**new**) | `pull_request`, `push: main` | **every PR + main push** |

## Code Analysis

- `RateLimitBackoff.cooldown(retryAfter, failureCount, jitter)` — `base = max(minimum(120), retryAfter)`; `exponent = clamp(failureCount, 0, 20)`; `escalated = max(base, min(maximum(1800), base·2^exponent))`; returns `escalated + escalated·clamp(jitter, 0, 0.2)`. Pure, `public`/`public static` on both platforms so tests reach it directly. Windows uses `TimeSpan · double` (valid operator; exact for powers of two → `.TotalSeconds` exact for the asserts).
- `ClaudeRateLimitState` (macOS actor / Windows locked class): `loadIfNeeded`/`EnsureLoaded` seed `retryAllowedAt` AND `failureCount` from the store once; `backOff` computes cooldown from current `failureCount`, then `failureCount += 1`, then persists the incremented count with the new retry instant; `currentError` clears the store on expiry but leaves `failureCount`; `clear` resets `failureCount = 0` + wipes store. Because `fetch()`/`FetchClaudeAsync` return early while a cooldown is active, `backOff` fires at most once per cooldown cycle (Windows test still asserts `CallCount == 1` on repeat within one process).
- `ClaudeRateLimitStore` (macOS `struct`, `public`): `load() -> State?` returns future-only (`retryAllowedAt.timeIntervalSinceNow > 0`), `failureCount = max(0, record.failureCount ?? 0)`. `save(_ state:)` creates dir 0700, atomic-writes, re-applies 0600. Windows `internal sealed class`: `Load() -> ClaudeRateLimitSnapshot?`, `Save(DateTimeOffset, int)`, positional `record Record(DateTimeOffset RetryAllowedAt, int FailureCount = 0)` — STJ tolerates a missing `FailureCount` → 0 (backward compat).
- `InstanceArbiter.shouldYield(current:others:)` — `others.contains { ownsSlot($0, over: current) }`; `ownsSlot` compares `(launchDate, pid)` as a total order. `AppDelegate.terminateIfDuplicateInstance()` maps `NSRunningApplication.runningApplications(withBundleIdentifier:)` (excluding self by pid) into `InstanceArbiter.Instance` and calls `NSApp.terminate(nil)` + returns true when yielding; `applicationDidFinishLaunching` early-returns on true (before `setActivationPolicy`/menu/timer).
- `Settings.migrateLegacyRefreshInterval()` — guards on `defaults.object(forKey:) as? Double` in `(0, 60)` → writes 60. Called in `init` after `registerDefaults()`. Registered default (300) does not false-trigger because `300 < 60` is false.
- `scripts/build_app.sh` — builds `.build/Token Tracker.app` for `$APP_ARCHS` (default host arch), embeds `Info.plist` with `CFBundleIdentifier local.token-tracker.menubar`, `LSUIElement true`. This bundle id is exactly `AppDelegate`'s fallback, so the guard's `NSRunningApplication` lookup matches.
- CI `ci.yml`: `concurrency` cancels in-progress runs per ref; Windows job sets `FORCE_JAVASCRIPT_ACTIONS_TO_NODE24: true` (mirrors `windows-release.yml`); `setup-dotnet@v4` with `10.0.x`. macOS job needs no `setup-xcode` — `macos-latest`'s default toolchain builds the `swift-tools-version: 6.0` / `.macOS(.v13)` package.
- Guard demo mechanics: the two-instance choreography used short `sleep` between `open -n` calls to let each instance register with `NSRunningApplication` / run its guard; that ran fine here (foreground `sleep` was not blocked in this context). The proof is not just "count stayed 1" but "the surviving PID equals the FIRST instance's PID (71791)" — showing the guard killed the *newer* instance, matching `InstanceArbiter`'s oldest-wins rule.
- Smoke-test seams: the interval-migration test uses a throwaway `UserDefaults(suiteName:)` (set 30 → `Settings(defaults:)` → assert 60; set 300 → assert 300), cleaned up with `removeSuite`. The backward-compat test hand-writes `{"retryAllowedAt":"<iso>"}` (no `failureCount`) to the store URL and asserts `load()?.failureCount == 0`. These are the only unit-testable seams for their features on macOS (no HTTP mock harness exists).
- Windows testability: `ClaudeRateLimitStore`/`ClaudeRateLimitSnapshot` are `internal`, so the failureCount-persistence test is black-box — it reads the state file written via the public `UsageClient` and asserts the JSON contains `"FailureCount":1` after one 429. `RateLimitBackoff` is `public`, so its truth table is tested directly.

Additional context in "Where We Are": the app still serves stale cache with the 429 error string during a cooldown (parent behavior, unchanged); `applicationDidFinishLaunching` order is now `terminateIfDuplicateInstance()` → (if surviving) `setActivationPolicy` → `configureMenu` → `refreshNow` → `scheduleTimer`, so a yielding duplicate never creates a status item or fires a request.

## Files Changed

### Source — macOS (Core)
- `Sources/TokenTrackerCore/RateLimitBackoff.swift` — **new**; pure exponential-backoff+jitter cooldown.
- `Sources/TokenTrackerCore/InstanceArbiter.swift` — **new**; pure single-instance ownership decision.
- `Sources/TokenTrackerCore/ClaudeRateLimitStore.swift` — `State` struct; persist/load `failureCount`; backward-compatible `Record`.
- `Sources/TokenTrackerCore/ClaudeUsageClient.swift` — `failureCount` field; `RateLimitBackoff` wiring; removed `minimumRateLimitCooldown`; seed/save failureCount.
- `Sources/TokenTrackerCore/Settings.swift` — `migrateLegacyRefreshInterval()`.

### Source — macOS (app)
- `Sources/TokenTrackerMenuBar/AppDelegate.swift` — `terminateIfDuplicateInstance()`; early return in `applicationDidFinishLaunching`.

### Source — Windows (Core, net10.0)
- `windows/TokenTracker.Windows.Core/RateLimitBackoff.cs` — **new**; C# mirror of the backoff.
- `windows/TokenTracker.Windows.Core/UsageClient.cs` — `ClaudeRateLimitState.failureCount`; `RateLimitBackoff.Cooldown` wiring; store `ClaudeRateLimitSnapshot`/`Save(…, int)`; new `internal readonly record struct ClaudeRateLimitSnapshot`.
- `windows/TokenTracker.Windows.Core/SettingsStore.cs` — `Load()` clamps `RefreshIntervalSeconds < 60` → 60.

### Tests
- `Sources/TokenTrackerSmokeTests/main.swift` — `RateLimitBackoff` truth table; `InstanceArbiter` tie-break (5 cases); interval-migration via temp `UserDefaults` suite; store round-trip with `failureCount` + legacy-record backward-compat.
- `windows/TokenTracker.Windows.Tests/Program.cs` — `RateLimitBackoff.Cooldown` truth table; legacy interval migration; `"FailureCount":1` persisted-file assertion in the 429 test.

### CI / tooling
- `.github/workflows/ci.yml` — **new**; PR/push gate (macOS swift + Windows dotnet incl. WinForms build).
- `~/.claude/projects/-Users-jkl-Projects-Token-tracker/memory/local-verification.md` — updated: CI now compiles WinForms on PRs.

## User Feedback & Preferences (REQUIRED — never omit)

- **`/remote-control` then `b 진행`** — session is in remote-control mode; chose option (b): implement deferred #3/#4/#5 then merge, over merely verifying PR #2. Expects autonomous multi-step execution + step reporting.
- **`머지해`** (twice) — explicitly approved merging PR #2, then PR #3. The bare `gh pr merge` was blocked by the auto-mode classifier until this explicit approval; the guardrail was respected, not worked around.
- **`삭제해`** — delete the merged feature branch (local + remote) after merge.
- **`ci 추가해. 2,3번 진행해`** — add CI, plus items #2 (guard end-to-end demo) and #3 (persist failureCount) from the "남은 작업" list. (Item #4, real-world 429 observation, deliberately not requested — it's not a code task.)
- **`남은 작업 있으면 알려줘` / `업데이트된 handoff 작성해줘`** — wants a proactive remaining-work scan, and a full handoff at the end.
- Inherited standing preferences (still honored): keep the feature (don't disable Claude polling); keep stale cache visible; **macOS/Windows parity is mandatory**; Korean-facing replies with English code/artifacts; CI-equivalent checks must pass locally; **never push to protected `main` — branch + PR**.
- Works decisively in short Korean commands; prefers action over re-confirmation once a direction is chosen.

## Where We're Going

The chain's core 429 mitigation is essentially complete. Remaining items are observational or nice-to-have:

1. **Observe real-world 429** — confirm 429 actually decreased in daily use (not a code task; user monitors over time).
2. **(Optional) Reset `failureCount` policy** — decide whether the escalation ladder should also persist across a restart-after-expiry (currently dropped), or reset sooner. Low value; current behavior is intentional.
3. **(Optional) macOS release signing/notarization** — `scripts/build_app.sh` builds an unsigned `.app`; the DMG is unsigned. Unrelated to 429 but a real gap for distribution.
4. **(Optional) Windows single-instance UX** — the Mutex guard silently exits the duplicate; could surface/activate the existing instance. Parity with macOS (which also silently terminates) is already fine.
5. **(Optional) Broaden CI** — add lint/format or a `swift test`-style target if the project grows real unit tests beyond the smoke executable. Consider gating `main` with a branch-protection rule now that a CI check exists (the repo currently has none, which is why the classifier — not GitHub — was the only guard against an unreviewed merge).
6. **(Optional) Backfill CI validation of the release path** — `ci.yml` runs `dotnet build`, not `dotnet publish -r <rid> --self-contained /p:PublishSingleFile=true`; a publish quirk could still surface only at release. Low risk, but a `publish` smoke could pre-empt it.

## Risks & Blockers

- **dotnet is not installed system-wide** and `curl … | bash` bootstrap is **blocked by the sandbox classifier**. Windows local testing depends on the reused scratchpad install (`fc637fd9-…/scratchpad/dotnet`, 10.0.301), which is session-scoped and may be garbage-collected. A future session must either find a surviving install or ask the user to run the bootstrap in a `!` command. CI now covers Windows regardless, reducing reliance on local dotnet.
- **429 is fundamentally server-side / per-account-shared.** These mitigations lower the app's own contribution but cannot prevent 429 if Claude Code (or another client on the same token) independently hammers `/api/oauth/usage`.
- **Backoff/jitter use `Double.random`/`Random.Shared`** — nondeterministic in the running app (fine); tests avoid flakiness by exercising the pure function with injected jitter.
- **The guard demo ran on the dev Mac's GUI session.** In a headless/SSH context `open -n` may not launch a menu-bar app, so the runtime guard is not exercisable in CI — CI only compiles it. The demo is the runtime evidence.
- **No `main` branch protection.** GitHub does not require the new CI check to pass before merge; the only guard against an unreviewed merge was the harness classifier. If that changes, an un-green PR could be merged.

## Open Questions

- Did real-world 429 actually drop after these changes? (observational; no data yet)
- Should the persisted `failureCount` also survive a restart-after-expiry, or is dropping it on natural expiry the right ceiling? (current: kept across cooldowns within a session, dropped after full expiry)
- Does the macOS guard behave identically when launched via LaunchServices from Finder / a login item (the real-world path) vs the `open -n` used in the demo? Expected equivalent (same bundle id → `NSRunningApplication` tracking), but untested.
- Should the two headerless/floor constants be unified? They currently live apart: `ClaudeUsageClient.defaultRateLimitCooldown` (300, the headerless arg) and `RateLimitBackoff.minimumCooldown` (120, the floor). Intentional but easy to confuse.
- Is spending `macos-latest` + `windows-latest` CI minutes on every PR acceptable for this repo's cadence, or should CI be scoped to paths (e.g. only run the Windows job when `windows/**` changes)? Not tuned this session.

## Quick Start for Next Session

```bash
# Restore context
cd "/Users/jkl/Projects/Token tracker" && git status -sb && git log --oneline -5

# Prior chain (read parent first)
sed -n '1,120p' plans/handoffs/HANDOFF_claude-usage-stability_polling-cooldown-persistence_2026-07-05.md
sed -n '1,200p' plans/handoffs/HANDOFF_claude-usage-stability_hardening-and-ci-gate_2026-07-06.md

# Key files to read first (not exhaustive — explore adjacent code too)
sed -n '1,60p'  Sources/TokenTrackerCore/RateLimitBackoff.swift
sed -n '1,60p'  Sources/TokenTrackerCore/InstanceArbiter.swift
sed -n '1,70p'  Sources/TokenTrackerCore/ClaudeRateLimitStore.swift       # State struct + backward-compat
sed -n '185,245p' Sources/TokenTrackerCore/ClaudeUsageClient.swift        # ClaudeRateLimitState actor
sed -n '175,320p' windows/TokenTracker.Windows.Core/UsageClient.cs        # C# state + store + snapshot
sed -n '1,50p'  .github/workflows/ci.yml

# Verify current state — macOS
swift build && swift run TokenTrackerSmokeTests

# Verify current state — Windows (reuse prior dotnet; curl|bash bootstrap is sandbox-blocked)
DN="/private/tmp/claude-501/-Users-jkl-Projects-Token-tracker/fc637fd9-00b5-4ca7-a40b-498dfdb2e3e0/scratchpad/dotnet/dotnet"
"$DN" run --project windows/TokenTracker.Windows.Tests/TokenTracker.Windows.Tests.csproj

# (Optional) re-demo the macOS single-instance guard
bash scripts/build_app.sh && open -n ".build/Token Tracker.app"   # launch twice; pgrep -x TokenTrackerMenuBar stays at 1

# Next action
# Core 429 work is COMPLETE and merged. No pressing code task. If the user reports 429 recurring,
# investigate whether another client on the account is the source; otherwise pick an optional item
# (signing/notarization, failureCount-persistence policy) only on request.
```

## Session Closed

**Closed at:** 2026-07-06 12:01 KST
**Branch:** `main` (both feature branches merged + deleted; this handoff committed on `main`)
**Commits:** `daf8b2c` (PR #2), `e072d10` (PR #3) on `main`; close commit adds this handoff (see `git log`)
**Session status:** Handed off to next session
