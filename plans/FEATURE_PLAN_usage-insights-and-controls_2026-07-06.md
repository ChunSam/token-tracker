# Feature Plan — Usage Insights & Controls (items 1–4)

**Date:** 2026-07-06
**Status:** PLAN (not yet implemented)
**Scope:** macOS menu-bar (Swift) **and** Windows tray (C#/WinForms) — parity is mandatory.
**Baseline:** `main` @ `bd72c6c` (429 hardening + CI gate + publish smoke all merged; `main` branch-protected).

## Guiding constraints (apply to every feature)

1. **No new API load.** The whole `claude-usage-stability` chain exists to *reduce* pressure on the shared per-account `/api/oauth/usage` budget. Features 1, 2, 4 read only the **already-collected local history** (`UsageHistoryStore`) — zero new network calls. Feature 3 *reduces* calls.
2. **macOS ⇄ Windows parity.** Every Core behavior lands on both platforms with matching semantics and matching unit tests. The two ports are near line-for-line today; keep it that way.
3. **Pure, testable Core.** New logic goes in `TokenTrackerCore` / `TokenTracker.Windows.Core` as pure functions/types with injected `now`, so it's unit-testable without an HTTP or UI harness (the only test seams that exist — see `Sources/TokenTrackerSmokeTests/main.swift` and `windows/TokenTracker.Windows.Tests/Program.cs`).
4. **Localization stays in sync.** Any new user-facing string adds a `L10nKey` case **and** both `english`+`korean` entries on **both** platforms. On Windows a missing Korean key falls through to the raw enum name (no English fallback), so both dictionaries must be updated together.
5. **Verification bar (CI-equivalent, must pass locally before each PR):**
   - macOS: `swift build` then `swift run TokenTrackerSmokeTests` → `TokenTrackerSmokeTests passed`.
   - Windows Core+Tests (`net10.0`): `<dotnet> run --project windows/TokenTracker.Windows.Tests/…csproj` → `TokenTracker.Windows.Tests passed` (dotnet is not installed system-wide; reuse a scratchpad install or ask the user — `curl|bash` bootstrap is sandbox-blocked).
   - WinForms app (`net10.0-windows`) cannot compile on macOS — CI (`.github/workflows/ci.yml`, now including a publish smoke) is the gate. `main` protection requires both CI checks green.
   - **Windows test date-bomb:** `Program.cs` hardcodes `now = 2026-05-27`. New forecast/pause tests must inject their own `now` (they do by design); any test comparing against the wall clock must stamp with `DateTimeOffset.Now`.

## Current architecture recap (grounding anchors)

- **Refresh loop.** macOS `AppDelegate.startRefresh` (`AppDelegate.swift:65`): `usageService.refresh()` → set `snapshot` → `historyStore.append(result, retentionDays:)` (`:78`) → `notificationCoordinator.handleNotifications` (`:79`) → `updateStatusTitle` → `configureMenu`. Timer in `scheduleTimer` (`:52`), floor `max(60, refreshInterval)`. Windows mirror: `TrayAppContext.RefreshAsync` (`TrayAppContext.cs:60`), append at `:92`, notify `:93`, `SetIcon` `:94`, menu rebuilt every cycle at `:104`.
- **Menu build.** macOS `StatusMenuBuilder.build` (`StatusMenuBuilder.swift:33`); per-provider rows in `addUsage` (`:133`); History submenu `historyItem` (`:105`). Context passed via `StatusMenuContext` (`:17`), actions via `StatusMenuActions` (`:5`). Windows `TrayAppContext.BuildMenu` (`:116`), per-provider `AddProvider` (`:164`), `HistoryMenu` (`:238`).
- **History.** `UsageHistoryStore.append(_:retentionDays:now:)` coalesces entries <60s apart; `UsageHistoryFormatter.trendSummary` reports **only the 5h delta** today (both platforms — this is what item 4 fixes); `csvString` unchanged. At the 5-minute default poll, the 5h window holds ~60 points and 7d holds thousands (capped by retention) — ample for forecasting and sparklines.
- **Alerts.** `UsageAlertEvaluator.candidates(snapshot, settings, now, localizer)` emits 5h-low / 7d-low / reset-proximity candidates, deduped downstream (`UsageNotificationCoordinator` on macOS; `deliveredAlertIds` HashSet in `TrayAppContext.HandleNotifications:307` on Windows).
- **Settings.** macOS `Settings` (UserDefaults, `Settings.swift`) with `registerDefaults()` + `migrateLegacyRefreshInterval()`. Windows `AppSettings`/`SettingsStore` (JSON file). 11 keys, 1:1 across platforms. **Note:** `SettingsStore.Save` (Windows) is **non-atomic** — relevant to feature 3 (see its Risks).
- **Prefs UI.** macOS `PreferencesWindowController` — `NSStackView` with `row`/`stepperRow`/`section` helpers (`:241`,`:254`,`:229`). Windows `SettingsForm` — `TableLayoutPanel` with `AddCheckbox`/`AddCombo`/`AddNumber`/`AddHeader` helpers.
- **Rendering.** macOS status text drawn in `StatusItemRenderer` (already color-emphasizes a low/7d-warning state via `sevenDayWarningColor`). Windows `TrayIconRenderer.Render` (32×32 `Bitmap`, blue→red `WarningBackground` on low). Menu items on both platforms accept custom views/images (macOS `InfoMenuItemView`; Windows `ToolStripMenuItem.Image`).

---

## Feature 1 — Depletion forecast ("time-to-empty") + predictive alert ⭐

**Value.** `resetAt` says *when the window refills*; nothing says *when you'll run out at the current pace*. Compute a burn rate from stored history and surface "at this rate the 5h window empties in ~2h10m" and, more actionably, "you'll run out **before** the reset." Turns passive %s into a plan.

### 1a. Core — `UsageForecast` (pure, both platforms)

New file `Sources/TokenTrackerCore/UsageForecast.swift` + `windows/TokenTracker.Windows.Core/UsageForecast.cs`.

```
enum ForecastWindow { fiveHour, sevenDay }

struct UsageForecast {           // nil result = "no forecast"
    burnPerHour: Double          // remaining-% consumed per hour (> 0)
    secondsToEmpty: Double
    emptyAt: Date
    willEmptyBeforeReset: Bool
}

static func forecast(entries, provider, window, resetAt, now) -> UsageForecast?
```

**Algorithm (deterministic, injected `now`):**
1. Map history → `(t, remaining)` for the chosen window & provider; drop `nil` remaining; sort ascending by `t`.
2. **Trim to the current window instance:** walk the series and cut everything up to and *including* the last index where `remaining[i] > remaining[i-1]` (an upward jump = a window reset). Forecast only from the post-reset segment — otherwise a reset looks like negative consumption.
3. Guards → return `nil` if: `segment.count < 2`; elapsed `segment.last.t − segment.first.t < minElapsed` (600 s); or `drop = first.remaining − last.remaining ≤ 0` (steady / replenishing → nothing to forecast).
4. `burnPerHour = drop / (elapsed / 3600)`; `secondsToEmpty = last.remaining / burnPerHour * 3600`; `emptyAt = now + secondsToEmpty`.
5. `willEmptyBeforeReset = resetAt != nil && emptyAt < resetAt`.

Edge cases codified as tests: steady decline → correct ETA; mid-series reset → only the post-reset slope used; flat/replenishing → `nil`; <2 points or <10 min span → `nil`; ETA straddling `resetAt` → `willEmptyBeforeReset` boundary. (Use `jitter`-free style: pure function, exact asserts — same discipline as `RateLimitBackoff`.)

### 1b. Core — predictive alert (pure, both platforms)

Add a **separate** evaluator (keep the existing `UsageAlertEvaluator.candidates` untouched/stable): `UsageForecastAlert.candidates(snapshot, forecasts:[Provider: (fiveHour, sevenDay)], settings, now, localizer) -> [UsageAlertCandidate]`. Emits one candidate per provider/window where `willEmptyBeforeReset` is true, gated by `settings.notificationsEnabled && settings.depletionAlertEnabled`. Candidate id `"{provider}-{5h|7d}-empty-before-reset-{unixReset}"` so it dedupes per window instance (same pattern as reset-proximity ids). Callers merge these with the existing candidates before the dedupe/dispatch step already in place.

### 1c. UI wiring

- **macOS.** In `AppDelegate.configureMenu`, compute forecasts from `historyStore.load()` + current `snapshot` and pass per-provider forecast text into `StatusMenuContext` (new fields, alongside `historyTrendText`). `StatusMenuBuilder.addUsage` (`:133`) renders one extra line: `예상 소진: ~2h 10m` (+ ` · 리셋 전 소진` when `willEmptyBeforeReset`), or the "steady"/"not enough data" localized string. In `startRefresh`, after computing forecasts, call the new forecast-alert evaluator and feed its candidates into `notificationCoordinator`.
- **Windows.** Mirror in `TrayAppContext.RefreshAsync`/`BuildMenu.AddProvider` (`:164`): compute forecasts from `historyStore.Load()`, add a disabled forecast row per provider, and merge forecast-alert candidates into `HandleNotifications` (`:307`).

### 1d. Settings + localization

- Settings: `showForecast: Bool = true`, `depletionAlertEnabled: Bool = false` (macOS `Settings` keys + `registerDefaults`; Windows `AppSettings` props). Prefs UI: one checkbox each — macOS `PreferencesWindowController` (Notifications section for the alert, a Display/History spot for `showForecast`); Windows `SettingsForm.AddCheckbox`.
- L10n keys (en/ko, both platforms): `forecastLabel`, `forecastSteady`, `forecastNotEnough`, `forecastEmptyBeforeReset`, `depletionAlertTitle`, `depletionAlertBody`, `showForecastLabel`, `depletionAlertToggle`.

### 1e. Tests
`UsageForecast.forecast` truth table + `UsageForecastAlert.candidates` (fires only when enabled & willEmptyBeforeReset) on **both** `main.swift` and `Program.cs`.

**Effort:** M (Core + alert + menu + 2 settings ×2 platforms). **Risk:** low (pure, no API). **Depends on:** none.

---

## Feature 2 — History sparkline / mini-chart

**Value.** Full snapshots are stored across the retention window but only ever shown as a one-line delta + CSV. Visualize the remaining-% trend inline.

### 2a. Core — shared sampling (both platforms)

New `SparklineSeries.build(entries, provider, window, maxPoints, now) -> [Int]` (values 0–100), pure/testable: filter to the window's non-nil remaining, bucket/downsample to `maxPoints` (e.g. 24) by averaging or last-in-bucket. This sampling is identical on both platforms.

### 2b. Rendering — two options (pick one; 2a-text recommended first)

- **Option A (recommended first): Unicode block sparkline in Core.** `SparklineText.render(series) -> String` using `▁▂▃▄▅▆▇█`. **Fully shared, zero platform rendering code, unit-testable**, drops straight into the existing text menu rows (`infoItem` / `AddDisabled`). Lower fidelity but parity-free and cheap. Add to the History submenu on both platforms.
- **Option B (enhancement): drawn bitmap.** macOS render an `NSImage` polyline in a custom menu-item view (like `InfoMenuItemView`); Windows draw a `Bitmap` and set `ToolStripMenuItem.Image` in `HistoryMenu` (`:238`) — the agent confirmed menu items support images (same path as provider logos). **Do not** put it in the tray icon itself — `TrayIconRenderer.Render` has no history access and the icon is DPI-size-constrained; menu item is the right home. Higher fidelity, per-platform rendering code + no unit test for the pixels.

### 2c. Settings/L10n
Optional `showSparkline: Bool = true`; L10n `historyChartLabel`. Reuse the History submenu — no new top-level UI.

### 2d. Tests
`SparklineSeries.build` (bucketing, empty→[], single point) + (Option A) `SparklineText.render` mapping on both platforms.

**Effort:** S (Option A) / M (Option B). **Risk:** low. **Depends on:** none. **Recommendation:** ship Option A, treat B as a follow-up if the user wants a real chart.

---

## Feature 3 — Snooze / pause polling

**Value.** Lets the user actively drop API pressure (directly on-theme with the 429 work) — "pause updates for 1h / 3h / until I resume" when they know they're rate-limited or away.

### 3a. State — persisted pause (both platforms)

- Setting `pollPausedUntil: Date?` (macOS: store epoch `Double`, `0`/absent = not paused; Windows: `DateTimeOffset?`). Persisting it means a restart during a pause stays paused — consistent with the cooldown-persistence precedent.
- Pure helper `PauseController` (Core, both): `isPaused(pausedUntil, now) -> Bool`, `remaining(pausedUntil, now) -> TimeInterval`, `label(...)` for "재개까지 42m". Unit-testable with injected `now`.

### 3b. Refresh guard

- **macOS `AppDelegate.startRefresh` (`:65`):** if `PauseController.isPaused(settings.pollPausedUntil, now)` → skip `usageService.refresh()` (no network), just `configureMenu()` (so the "paused until X" row updates) and return. Timer keeps firing but no-ops until expiry. `refreshNow` (manual) may either respect or override the pause — **decision: manual "Refresh Now" clears the pause** (explicit user intent to fetch).
- **Windows `TrayAppContext.RefreshAsync` (`:60`):** same guard before the fetch block; menu rebuild still runs in `finally`.

### 3c. Menu UI

Submenu "업데이트 일시중지 ▸ 1시간 / 3시간 / 재개할 때까지", plus a top-of-menu "일시중지됨 — X 후 재개" info row and a "지금 재개" action when paused. macOS: new `StatusMenuActions` selectors (`pause1h`/`pause3h`/`pauseIndefinite`/`resume`) + `@objc` handlers in `AppDelegate` that set `settings.pollPausedUntil` and `configureMenu`. Windows: menu items in `BuildMenu` wired to handlers that set `settings.PollPausedUntil` + save + rebuild.

### 3d. Settings/L10n
L10n: `pausePolling`, `pause1h`, `pause3h`, `pauseUntilResumed`, `resumeNow`, `pausedUntilFmt`. **Windows robustness note:** pause writes go through `SettingsStore.Save`, which is currently **non-atomic** (`SettingsStore.cs:63`) — make `Save` atomic (temp-file + `File.Move(overwrite)`, mirroring `UsageHistoryStore.Save`) as part of this feature, or store pause in its own small file. macOS UserDefaults writes are already safe.

### 3e. Tests
`PauseController` boundary tests (paused just-before/after expiry; remaining minutes; `pausedUntil == nil`) on both platforms; assert the refresh guard path via the pure helper (no UI/HTTP seam for the actual skip).

**Effort:** M. **Risk:** low–med (adds a persisted field + Windows atomic-save tweak). **Depends on:** none. **On-theme bonus:** further reduces 429 exposure.

---

## Feature 4 — 7-day trend line (small)

**Value.** `UsageHistoryFormatter.trendSummary`/`providerTrend` report only the **5h** delta; add the **7d** delta so the History submenu shows both windows.

### 4a. Core (both platforms)
Extend `providerTrend` (`UsageHistoryStore.swift:126` / `UsageHistoryFormatter.cs`) to also read `remainingPercent7d` and emit e.g. `Claude 5h +3% · 7d −1%` (or a second line). No new settings, no UI plumbing beyond the existing `historyTrendText` row. Update `trendSummary` string assembly.

### 4b. Tests
Extend the existing trend-summary assertions on both platforms to cover the 7d delta (including the `nil`-remaining `--` case).

**Effort:** XS. **Risk:** minimal. **Depends on:** none. **Do first** as a warm-up — pure Core, no settings/UI/localization churn (reuses `historyTrend`).

---

## Recommended sequencing & PR plan

One feature per PR (each gated by branch protection + CI, incl. the new publish smoke). Suggested order by value ÷ effort:

1. **PR A — Feature 4** (7d trend). XS, pure Core, no settings. Fast confidence-builder that exercises the two-platform + two-test-suite loop.
2. **PR B — Feature 1** (forecast + predictive alert). The headline value; pure Core + menu + 2 settings.
3. **PR C — Feature 3** (snooze/pause). Persisted state + menu + Windows atomic-save fix.
4. **PR D — Feature 2** (sparkline, Option A text). Small, visual polish; Option B bitmap only if requested.

Each PR: implement Core (both platforms) → add unit tests (both suites) → wire UI → `swift build` + smoke + Windows Core tests locally → branch, push, open PR, watch CI green → merge on explicit approval (self-authored merges are classifier-gated; the repo's pattern is an explicit "머지해").

## Cross-feature file map

| Area | macOS | Windows |
|---|---|---|
| Forecast core | `Core/UsageForecast.swift` (new) | `Core/UsageForecast.cs` (new) |
| Forecast alert | `Core/UsageForecastAlert.swift` (new) | `Core/UsageForecastAlert.cs` (new) |
| Sparkline core | `Core/SparklineSeries.swift`+`SparklineText.swift` (new) | `Core/SparklineSeries.cs`+`SparklineText.cs` (new) |
| Pause core | `Core/PauseController.swift` (new) | `Core/PauseController.cs` (new) |
| 7d trend | `Core/UsageHistoryStore.swift` (edit `providerTrend`) | `Core/UsageHistoryStore.cs` (edit formatter) |
| Settings | `Core/Settings.swift` | `Core/SettingsStore.cs` (+ make `Save` atomic) |
| Localization | `Core/Localization.swift` | `Core/Localizer.cs` |
| Refresh/menu | `MenuBar/AppDelegate.swift`, `StatusMenuBuilder.swift` | `TrayAppContext.cs` |
| Prefs UI | `MenuBar/PreferencesWindowController.swift` | `SettingsForm.cs` |
| Tests | `SmokeTests/main.swift` | `Tests/Program.cs` |

## Risks & open questions

- **Forecast noise.** Short/volatile history can produce jumpy ETAs. Mitigations in the design: 10-min minimum span, post-reset-only slope, `nil` when not declining. Could later smooth with linear regression over the segment instead of first/last delta — start simple, iterate if noisy.
- **"Refresh Now" vs pause.** Proposed: manual refresh clears the pause (explicit intent). Confirm this is the desired UX vs. "manual refresh is also suppressed."
- **Windows `SettingsStore.Save` non-atomic.** Feature 3 writes pause state; make Save atomic in that PR (low effort, also hardens all settings writes).
- **`UsageSource` missing `LocalLog` on Windows** (`Models.cs`) — pre-existing divergence, *not* touched by these 4 features (none add a data source); noted only so it isn't mistaken for new work.
- **Sparkline fidelity.** Option A (unicode) is parity-cheap but coarse; if the user wants a real chart, that's Option B (per-platform bitmap, no pixel unit tests).
- **No UI unit tests.** Menu/prefs changes are validated by build + the macOS `.app` smoke launch + CI compile; only the pure Core pieces get unit tests. This matches the existing test strategy.

## Verification checklist (per PR)

- [ ] `swift build` clean (incl. `TokenTrackerMenuBar` app target, not just smoke).
- [ ] `swift run TokenTrackerSmokeTests` → passed (new Core assertions included).
- [ ] Windows Core tests → `TokenTracker.Windows.Tests passed` (reused/boot-strapped dotnet 10).
- [ ] New L10n keys present in **all four** dictionaries (en/ko × macOS/Windows).
- [ ] PR CI green: macOS job + Windows job (build + tests + publish smoke).
- [ ] (Feature 1/3, optional) re-run the `.app` two-instance/guard demo or a manual launch to eyeball the new menu rows.
