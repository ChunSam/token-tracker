# Usage-insight features (7d trend, depletion forecast + predictive alert, pause polling, history sparkline) + v1.1 release

**Date:** 2026-07-06
**Status:** COMPLETED (all merged to `main`; v1.1 release upload is the one remaining action, in progress)
**Bead(s):** none (bd unavailable in this environment)
**Epic:** Token Tracker usage UX
**Chain:** `usage-insights` seq `1`
**Parent:** `none — first in chain`
**Prior chain:** none — first in chain

## Related Handoffs

Same repo, other work streams (reference only, NOT chain parents):
- `HANDOFF_claude-usage-stability_hardening-and-ci-gate_2026-07-06.md` — the 429-hardening chain (seq 4). This session **finished its "Where We're Going" optional items**: merged its handoff PR (#4), added the CI publish smoke (#5), and added `main` branch protection. The core 429 work was already complete.
- `HANDOFF_macos-usage-ux_diagnostics-alerts-history_2026-06-15.md` / `HANDOFF_macos-usage-ux_windows-parity_2026-06-22.md` — earlier usage-UX features (menu diagnostics, alerts, history store, CSV, Windows parity). This session's forecast/sparkline/pause build directly on that history store + alert evaluator, so those are the closest architectural predecessors.

## Reference Documents

- `plans/FEATURE_PLAN_usage-insights-and-controls_2026-07-06.md` — the implementation plan for all 4 features (written this session, committed in PR #6). Documents the Core design, per-platform anchors, sequencing, and open questions. **Read this first** if continuing feature work. It also carries the deferred Option-B (bitmap sparkline) design and the parity file-map table.
- `agent.md` — project conventions (Claude usage API endpoint ~line 78).
- `/Users/jkl/.claude/CLAUDE.md` — global conventions: Korean to user / English artifacts; CI-equivalent checks must pass locally; never push to protected `main` (branch + PR); always pass explicit `model` to subagents.
- `~/.claude/projects/-Users-jkl-Projects-Token-tracker/memory/local-verification.md` — how to run macOS + Windows tests locally; notes CI gates PRs, the publish smoke, and `main` branch protection.

## The Goal

Token Tracker is a macOS menu-bar (Swift) + Windows system-tray (C#/WinForms) app showing Claude and Codex remaining usage (5h + 7d windows, reset times, plan). The 429-reliability chain was complete; this session added **user-facing insight features that squeeze more value out of the already-collected local history without adding any API load** (the app polls a shared per-account rate limit, so new network calls are off the table). Four features shipped — 7d trend, depletion forecast + predictive alert, pause/snooze polling, and a history sparkline — plus a version bump to 1.1, two runtime bug fixes surfaced during manual testing, and (in progress) a v1.1 GitHub release. macOS/Windows parity is mandatory throughout.

## Where We Are

- Repo `/Users/jkl/Projects/Token tracker`, branch **`main`** @ `0bab083` (HEAD), working tree **clean**. Everything committed and merged.
- **8 PRs merged this session** (all rebase-merged for linear history, branches deleted): #4 (prior session's handoff doc), #5 (publish smoke), #6 (7d trend), #7 (forecast), #8 (pause), #9 (sparkline), #10 (version 1.1), #11 (fixes). No open PRs.
- **`main` is branch-protected** (GitHub setting, set via `gh api` — user ran the PUT via a `!` command because the auto-mode classifier blocked the agent from doing it): both CI checks (`macOS build + smoke tests`, `Windows build + tests`) required + strict, PR required (0 approvals), `enforce_admins=true`. So even self-authored PRs merge only on green CI. Relax admin enforcement in an emergency: `gh api -X DELETE repos/ChunSam/token-tracker/branches/main/protection/enforce_admins`.
- **Feature 4 — 7d trend** (`04f6e36`): `UsageHistoryFormatter.providerTrend` now emits the 7d delta beside 5h via a shared `deltaText`/`DeltaText` helper (`--` when either endpoint nil), e.g. `24h trend: Claude 5h +23% 7d +10% Codex 5h +1% 7d 0%`.
- **Feature 1 — depletion forecast + predictive alert** (`3bf7ffd`): new pure `UsageForecaster.forecast(entries, provider, window, resetAt, now)` → `UsageForecast?` (burnPerHour, secondsToEmpty, emptyAt, willEmptyBeforeReset). Menu shows `Projected depletion: ~2h 10m (· empties before reset)` per provider (5h window), gated by new `showForecast` setting (default **on**). New `UsageForecastAlert.candidates(inputs, enabled, localizer)` emits a "may run out before reset" notification, gated by notifications + new `depletionAlertEnabled` setting (default **off**), merged into the existing dedupe/dispatch path.
- **Feature 3 — pause/snooze polling** (`9ebc48a`): new pure `PauseController` (isPaused / remaining / isIndefinite). Menu "Pause updates" submenu (1h / 3h / until resumed); when paused shows "Updates paused: <countdown | until I resume>" + "Resume now". Refresh loop early-returns while paused (no fetch). Persisted via new `pollPausedUntil` setting. **Windows `SettingsStore.Save` made atomic** (temp+move) since it now persists pause state.
- **Feature 2 — history sparkline** (`6634f92`): new pure `SparklineSeries.build` (downsample stored history to ≤20 points) + `SparklineText.render` (0–100 → `▁▂▃▄▅▆▇█`, absolute scale). History submenu shows `Claude 5h █▇▅▄▃` per provider. No setting, no drawing code, no localization key (label is `{name} 5h`). Chose **Option A (unicode)** over Option B (bitmap) per user endorsement.
- **Version 1.1** (`26e5959`): `scripts/build_app.sh` defaults bumped `APP_VERSION` 1.0→**1.1**, `APP_BUILD` 1→**2** (was indistinguishable before — the actual confusion that triggered this). Release builds still override both from tag/run-number.
- **Two bug fixes** (`0bab083`, found during manual testing):
  1. **Preferences didn't re-localize on language change** — only the menu rebuilt, not the window. Now `PreferencesWindowController.buildContent` clears + re-applies localized checkbox titles and is re-run on language change (deferred via `DispatchQueue.main.async`); Windows `SettingsForm` gets a `RebuildContent()` (deferred via `BeginInvoke`).
  2. **Pause not retained across macOS restart** — `applicationDidFinishLaunching` called `refreshNow()`, which lifts a pause. Now it calls `startRefresh(showLoadingIndicator:)` directly, so a persisted `pollPausedUntil` is honored on launch. Windows already used `RefreshAsync` on launch (which doesn't clear) → was unaffected.
- **Installed app updated**: `/Applications/Token Tracker.app` replaced with a **universal (arm64+x86_64) 1.1 (2)** build including both fixes; running (verified stable, single instance). Old `/Applications` copy was Jun-6 (pre-session).
- **DMG regenerated**: `dist/TokenTracker-v1.1-macOS.dmg` (4.4M, universal) + `.sha256`, includes both fixes. `dist/` is git-ignored.
- All 4 features honor the invariants: **no new API calls** (1/2/4 read stored history; 3 reduces calls), **macOS⇄Windows parity**, **pure Core unit-tested on both platforms**, **en/ko localization synced across all 4 dictionaries**.
- **CI publish smoke** (`ci.yml`, PR #5): the Windows job now also runs `dotnet publish -r win-x64 --self-contained true /p:PublishSingleFile=true /p:PublishReadyToRun=false` so a publish-only quirk is caught on every PR, not just at release. win-x64 only (arm64 stays release-only) — noted, not silently dropped.
- **Feature ideation used subagents**: an `Explore` agent (model `sonnet`) mapped the entire Windows parity surface (TrayAppContext/SettingsForm/SettingsStore/Localizer/UsageHistoryStore/UsageAlertEvaluator/TrayIconRenderer/Models) before any feature code — its findings drove the symmetric per-platform edits. Key divergence it found: Windows `UsageSource` lacks the `LocalLog` case (pre-existing, untouched by these features).
- **Verified state on the running app**: `/Applications/Token Tracker.app` = 1.1 (2), single instance (pgrep count 1), stable after relaunch (pid changed across rebuilds: 24837→30342→32049→44814 as expected).

Additional notes: the app still serves stale cache with the 429 error string during a cooldown (unchanged); the menu-bar status item already color-emphasizes a low/7d-warning state (`sevenDayWarningColor` macOS / `WarningBackground` Windows) — so "color when low" was NOT added (already existed).

## What We Tried (Chronological)

1. **Onboarded**: ran the app, read the `hardening-and-ci-gate` handoff (429 chain seq 4, COMPLETED). Confirmed core 429 work merged; its only OPEN item was PR #4 (handoff doc). macOS `swift build`+smoke green; reused prior session's scratchpad dotnet 10.0.301 for Windows tests (curl|bash bootstrap is sandbox-blocked).
2. **Closed the 429 chain tail**: merged PR #4 (handoff doc) on approval; then user asked for remaining work → added the **CI publish smoke** (PR #5: `dotnet publish -r win-x64 --self-contained /p:PublishSingleFile=true` mirroring the release path) and **`main` branch protection** (agent `gh api` PUT was classifier-blocked; user ran it via `!`).
3. **Feature ideation**: surveyed the codebase (Models, UsageService, StatusMenuBuilder, Settings, history/alerts, Codex client) + an Explore agent mapped the Windows parity surface. Recommended 4 features; user asked for a plan doc → wrote `FEATURE_PLAN_usage-insights-and-controls_2026-07-06.md`; user said "추천 순서로 진행" (proceed in recommended order).
4. **PR A — Feature 4 (7d trend)**: extended `providerTrend` (both platforms) + shared `deltaText`. Updated the trend tests + a new nil-7d `--` assertion. macOS build+smoke + Windows Core tests green → PR #6 → CI green → merged.
5. **PR B — Feature 1 (forecast + alert)**: wrote `UsageForecast.swift`/`.cs` (forecaster + text helper + alert evaluator), wired the menu (`StatusMenuContext.forecastLines`, Windows `AddProvider`), the alert path (`UsageNotificationCoordinator.handleNotifications` gained `extraCandidates`; Windows `HandleNotifications` merges `ForecastCandidates`), 2 settings, prefs UIs, 5 L10n keys ×2 platforms. Unit tests on both. PR #7 → CI green (first WinForms compile of the new menu wiring) → merged.
6. **PR C — Feature 3 (pause)**: `PauseController.swift`/`.cs`, `pollPausedUntil` setting, menu submenu + guard in refresh loop, manual-refresh-lifts-pause, Windows atomic Save, 6 L10n keys. Unit tests on both (incl. persistence round-trip). PR #8 → CI green → merged.
7. **PR D — Feature 2 (sparkline)**: `Sparkline.swift`/`.cs`, History-submenu wiring, no setting. Unit tests on both (block mapping, empty/single → "", downsample). PR #9 → CI green → merged.
7a. **Two plan open-questions resolved** (user endorsed via "추천 순서로 진행"): (1) a manual "Refresh Now" lifts an active pause (explicit fetch intent) — this later turned out to be the exact cause of bug #2 when the launch path reused `refreshNow`; (2) sparkline Option A (unicode) shipped, Option B (bitmap) left as optional follow-up.
7b. **Method per feature**: implement Core on both platforms → add unit tests on both → wire UI → run macOS build+smoke + Windows Core tests locally → branch, push, PR, watch CI (the first WinForms compile of each change) → merge on the standing go-ahead. Windows Core tests use the reused scratchpad dotnet; the WinForms app itself is only ever compiled by CI.
8. **Final verification on main**: macOS build+smoke, Windows Core tests, rebuilt `.app`, relaunched — all green/stable.
9. **User reported installed app was old** → found `/Applications` copy was Jun-6; replaced with fresh build, relaunched. Noted version string was still 1.0 (1).
10. **PR #10 — version 1.1**: bumped `build_app.sh` defaults; built universal 1.1 `.app`; created v1.1 DMG; replaced `/Applications`; relaunched (1.1 (2)). Merged.
11. **`dist/` anomaly**: old local DMGs (v1.0.0–v1.0.6) were gone from `dist/` — could not be explained by any agent command (only the v1.1 file was targeted). Surfaced honestly; confirmed all old DMGs are safe on **GitHub Releases**, so no real loss.
12. **User reported two bugs from the screenshot** (prefs language not switching; pause not surviving restart). Diagnosed both, fixed both (PR #11). **Empirically verified pause persistence** via a `defaults` round-trip (pollPausedUntil survived relaunch). Language fix is code+CI-verified (native popup click not automatable). Rebuilt universal 1.1 `.app` with fixes, regenerated DMG, reinstalled, relaunched. User confirmed ("확인 완료").
13. **This handoff** + (next) merge it + upload the v1.1 release.

## Key Decisions

- **Forecast algorithm is deterministic and conservative.** `base` slope from the **post-reset segment only** (trim everything up to and including the last upward jump — a reset refilling budget must not read as consumption); require a **10-minute minimum span** (`minimumSpan = 600`); return `nil` for a flat/replenishing window (`drop ≤ 0`). Projects `secondsToEmpty = lastRemaining / burnPerHour * 3600` from `now`. Pure function with injected `now` → exact unit-test asserts, no HTTP/clock mock. Chose first/last delta over regression (simple; iterate later if noisy).
- **Predictive alert is a SEPARATE evaluator** (`UsageForecastAlert`), not an overload of the tested `UsageAlertEvaluator` — keeps the existing alert function stable. Caller passes `enabled = notificationsEnabled && depletionAlertEnabled`; id includes the reset unix-seconds so it dedupes per window instance (matches the reset-proximity convention).
- **Sparkline Option A (unicode blocks) over Option B (drawn bitmap).** Fully shared Core, zero platform drawing code, unit-testable, drops into existing text menu rows. **Absolute 0–100 scale** (not min/max normalized) so both the level and the slope read at a glance. No setting (always shown in the History submenu when ≥2 points) to avoid settings/prefs churn.
- **Pause semantics: manual overrides, automatic respects.** A user-initiated "Refresh Now" / "Resume now" lifts the pause (explicit fetch intent); the timer tick and **app launch** respect it. The bug was macOS launch using `refreshNow` (which lifts) — fixed to `startRefresh`. `pollPausedUntil` persisted so a restart mid-pause stays paused (consistent with the 429-cooldown persistence precedent). "Until resumed" = `Date.distantFuture` / `DateTimeOffset.MaxValue`, detected via `isIndefinite` (> 365-day threshold) to show a label instead of a countdown.
- **Cross-feature reuse:** `ForecastWindow` enum and `UsageForecaster.durationText` (from Feature 1) are reused by the sparkline series and the pause countdown label — avoids duplicate window/format logic.
- **Prefs re-localization is deferred, not synchronous.** Rebuilding the window/form from inside the language control's own change event risks mutating/disposing the sender mid-event → `DispatchQueue.main.async` (macOS) / `BeginInvoke` (Windows). macOS reuses the lazy control instances (re-parented into a fresh stack); the accumulating width constraints are identical (`>=160`) and benign.
- **Version bump lives in `build_app.sh` defaults**, not per-file plists — one place, and release builds already override via env. Bumped build number too (2) so Copy-Diagnostics/Finder distinguish it.
- **PR-per-feature**, each gated by branch protection + CI (incl. publish smoke). Self-authored merges were classifier-gated early in the session but allowed once the user gave the standing "추천 순서로 진행" directive.
- **No `dist/` in git** (git-ignored) → the DMG is a local/release-CI artifact, never committed.
- **Menu forecast uses the 5h window only** (not 7d) — 5h is the short-term binding constraint and keeps the provider row compact; the 7d case is still covered by the predictive alert (which considers both windows). Revisit if users want a 7d menu line.
- **Rebase-merge every PR** to preserve `main`'s linear history; delete the branch on merge. Eight PRs this session, all rebase-merged.
- **Bumped the build number (2), not just the marketing string (1.1)** — `DiagnosticsReporter` prints `App version: X (Y)` in Copy-Diagnostics, so a distinct build number is the reliable "is this the new binary?" signal (the marketing string alone caused the confusion that started the version work).

## Evidence & Data

Commits landed on `main` this session (rebase-merged):

| Commit | PR | Summary |
|---|---|---|
| `bd72c6c` | #5 | CI: release-path publish smoke (win-x64 self-contained single-file) |
| `04f6e36` | #6 | History trend: add 7d delta beside 5h (both platforms) |
| `3bf7ffd` | #7 | Depletion forecast + predictive "before reset" alert |
| `9ebc48a` | #8 | Pause/snooze polling (1h / 3h / until resumed) |
| `6634f92` | #9 | Unicode sparkline of 5h remaining in History submenu |
| `26e5959` | #10 | Bump app version to 1.1 (build 2) |
| `0bab083` | #11 | Fix Preferences localization refresh + pause persistence |

(`ae6ac5b` = prior session's handoff doc, merged as PR #4 this session.)

`UsageForecaster.forecast` verified truth table (unit tests, both platforms):

| entries (secondsAgo:5h%) | resetAt | burnPerHour | secondsToEmpty | willEmptyBeforeReset |
|---|---|---|---|---|
| 3600:60, 1800:50, 0:40 | now+3h | 20 | 7200 (2h) | true |
| 3600:60, 1800:50, 0:40 | now+1h | 20 | 7200 | false |
| 3600:30, 1800:80, 900:70, 0:60 (reset mid) | nil | 40 | 5400 (1h30m) | — |
| 3600:40, 0:50 (replenishing) | — | — | — | nil |
| 300:60, 0:50 (span < 10m) | — | — | — | nil |

`durationText`: 7800→"2h 10m", 2700→"45m", 30→"<1m". Sparkline `render([0,25,50,75,100])`→"▁▃▅▇█"; `render([100,50,0])`→"█▅▁"; `render([42])`/`render([])`→"". Alert id: `claude-5h-empty-before-reset-{unixReset}`.

Pause-persistence empirical check (the reported bug):
```
before launch: pollPausedUntil = 1783322670.27 (now+1h)
after  launch: pollPausedUntil = 1783322670.27   ← retained (was cleared to 0 pre-fix)
```

Verification matrix:

| Check | Command | Result |
|---|---|---|
| macOS build+smoke | `swift build` / `swift run TokenTrackerSmokeTests` | `TokenTrackerSmokeTests passed` |
| Windows Core+Tests | `<dotnet> run --project windows/TokenTracker.Windows.Tests/…csproj` | `TokenTracker.Windows.Tests passed` |
| CI (every PR #5–#11) | GitHub Actions (macOS + Windows incl. WinForms compile + publish smoke) | all green |
| Universal build | `lipo -archs` | `x86_64 arm64` |
| Installed app | PlistBuddy on `/Applications/Token Tracker.app` | `1.1 (2)`, running |

Artifacts: `dist/TokenTracker-v1.1-macOS.dmg` (+ `.sha256`); reused dotnet at `/private/tmp/claude-501/-Users-jkl-Projects-Token-tracker/fc637fd9-…/scratchpad/dotnet/dotnet` (10.0.301). GitHub Releases hold v1.0.0–v1.0.6 (macOS DMG + Windows zips + checksums).

CI timings (approx, per PR): macOS job 20–40s; Windows job 55s–1m38s (compile + Core tests + WinForms build + publish smoke). Every PR #5–#11 passed both jobs before merge.

**New localization keys** (each added to macOS `Localization.swift` enum+en+ko AND Windows `Localizer.cs` enum+English+Korean — all four dictionaries):

| Key | English | Korean |
|---|---|---|
| forecastLabel | Projected depletion | 예상 소진 |
| forecastBeforeReset | empties before reset | 리셋 전 소진 |
| depletionAlertTitle | May run out before reset | 리셋 전 소진 예상 |
| showForecastLabel | Show depletion forecast | 소진 예측 표시 |
| depletionAlertToggle | Depletion alert (before reset) | 소진 예측 알림 (리셋 전) |
| pausePolling | Pause updates | 업데이트 일시중지 |
| pause1h | For 1 hour | 1시간 |
| pause3h | For 3 hours | 3시간 |
| pauseUntilResumed | Until I resume | 재개할 때까지 |
| resumeNow | Resume now | 지금 재개 |
| updatesPaused | Updates paused | 업데이트 일시중지됨 |

Note: Windows has **no per-key fallback** — a missing Korean key renders the raw enum name, so both dicts must stay in sync. The sparkline/7d-trend features added **no** keys (labels are `{provider.displayName} 5h` + literal window tags).

**New settings** (defaults): `showForecast=true`, `depletionAlertEnabled=false`, `pollPausedUntil=nil`. macOS registers the two bools in `registerDefaults`; `pollPausedUntil` needs no registration (absent double → 0 → nil). Windows: `AppSettings` initializers (`ShowForecast=true`, `DepletionAlertEnabled=false`, `PollPausedUntil=null`).

**Exact rendered strings** (so the next session can grep/verify): forecast menu line `Projected depletion: ~2h 10m` (+ ` · empties before reset` when applicable, or ko `예상 소진: ~2h 10m · 리셋 전 소진`); pause status row `Updates paused: 42m` or `Updates paused: Until I resume`; sparkline row `Claude 5h █▇▅▄▃`; 7d trend `24h trend: Claude 5h +23% 7d +10% Codex 5h +1% 7d 0%`; alert body `Claude 5h: ~2h 10m → 0% (before reset)`.

**Per-feature unit-test coverage** (both `main.swift` and `Program.cs`, so 2× each):
- 7d trend: `+`/`0`/`--` deltas for both windows; nil-7d renders `--`.
- Forecast: steady-decline ETA (burn 20/h, 7200s); before/after-reset boundary; post-reset segment trimming (burn 40/h, 5400s); replenish → nil; sub-min-span → nil; `durationText` 3 cases.
- Forecast alert: fires only when `willEmptyBeforeReset` + enabled; suppressed when disabled; suppressed when reset comes first; exact id string.
- Pause: isPaused true/false/nil; remaining seconds; remaining 0 when unset; isIndefinite for MaxValue/distantFuture vs a timed pause; `pollPausedUntil` round-trips through the (atomic) settings store.
- Sparkline: 8-block mapping `[0,25,50,75,100]→▁▃▅▇█`; single/empty → `""`; in-order extraction `[100,50,0]`; end-to-end `█▅▁`; downsample 40→20.

**Reproducible commands used this session:**
```bash
# Pause-persistence empirical test (macOS)
defaults write local.token-tracker.menubar pollPausedUntil -float $(python3 -c "import time;print(time.time()+3600)")
open -n ".build/Token Tracker.app"; sleep 4
defaults read local.token-tracker.menubar pollPausedUntil     # retained == fix works
defaults delete local.token-tracker.menubar pollPausedUntil   # cleanup

# Universal build + DMG (mirrors release.yml)
APP_ARCHS="arm64 x86_64" bash scripts/build_app.sh
hdiutil create -volname "Token Tracker" -srcfolder ".build/Token Tracker.app" -ov -fs HFS+ -format UDZO "dist/TokenTracker-v1.1-macOS.dmg"

# Install to /Applications
pkill -x TokenTrackerMenuBar; rm -rf "/Applications/Token Tracker.app"
ditto ".build/Token Tracker.app" "/Applications/Token Tracker.app"; open "/Applications/Token Tracker.app"

# Branch protection (user ran via ! — agent gh-api PUT was classifier-blocked)
gh api -X PUT repos/ChunSam/token-tracker/branches/main/protection --input <protection.json>
#   required_status_checks{strict:true, contexts:["macOS build + smoke tests","Windows build + tests"]},
#   enforce_admins:true, required_pull_request_reviews{required_approving_review_count:0}, restrictions:null
```

## Code Analysis

- `UsageForecaster.forecast` — collects `(recordedAt, remaining)` for the window, sorts, trims to the last post-reset segment (loop finds last `points[i] > points[i-1]`), guards `count≥2 / elapsed≥600 / drop>0`, returns burn+ETA. `durationText(seconds)`: `<1m` / `{m}m` / `{h}h {m}m`. `UsageForecastText.menuLine(forecast, localizer)` → nil when no forecast. `ForecastWindow { fiveHour, sevenDay }` reused by sparkline.
- `UsageForecastAlert.candidates(inputs, enabled, localizer)` — `inputs: [ForecastAlertInput(provider, window, forecast, resetAt)]`; emits only where `willEmptyBeforeReset && resetAt != nil`.
- `PauseController` — `isPaused(until, now)`, `remaining(until, now) -> TimeInterval/TimeSpan`, `isIndefinite(until, now)` (`> indefiniteThreshold` = 365d). Settings: macOS `pollPausedUntil: Date?` stored as epoch Double (0/absent = nil); Windows `PollPausedUntil: DateTimeOffset?`.
- `SparklineSeries.build(entries, provider, window, maxPoints=20)` — sorts, extracts non-nil remaining, averages into ≤20 buckets. `SparklineText.render(series)` — `< 2 → ""`; else map `clamp(v,0,100)*8/100` → `blocks[min(7, idx)]`.
- macOS wiring: `AppDelegate.forecastLines()` / `sparklines()` / `pauseRemainingText()` build `[Provider: String]` / `String?` passed via `StatusMenuContext`; `forecastAlertCandidates(for:)` feeds `notificationCoordinator`. `applicationDidFinishLaunching` now `startRefresh(showLoadingIndicator: true)` (was `refreshNow()`). `refreshNow()` clears pause then fetches. `StatusMenuActions` gained `pause1h/pause3h/pauseUntilResumed/resumePolling`.
- Windows wiring: `TrayAppContext.RefreshAsync` early-returns when `PauseController.IsPaused` (no clear); `AddProvider` shows the forecast line; `HistoryMenu` shows sparklines; `AddPauseControls`/`PausePolling` manage the submenu; `HandleNotifications` merges `ForecastCandidates`. `SettingsForm.RebuildContent()` (deferred) re-localizes.
- Settings keys added: `showForecast` (default true), `depletionAlertEnabled` (false), `pollPausedUntil` (nil). Registered in macOS `registerDefaults` / Windows `AppSettings` initializers.
- **Menu placement:** forecast line sits between the recovery/detail block and the 5h-reset row inside each provider section (`addUsage` macOS / `AddProvider` Windows). Pause controls sit between "Preferences…" and "Diagnostics". Sparklines sit in the History submenu right after the trend text, before the retention row.
- **Refresh-loop order (macOS `startRefresh`):** pause guard → (if not paused) fetch → `historyStore.append` → `notificationCoordinator.handleNotifications(for:extraCandidates:localizer:)` (base + forecast candidates) → `updateStatusTitle` → `configureMenu`. `configureMenu` recomputes `forecastLines()`/`sparklines()`/`pauseRemainingText()` from `historyStore.load()` each build (cheap file read). Windows `RefreshAsync` mirrors this; menu is fully rebuilt in the `finally`.
- **Prefs rebuild mechanics:** macOS `buildContent` first does `contentView.subviews.forEach { removeFromSuperview() }`, re-sets the 3 localized checkbox titles (lazy vars set once at init), then rebuilds the stack; the lazy control instances are re-parented into the new stack. Windows `RebuildContent` recreates the `Localizer`, disposes the old `Controls`, then `BuildContent()` (fresh controls). Prefs window height bumped 420→480 (macOS) / 470→520 (Windows) for the 2 new checkboxes.
- **Windows atomic settings save:** `SettingsStore.Save` now writes `Path + ".tmp"` then `File.Move(overwrite: true)` (mirrors `UsageHistoryStore.Save`) — needed because pause writes settings frequently.

## Files Changed

### Source — Core (both platforms)
- `Sources/TokenTrackerCore/UsageForecast.swift` + `windows/…Core/UsageForecast.cs` — **new**; forecaster, text helper, alert evaluator, `ForecastWindow`.
- `Sources/TokenTrackerCore/PauseController.swift` + `…Core/PauseController.cs` — **new**; pause math.
- `Sources/TokenTrackerCore/Sparkline.swift` + `…Core/Sparkline.cs` — **new**; series + block renderer.
- `Sources/TokenTrackerCore/UsageHistoryStore.swift` + `…Core/UsageHistoryStore.cs` — 7d delta in `providerTrend` (shared `deltaText`).
- `Sources/TokenTrackerCore/Settings.swift` + `…Core/SettingsStore.cs` — `showForecast`/`depletionAlertEnabled`/`pollPausedUntil`; Windows `Save` made atomic.
- `Sources/TokenTrackerCore/Localization.swift` + `…Core/Localizer.cs` — 11 new L10n keys (forecast ×5, pause ×6), en+ko on both.

### Source — apps
- `Sources/TokenTrackerMenuBar/AppDelegate.swift` — forecast/sparkline/pause helpers; launch uses `startRefresh`; pause handlers.
- `Sources/TokenTrackerMenuBar/StatusMenuBuilder.swift` — `forecastLines`/`sparklines`/`pausedRemainingText` context + pause submenu.
- `Sources/TokenTrackerMenuBar/UsageNotificationCoordinator.swift` — `extraCandidates` merge.
- `Sources/TokenTrackerMenuBar/PreferencesWindowController.swift` — 2 toggles; rebuildable `buildContent`; re-localize on language change.
- `windows/TokenTracker.Windows/TrayAppContext.cs` — forecast line, sparkline, pause controls/guard, forecast alerts.
- `windows/TokenTracker.Windows/SettingsForm.cs` — 2 checkboxes; `RebuildContent()` on language change.

### Tests
- `Sources/TokenTrackerSmokeTests/main.swift` + `windows/TokenTracker.Windows.Tests/Program.cs` — forecast truth table, alert gating, pause boundaries + persistence round-trip, sparkline mapping/downsample, 7d trend + nil case.

### CI / build / docs
- `.github/workflows/ci.yml` — publish smoke step (PR #5).
- `scripts/build_app.sh` — version 1.1 / build 2.
- `plans/FEATURE_PLAN_usage-insights-and-controls_2026-07-06.md` — **new**; the plan.
- `~/.claude/…/memory/local-verification.md` — CI/branch-protection/publish-smoke notes.

## User Feedback & Preferences (REQUIRED — never omit)

- **"추천 순서로 진행"** — do the 4 features in the recommended PR order (A→B→C→D); adopt my recommended answers to the two plan open-questions (manual refresh lifts pause; sparkline Option A). Expects autonomous multi-PR execution with per-PR reporting.
- **"머지해줘" / merges** — approves merging; early self-authored merges were classifier-blocked until this standing directive. Repo pattern: explicit Korean go-ahead.
- **"버전 1.1로 올리고 DMG도 새로 만들어줘"** — bump version + rebuild DMG + reinstall.
- **"설정메뉴가 언어를 영어로 바꿔도 한글로 나와 수정해줘"** + **"업데이트 일시중지 … 재실행시 유지 안되는것 확인해줘"** — the two bug reports (with screenshot). Wants root-cause + fix + verification.
- **"확인 완료"** — confirmed the two fixes work in the reinstalled app.
- **"/handoff 하고 머지해줘. 릴리즈 빌드 업로드 해줘"** — write handoff, merge it, upload the v1.1 release.
- Standing (inherited, still honored): keep the feature (don't disable polling); **macOS/Windows parity mandatory**; Korean-facing replies with English code/artifacts; CI-equivalent checks pass locally; never push to protected `main` (branch + PR); pass explicit `model` to subagents.
- Works decisively in short Korean commands; prefers action over re-confirmation once a direction is set; wants proactive honesty when something is off (surfaced the `dist/` anomaly rather than glossing).

## Where We're Going

1. **Upload the v1.1 release** (immediate, in progress this turn): tag `v1.1` on `main` → `release.yml` builds the universal macOS DMG + Windows win-x64/win-arm64 zips + checksums and creates the GitHub Release. (Alternative if the tag push is classifier-blocked: `gh release create v1.1` + upload the local DMG, or the user pushes the tag via `!`.)
2. **(Optional) Sparkline Option B** — a drawn bitmap chart (macOS `NSImage` menu-item view / Windows `ToolStripMenuItem.Image`) if the user wants higher fidelity than the unicode blocks.
3. **(Optional) macOS signing/notarization** — the `.app`/DMG are unsigned (Gatekeeper prompt on other machines). Real distribution gap, unrelated to features.
4. **(Optional) Forecast smoothing** — linear regression over the post-reset segment instead of first/last delta, if the ETA reads jumpy in real use.
5. **Observe** — confirm the forecast/sparkline populate correctly with real accumulated history (needs ≥2 points and a declining 5h for the forecast line to appear).
6. **After the release lands**, verify assets and consider adding a Windows-machine smoke pass of the tray menu (pause submenu, forecast/sparkline rows, settings `RebuildContent`) since CI only compiles the WinForms app:
   ```bash
   gh release view v1.1 --json assets -q '.assets[].name'   # expect macOS DMG + win-x64/win-arm64 zips + .sha256
   ```

## Risks & Blockers

- **WinForms app (`net10.0-windows`) is compile-checked by CI only — never run locally.** `TrayAppContext`/`SettingsForm` runtime behavior (pause menu, forecast/sparkline rows, prefs `RebuildContent`) is unverified on a real Windows machine. The macOS equivalents are verified; parity is by construction. A Windows user should smoke-test the tray menu + settings form.
- **dotnet not installed system-wide**; `curl|bash` bootstrap is sandbox-blocked. Windows local testing depends on the reused scratchpad install (`fc637fd9-…`, session-scoped, may be GC'd). CI covers Windows regardless.
- **Prefs language switch (both platforms) is code+CI-verified but not UI-automated** — the native popup click wasn't scriptable. User confirmed manually.
- **Forecast/sparkline need accumulated history** — absent on a fresh launch (expected), so "I don't see it yet" is normal until a few poll cycles pass.
- **`dist/` old DMGs vanished mid-session, cause unexplained** by agent commands. No data loss (all on GitHub Releases), but flagged in case it recurs.
- **Prefs re-localization re-parents reused controls (macOS)** and adds identical `>=160` width constraints on each language toggle — benign (redundant, non-conflicting) but the constraint set grows if a user toggles language many times in one session. If it ever matters, refactor to store/update label refs instead of rebuilding.
- **Forecast projects from `now` using the last observed remaining** — assumes remaining hasn't changed since the last history point (true right after a refresh, which is when it's computed). A long gap between last sample and `now` would make the ETA slightly optimistic.
- **The `.app` and DMG are unsigned/un-notarized** — Gatekeeper will warn on machines other than this dev Mac (right-click→Open, or `xattr -d com.apple.quarantine`). Fine for local use; a real distribution gap.

## Open Questions

- Did the `dist/` old DMGs get removed by something outside the agent's commands? Unresolved; harmless (Releases hold them).
- Should the sparkline/forecast also cover the 7d window in the menu (currently 5h only)? Menu compactness vs completeness — deferred.
- Is v1.1 the right version label, or should the bug fixes be 1.1.1? Since 1.1 was never released before this session, shipping 1.1 with the fixes folded in is fine.
- Should the forecast also appear as a menu row when there's *not enough data* (a "collecting…" hint), or stay hidden (current)? Chose hidden to avoid clutter; a user unaware of the data dependency might wonder why it's missing on a fresh launch.
- Should provider-toggle in Preferences also respect a pause (it currently calls `refreshNow`, which lifts the pause)? Low-impact edge; left as-is since toggling a provider is an active config change.

## Quick Start for Next Session

```bash
# Restore context
cd "/Users/jkl/Projects/Token tracker" && git status -sb && git log --oneline -8

# The plan + this handoff
sed -n '1,120p' plans/FEATURE_PLAN_usage-insights-and-controls_2026-07-06.md
sed -n '1,80p'  plans/handoffs/HANDOFF_usage-insights_forecast-pause-sparkline_2026-07-06.md

# Key new Core files (Swift + C# mirror each other line-for-line)
sed -n '1,120p' Sources/TokenTrackerCore/UsageForecast.swift        # windows/…Core/UsageForecast.cs
sed -n '1,60p'  Sources/TokenTrackerCore/PauseController.swift       # windows/…Core/PauseController.cs
sed -n '1,60p'  Sources/TokenTrackerCore/Sparkline.swift            # windows/…Core/Sparkline.cs

# UI wiring (menu/prefs/refresh loop)
sed -n '33,120p' Sources/TokenTrackerMenuBar/AppDelegate.swift      # launch, forecast/pause/sparkline helpers
grep -n "forecast\|Forecast\|Pause\|sparkline\|Sparkline" windows/TokenTracker.Windows/TrayAppContext.cs

# Verify the installed app is the new build
/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "/Applications/Token Tracker.app/Contents/Info.plist"  # expect 2

# Verify current state — macOS
swift build && swift run TokenTrackerSmokeTests

# Verify current state — Windows (reuse prior dotnet; curl|bash bootstrap is sandbox-blocked)
DN="/private/tmp/claude-501/-Users-jkl-Projects-Token-tracker/fc637fd9-00b5-4ca7-a40b-498dfdb2e3e0/scratchpad/dotnet/dotnet"
"$DN" run --project windows/TokenTracker.Windows.Tests/TokenTracker.Windows.Tests.csproj

# Next action
# Upload the v1.1 GitHub release: push tag v1.1 on main to trigger release.yml
# (builds universal macOS DMG + Windows zips + creates the Release). If already
# done, verify assets: gh release view v1.1 --json assets -q '.assets[].name'
```

## Session Closed

**Closed at:** 2026-07-06 16:23 KST
**Branch:** committed on `handoff/usage-insights-2026-07-06`, merged to `main` via PR (branch-protected — no direct push)
**Session status:** Handed off to next session
