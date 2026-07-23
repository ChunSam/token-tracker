# Codex 7d forecast/sparkline fallback + v1.1.2 release (5h lane still absent upstream)

**Date:** 2026-07-23
**Status:** COMPLETED (merged to `main` as `088748d`; installed app 1.1.2 (4); GitHub Release v1.1.2 published as Latest)
**Bead(s):** none (bd unavailable in this environment)
**Epic:** Token Tracker usage UX
**Chain:** `usage-insights` seq `3`
**Parent:** `HANDOFF_usage-insights_codex-weekly-window_2026-07-23.md`
**Prior chain:** `HANDOFF_usage-insights_forecast-pause-sparkline_2026-07-06.md` > `HANDOFF_usage-insights_codex-weekly-window_2026-07-23.md` > this

---

## Stale References

- `UsageForecastText.menuLine(forecast:localizer:)` (Swift) / `UsageForecastText.MenuLine(forecast, localizer)` (C#) — signature CHANGED this session; both now require a `window` parameter: `menuLine(forecast:window:localizer:)` / `MenuLine(forecast, window, localizer)`. Any older notes calling the two-arg form are stale.
- Parent's statement "Menu forecast line remains **5h-window-only** … Codex currently gets NO menu forecast line" — NO LONGER TRUE; that gap is exactly what this session fixed (7d fallback). Same for "sparkline is the only surface that shows them [polluted 5h points]" — the Codex sparkline now renders the 7d lane, so the polluted 5h series is not displayed anywhere.
- Parent's risk "Codex 5h sparkline shows stale (weekly) points until ~07-30" — OBSOLETE; the fallback hides the 5h series for Codex entirely (data still ages out on schedule, it's just never rendered).
- Memory claim "WinForms app cannot be compiled on macOS" (was in `local-verification.md`) — DISPROVEN and rewritten this session; see Key Decisions.
- Parent's version defaults `1.1.1` / build `3` in `scripts/build_app.sh` — now `1.1.2` / `4`.

## Since Last Handoff

Parent's "Where We're Going" had 6 items; this session resolved 4 of them:

- **#1 Observe the fixed app** — DONE and exceeded: verified at session start (cache `5h None / 7d 96%`, app 1.1.1 (3), single instance) and again post-deploy. The 7d lane accumulated 137 history points in ~11h (96%→88%), enough that the new fallback forecast produced a real ETA on day one.
- **#2 Watch for OpenAI restoring the 5h window** — checked live: NOT restored. `wham/usage` still returns weekly-as-primary (`limit_window_seconds: 604800`), no `secondary_window`, `additional_rate_limits: null`. Shape byte-identical to parent's capture (same `reset_at: 1785331564`).
- **#3 (Decide) 7d fallback for Codex forecast/sparkline** — DECIDED YES by the user (picked from an option menu) and IMPLEMENTED this session (PR #15). This was the session's main work.
- **#4 (Optional) cut a release** — DONE, but as **v1.1.2** (not the v1.1.1 the parent anticipated — this session's feature bumped past it). Published as Latest with all 6 assets.
- **#5 (carried: sparkline Option B, signing/notarization, forecast smoothing)** — still untouched; now phased in the paired PLAN file.
- **#6 (idea: surface `rate_limit_reset_credits` etc.)** — still untouched; now Phase 1 of the paired PLAN file.
- Parent's open question "should forecast/sparkline fall back to 7d…?" — ANSWERED (yes, shipped). Parent's open question "will OpenAI restore the 5h window?" — still open, but moot for correctness (length classification self-heals).
- Parent's risk "agent cannot merge PRs (classifier + PAT)" — PARTIALLY RESOLVED: with an explicit user directive ("머지 해줘"), `gh pr merge 15 --rebase --delete-branch` ran without a classifier block. The pattern is now *ask → user says merge → agent runs gh merge*, no `!` escape needed.
- Parent's risk "WinForms runtime still never executed (CI compiles only)" — narrowed: WinForms now compile-checks **locally on macOS** too (new discovery), but still has never been *run* on Windows.

## Reference Documents

- `plans/FEATURE_PLAN_usage-insights-and-controls_2026-07-06.md` — grandparent's feature plan (forecast/pause/sparkline design incl. "Option B" bitmap sparkline, parity file map).
- `agent.md` — project conventions (Claude usage API endpoint ~line 78).
- `/Users/jkl/.claude/CLAUDE.md` — global conventions: Korean to user / English artifacts; CI-equivalent checks pass locally; never push to protected `main` (branch + PR); explicit `model` for subagents; never pipe a gate's exit code.
- `~/.claude/projects/-Users-jkl-Projects-Token-tracker/memory/local-verification.md` — local test procedure for both platforms (UPDATED this session: WinForms macOS compile-check command added).
- `plans/handoffs/PLAN_usage-insights_codex-7d-fallback_2026-07-23.md` — the paired plan for the next session (written by this /handoffplan).

## The Goal

Token Tracker (macOS Swift menu-bar + Windows C#/WinForms tray) shows Claude and Codex remaining usage in 5h and 7d windows. The parent session fixed the window *mapping* after OpenAI removed the Codex 5h rate-limit window (2026-07-12), but left Codex with **no menu forecast line and no sparkline** — both surfaces were hardcoded to the 5h window, and Codex's 5h lane is now empty. This session's goal: verify the parent's fix is holding (it is), then make the forecast and sparkline surfaces **fall back to the 7d window** when a provider's 5h lane is empty — restoring both surfaces for Codex, keeping Claude untouched, self-healing back to 5h if OpenAI restores that window, with full macOS⇄Windows parity — and ship it (PR, local deploy, GitHub Release v1.1.2).

## Where We Are

- Repo `/Users/jkl/Projects/Token tracker`, branch **`main`** @ `088748d` (HEAD), clean, in sync with origin. PR **#15** rebase-merged; branch `feat/codex-7d-forecast-fallback` deleted. Tag **`v1.1.2`** on `088748d`.
- **New `DisplayFormatter.preferredForecastWindow(_:)` / `PreferredForecastWindow(ProviderUsage)`** (both platforms): `.fiveHour` when `remainingPercent5h != nil`; else `.sevenDay` when `remainingPercent7d != nil`; else `.fiveHour`. Placed next to `isSevenDayWarning` (display-concern grouping).
- **New `ForecastWindow.shortLabel`** (Swift computed property) / **`ForecastWindowExtensions.ShortLabel(this ForecastWindow)`** (C# extension method — C# enums can't have members): returns literal `"5h"` / `"7d"`. Now shared by the alert body/id builder (previously inline ternaries) and the new menu/sparkline labels. Alert ids/bodies unchanged.
- **`UsageForecastText.menuLine(forecast:window:localizer:)` / `MenuLine(forecast, window, localizer)`**: gained the `window` parameter; appends `" (7d)"` after the duration **only** for `.sevenDay`. The `.fiveHour` output is byte-identical to before (pinned by new tests).
- **`UsageForecaster.durationText` / `DurationText` gained a days tier**: `hours >= 24 → "{d}d {h}h"` (minutes dropped above a day). Weekly ETAs now render `5d 4h` instead of `124h 27m`. Also affects the 7d depletion-alert body (improvement, not regression).
- **macOS `AppDelegate.forecastLines()`**: per provider computes `window = preferredForecastWindow(usage)`, passes matching reset (`resetAt5h` vs `resetAt7d`) to the forecaster and `window` to `menuLine`.
- **macOS `AppDelegate.sparklines()`**: `window = snapshot.map { preferredForecastWindow($0.usage(for: provider)) } ?? .fiveHour`; label now `"\(provider.displayName) \(window.shortLabel) \(rendered)"` (was hardcoded `"5h"`).
- **Windows `TrayAppContext.AddProvider`** (forecast block) and **`HistoryMenu`** (sparkline block): mirrored; HistoryMenu picks the usage via `provider == Provider.Claude ? snapshot.Claude : snapshot.Codex` (null snapshot → FiveHour).
- **Predictive-alert paths untouched on both platforms** — they already evaluate BOTH windows (macOS `AppDelegate.forecastAlertCandidates` lines ~198-208; Windows `TrayAppContext.ForecastCandidates` lines ~405-430). The remaining hardcoded `.fiveHour` references in app code are exactly these and are correct.
- **No L10n changes** — the `(7d)` marker and sparkline labels are language-neutral literals, consistent with the established alert-body convention. All four localization dictionaries untouched.
- **Version defaults**: `scripts/build_app.sh` `APP_VERSION` 1.1.1→**1.1.2**, `APP_BUILD` 3→**4**.
- **Installed app**: `/Applications/Token Tracker.app` replaced with universal (x86_64+arm64) **1.1.2 (4)**, running, single instance (pgrep count 1), fetching live (`codex 5h None / 7d 88 / source api`).
- **Live fallback verified end-to-end by replicating the forecaster on the app's real history**: Codex 7d segment 137 points, 96%→88% over 11.3h, newest sample 62s old → burn 0.71%/h → ETA ~**5d 4h**, `before-reset=True` (reset 2026-07-29T13:26Z). Expected menu line: `예상 소진: ~5d 4h (7d) · 리셋 전 소진` — the first Codex forecast line since 07-12.
- **GitHub Release "Token Tracker v1.1.2"** published 2026-07-23T14:56:01Z, marked **Latest**, targeting `main`; run 30017971164 all 4 jobs green; 6 assets (see Evidence).
- **Tests added** (both `main.swift` and `Program.cs`): preferred-window truth table (5h present / 5h-nil+7d / both-nil), menuLine 5h-unchanged + 7d-marked + nil→nil, durationText `86400→"1d 0h"` and `273000→"3d 3h"`.
- **Local gates green**: `swift build` + `swift run TokenTrackerSmokeTests`; Windows Core tests via freshly bootstrapped scratchpad dotnet 10.0; **NEW: WinForms app project compiled on macOS** (`dotnet build windows/TokenTracker.Windows/TokenTracker.Windows.csproj -p:EnableWindowsTargeting=true` — 0 warnings, 0 errors, 6.3s) — first time the TrayAppContext layer was compile-validated before CI.
- **CI green on PR #15 first run**: `macOS build + smoke tests` 1m2s, `Windows build + tests` 1m15s.
- Memory `local-verification.md` updated: WinForms macOS compile-check replaces the "cannot compile, review by hand" guidance.
- Codex 5h-lane polluted history (07-12→07-23 weekly values): still present on disk, **no longer rendered anywhere**, ages out via 7-day retention by ~07-30. No purge (unchanged decision).
- Claude behavior fully unchanged: its 5h lane always reports, so `preferredForecastWindow` always returns `.fiveHour` for it.

## What We Tried (Chronological)

1. **Structured onboarding** (user's session opener demanded narration: summarize handoff → state verification plan → read key files + 2-3 unlisted adjacent files → propose first action → WAIT for go-ahead). Read parent handoff (240 lines); read `CodexWindowMapper.swift`/`.cs` (matched parent's description); parity-grepped `isSevenDayWarning`/`maximumSampleAge` — first grep missed C# because C# uses PascalCase (`IsSevenDayWarning`/`MaximumSampleAge`); case-insensitive re-grep confirmed parity.
2. **Adjacent-file exploration** (not in parent's key-file list) paid off: `AppDelegate.swift:161-194` showed both `forecastLines()` and `sparklines()` hardcode `window: .fiveHour` — the exact surface of parent's decision item #3; `Sparkline.swift` showed `SparklineSeries.build` **already takes a `window:` parameter** (so the fallback is a call-site change, not a core change); `.github/workflows/release.yml` confirmed a `v*` tag push runs the full 3-job release pipeline.
3. **Verification pass** (after "진행해"): swift build + smoke green; live `wham/usage` call (user's own auth, token never printed) → 5h window still absent (same shape and same `reset_at` as parent's capture); installed app 1.1.1 (3), single instance.
4. **Cache read stumble**: first attempt assumed a `snapshot` top-level key → `KeyError`. Actual `usage-cache.json` shape is flat: `{codex: {...}, claude: {...}, updatedAt}`. Confirmed codex `5h None / 7d 96 / source api`.
5. **Asked the user to choose next work** (multi-select option menu: 7d fallback (recommended) / v1.1.2 release cut / reset-credits display / observe only). User picked **only** "7d 폴백 구현" — but later requested the release cut separately in conversation, so both happened.
6. **Traced ALL surfaces before coding**: read `UsageForecast.swift` fully (menu-line format has no window label; alert builder already uses literal `"5h"`/`"7d"`); found Windows surfaces at `TrayAppContext.cs:204-212` (AddProvider forecast) and `:306-311` (HistoryMenu sparkline, hardcoded `"5h"` label); confirmed `TrayAppContext` has a `snapshot` field usable by HistoryMenu; confirmed both platforms' predictive-alert paths already evaluate both windows (no change needed); L10n check → `forecastLabel` EN "Projected depletion" / KO "예상 소진" — window marker as a literal avoids touching all four dictionaries (and Windows still has no per-key fallback).
7. **Implemented Swift** (branch `feat/codex-7d-forecast-fallback`): `shortLabel`, durationText days tier, `menuLine(window:)`, alert refactor to `shortLabel`, `preferredForecastWindow`, AppDelegate call sites. Build + smoke green first run.
8. **Implemented C# mirror**: `ForecastWindowExtensions.ShortLabel`, `DurationText` days tier, `MenuLine(window)`, alert refactor, `PreferredForecastWindow`, TrayAppContext AddProvider + HistoryMenu. Bootstrapped dotnet via the memory's two-step method (background while Swift built) — worked again.
9. **Tests both platforms** reusing existing fixtures (`missingFiveHourUsage` 5h=nil/7d=42 etc., `steadyForecast` burn 20%/h → 7200s): truth table, byte-identical 5h line `"Projected depletion: ~2h 0m · empties before reset"`, marked 7d line `"…~2h 0m (7d) · …"`, duration days tier. All green.
10. **Tried compiling the WinForms project on macOS** (previously believed impossible): `dotnet build …TokenTracker.Windows.csproj -p:EnableWindowsTargeting=true` → **built, 0 errors** in 6.3s. Adopted as a local gate for app-layer C# edits; memory updated.
11. **Swept for missed call sites**: grepped all `menuLine`/`MenuLine` callers (all updated) and all remaining `ForecastWindow.FiveHour`/`.fiveHour` in app code (only the intentional alert paths + the null-snapshot default remain).
12. **PR #15** (single commit `376ec24`, 9 files +126/−22): CI green both jobs first run (macOS 1m2s, Windows 1m15s). Reported the `!` merge command per the parent's pattern.
13. **Merge surprise**: user said "머지 해줘" → ran `gh pr merge 15 --rebase --delete-branch` directly and it **worked** (no classifier block, unlike parent session where the same command was blocked without an explicit directive). Local `main` fast-forwarded e78e32b..088748d, branch deleted.
14. **Deployed locally**: `APP_ARCHS="arm64 x86_64" bash scripts/build_app.sh` (5.95s) → `lipo -archs` = `x86_64 arm64` → pkill, replace `/Applications`, `open` → PlistBuddy 1.1.2/4, pgrep 1.
15. **Verified live behavior beyond the cache**: replicated `UsageForecaster` in python against the app's real `usage-history.json` → Codex 7d forecast condition actually satisfied (see Evidence) — so the new line is expected to be visible in the menu right now, including the `(7d)` marker, the days-tier duration, AND the "before reset" suffix.
16. **Release cut** (after "릴리스 컷 진행"): `git tag v1.1.2 && git push origin v1.1.2` → run 30017971164. Caught own verification-discipline slip: watched with `gh run watch … | tail` (pipe hides exit code, violates global CLAUDE.md) → re-verified via `gh run view --json conclusion` (success ×4) and `gh release view` (6 assets, Latest).

## Key Decisions

- **Fallback keyed on the CURRENT snapshot's lanes, not on history contents.** `preferredForecastWindow` looks at `remainingPercent5h/7d` of the latest usage. Bonus: Codex's polluted 5h history (weekly values recorded 07-12→07-23) is instantly invisible because the 5h series is never rendered for a provider whose live 5h lane is empty. Rejected: "fall back when the 5h series is empty" — the polluted series is NOT empty, so it would have kept showing garbage until ~07-30.
- **Both-lanes-nil → `.fiveHour` default** (error/loading states). Keeps behavior identical to pre-fallback in degraded states; a provider with no data gets no forecast/sparkline anyway in practice.
- **Helper lives in `DisplayFormatter`, not `UsageForecast`** — it's a display-surface choice (which lane to show), grouped with `displayPercent`/`isSevenDayWarning` which make the same kind of decision for the tray.
- **`(7d)` marker is a language-neutral literal, not an L10n key.** Matches the established convention (`UsageForecastAlert` bodies already use literal `"5h"`/`"7d"`); avoids touching 4 dictionaries and dodges the known Windows no-per-key-fallback gap. The 5h line stays completely unmarked so the long-standing format doesn't churn.
- **`durationText` days tier added now** (not deferred): the first live 7d ETA would have rendered `124h+`-style text; `{d}d {h}h` (minutes dropped) mirrors `formatReset`'s existing day format. Accepted side effect: 7d depletion-alert bodies change format too (improvement).
- **`shortLabel` on the enum** (Swift property / C# extension method) rather than a free function — DRYs three sites (alert id, alert body, menu/sparkline labels) without changing any output where it replaced inline ternaries.
- **1.1.2 (4), not 1.2**: the change restores surfaces lost to the upstream API change — fix-family semantics, consistent with parent's 1.1.1 reasoning. Build bump keeps Copy-Diagnostics as the "is this the new binary?" signal.
- **WinForms macOS compile-check adopted as a local gate** (`-p:EnableWindowsTargeting=true`): app-layer C# edits (TrayAppContext) no longer wait for CI to catch compile errors. It compiles only — running the app still requires Windows.
- **Release cut in-session** (user asked): v1.1.2 supersedes the parent's "maybe v1.1.1" — no v1.1.1 release will ever exist; versions on GitHub go v1.1 → v1.1.2.
- **No history purge** (re-affirmed): polluted 5h entries now invisible AND still age out by ~07-30; rewriting `usage-history.json` remains risk > benefit.

## Evidence & Data

Session-start verification (all pre-conditions from parent held):

| Check | Result |
|---|---|
| `git status`/`log` | `main` @ `e78e32b` (parent's handoff commit), clean, synced |
| macOS `swift build` + smoke | `TokenTrackerSmokeTests passed` |
| Live `wham/usage` | `primary_window {used_percent: 4, limit_window_seconds: 604800, reset_at: 1785331564}`, `secondary_window: None`, `additional_rate_limits: None`, `plan_type: plus` — 5h NOT restored, shape unchanged from parent |
| Installed app | 1.1.1 (3), pgrep count 1 |
| Running-app cache | codex `5h: None, 7d: 96, resetAt7d: 2026-07-29T13:26:04Z, source: api` @ 04:29:42Z |

Post-deploy verification (1.1.2 (4)):

| Check | Result |
|---|---|
| `lipo -archs` on built app | `x86_64 arm64` |
| Installed PlistBuddy | `1.1.2` / `4`, pgrep count 1 |
| Fresh cache | codex `5h: None, 7d: 88, resetAt7d: 2026-07-29T13:26:04Z, source: api` @ 14:26:50Z |
| History depth | 2017 total entries; **137 Codex 7d-lane points** spanning 03:09:41Z (96%) → 14:26:50Z (88%) |

Live forecast replication (python mirror of `UsageForecaster` on real history — validates the fallback end-to-end):

| Quantity | Value |
|---|---|
| Post-reset segment | 137 pts, 96% → 88% |
| Span / newest age / drop | 11.3h / 62s / 8 points |
| Guards | span ≥600s ✓, age ≤1800s ✓, drop >0 ✓ |
| Burn rate | 0.71 %/h |
| ETA (secondsToEmpty) | ~5d 4h (days tier exercised) |
| before-reset | **True** (empty ~07-28 evening < reset 07-29T13:26Z) |
| Expected menu line (KO) | `예상 소진: ~5d 4h (7d) · 리셋 전 소진` |

New test expectations (both platforms, pinned):

| Test | Expectation |
|---|---|
| `preferredForecastWindow(5h=73, 7d=nil)` | `.fiveHour` |
| `preferredForecastWindow(5h=nil, 7d=42)` | `.sevenDay` |
| `preferredForecastWindow(5h=nil, 7d=nil)` | `.fiveHour` |
| `menuLine(steadyForecast, .fiveHour, en)` | `"Projected depletion: ~2h 0m · empties before reset"` (byte-identical to pre-change) |
| `menuLine(steadyForecast, .sevenDay, en)` | `"Projected depletion: ~2h 0m (7d) · empties before reset"` |
| `menuLine(nil, .sevenDay, en)` | nil |
| `durationText(86400)` | `"1d 0h"` (boundary) |
| `durationText(273000)` | `"3d 3h"` |

Release v1.1.2 (run `30017971164`, all 4 jobs success; published 2026-07-23T14:56:01Z, **Latest**, target `main`):

| Asset | Size (bytes) |
|---|---|
| TokenTracker-v1.1.2-macOS.dmg | 4,684,936 |
| TokenTracker-v1.1.2-macOS.dmg.sha256 | 101 |
| TokenTracker.Windows-v1.1.2-win-x64.zip | 53,725,701 |
| TokenTracker.Windows-v1.1.2-win-x64.zip.sha256 | 107 |
| TokenTracker.Windows-v1.1.2-win-arm64.zip | 51,568,375 |
| TokenTracker.Windows-v1.1.2-win-arm64.zip.sha256 | 109 |

Release lineage on GitHub: v1.0.6 (2026-06-08) → v1.1 (2026-07-06) → **v1.1.2 (Latest)**. No v1.1.1 release exists (that version shipped only as a local build).

Commits: `376ec24` (branch) → rebase-merged as **`088748d`** — "Fall back to the 7d window for forecast and sparkline when a provider's 5h lane is empty" (PR #15, 9 files, +126/−22). CI run on PR: both jobs green first attempt. Release workflow annotations: Node 20 deprecation warnings on actions/checkout@v4, setup-dotnet@v4, upload/download-artifact@v4, softprops/action-gh-release@v2 — informational only, but these actions will need version bumps eventually.

Unused API fields available for the plan's Phase 1 (from live capture, parent + this session): `rate_limit_reset_credits {available_count: 2, applicable_available_count: 0}`, `credits {has_credits: false, balance: "0"}`, `spend_control {reached: false}`, plus `rate_limit.allowed: true, limit_reached: false`.

Session timings and run ids (for cross-referencing GitHub):

| Event | Value |
|---|---|
| PR #15 CI run | `30012650968` — macOS job 1m2s, Windows job 1m15s, both green first attempt |
| Release run | `30017971164` — 4 jobs (macOS DMG / win-x64 / win-arm64 / publish), all success |
| Release published | 2026-07-23T14:56:01Z |
| Local universal build | 5.95s (`APP_ARCHS="arm64 x86_64" bash scripts/build_app.sh`) |
| WinForms macOS compile check | 6.32s, 0 warnings, 0 errors |
| Session span | onboarding ~13:29 KST → close ~24:00 KST (large user-away gaps between approvals; cache timestamps 04:29Z → 14:26Z bracket it) |

Option menu presented mid-session (AskUserQuestion, multi-select) and outcome — records what was OFFERED vs chosen, since unchosen items feed the plan:

| Option | Chosen? | Later status |
|---|---|---|
| 7d fallback (recommended) | **YES** | implemented + shipped this session |
| v1.1.2 release cut | no | requested separately later ("릴리스 컷 진행") — done |
| Surface reset-credits in Diagnostics | no | → PLAN Phase 1 |
| Observe only, close session | no | — |

Deploy command sequence that worked (repeatable):

```bash
APP_ARCHS="arm64 x86_64" bash scripts/build_app.sh
lipo -archs ".build/Token Tracker.app/Contents/MacOS/TokenTrackerMenuBar"   # x86_64 arm64
pkill -x TokenTrackerMenuBar; sleep 1
rm -rf "/Applications/Token Tracker.app" && cp -R ".build/Token Tracker.app" "/Applications/Token Tracker.app"
open "/Applications/Token Tracker.app"
/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" -c "Print :CFBundleVersion" "/Applications/Token Tracker.app/Contents/Info.plist"
pgrep -x TokenTrackerMenuBar | wc -l   # expect 1
```

## Code Analysis

- `DisplayFormatter.preferredForecastWindow(_ usage: ProviderUsage) -> ForecastWindow` (Swift) / `PreferredForecastWindow(ProviderUsage)` (C#): pure, 3-branch; doc comment explains the Codex-since-2026-07 rationale.
- `ForecastWindow.shortLabel: String` (Swift) / `ForecastWindowExtensions.ShortLabel(this ForecastWindow)` (C#): `"5h"` / `"7d"`.
- `UsageForecastText.menuLine(forecast: UsageForecast?, window: ForecastWindow, localizer: Localizer) -> String?`: format = `{forecastLabel}: ~{duration}` + (sevenDay ? ` ({shortLabel})` : ``) + (willEmptyBeforeReset ? ` · {forecastBeforeReset}` : ``).
- `UsageForecaster.durationText`: tiers `<1m` / `{m}m` / `{h}h {m}m` (h<24) / `{d}d {h}h`. Same tier boundaries as `DisplayFormatter.formatReset` (which already had the day tier — they are now format-consistent).
- `UsageForecaster.forecast` nil-conditions (unchanged): <2 points → post-reset segment <2 → span <600s → newest older than 1800s → drop ≤0. Slope is **endpoint-based** (`first.r - last.r` over elapsed) — the plan's Phase 2 (regression smoothing) targets exactly this.
- macOS sparkline window pick: `snapshot.map { … } ?? .fiveHour` (snapshot is `Optional` on AppDelegate); Windows: `snapshot is null ? FiveHour : PreferredForecastWindow(provider == Provider.Claude ? snapshot.Claude : snapshot.Codex)`.
- `usage-cache.json` shape (macOS app): flat `{codex: {…}, claude: {…}, updatedAt}` — NOT nested under `snapshot`.
- `usage-history.json`: array of `{recordedAt, snapshot: {codex: {…}, claude: {…}, updatedAt}}` — history entries DO nest under `snapshot`.
- CI (`ci.yml`) Windows job: Core tests + WinForms `dotnet build` + win-x64 publish smoke. Release (`release.yml`): tag `v*` or workflow_dispatch; APP_BUILD = `github.run_number` (so released build numbers differ from local defaults — expected).
- L10n keys involved (unchanged): `.forecastLabel` EN "Projected depletion" / KO "예상 소진"; `.forecastBeforeReset` EN "empties before reset" / KO "리셋 전 소진".
- **Windows `TrayAppContext` architecture** (read in full this session; relevant to any app-layer C# work): fields include `UsageSnapshot? snapshot`, `deliveredAlertIds` (HashSet<string>, alert dedup), `Localizer` is a computed property re-created per access from `settings.Language`. `RefreshAsync`: skips fetch while paused (but rebuilds menu for the countdown), fetches Claude+Codex in parallel (`Task.WhenAll`), applies `UsageSnapshotCachePolicy.Apply(fresh, cacheStore.Load(TimeSpan.FromHours(1)), claudeEnabled, codexEnabled)`, saves cache, appends history with `settings.HistoryRetentionDays`, `HandleNotifications`, re-renders icon + tooltip, rebuilds menu in `finally`. Timer interval `Math.Max(60, settings.RefreshIntervalSeconds) * 1000`.
- **Windows menu layout** (`AddProvider` dropdown order): Status/issue title + detail (+ recovery), forecast line (indented 2 spaces, only if `settings.ShowForecast`), FiveHourReset, SevenDayReset, Source, TechnicalError (if any), Plan (if any). `HistoryMenu`: trend text → per-provider sparkline lines → `HistoryRetentionDays: {n}d`.
- **Windows `DiagnosticsMenu` contents** (PLAN Phase 1 will extend this + macOS counterpart): CopyDiagnostics (clipboard + balloon tip), separator, OpenClaudeCredentials / OpenCodexAuth (reveal in Explorer), separator, `DuplicateInstances: {count}`, RefreshIntervalWarning when `< 300s`. Backed by `DiagnosticsReporter` (both platforms have one; macOS also has `StatusMenuContext.historyTrendText` etc.).
- **macOS `StatusMenuContext` fields** (menu is rebuilt from this): localizer, settings, snapshot, lastSuccessfulRefreshAt, forecastLines `[Provider: String]`, pausedRemainingText, sparklines `[Provider: String]`, historyTrendText, launchAtLoginEnabled/Status, runningInstanceCount. Forecast/sparkline lines are computed in `AppDelegate` (`forecastLines()`/`sparklines()`), NOT in `StatusMenuBuilder` — the builder just places strings.
- **Sparkline internals** (matters for PLAN Phase 3 / Option B): `SparklineSeries.build(entries:provider:window:maxPoints:20)` — sorts by `recordedAt`, extracts the window's remaining %, and if >20 points, bucket-averages (`start = bucket*count/max`, `end = max(start+1, (bucket+1)*count/max)`). `SparklineText.render` maps 0-100 absolute scale onto 8 Unicode blocks `▁▂▃▄▅▆▇█`, returns `""` for <2 points (which is why an empty lane shows no sparkline row at all).
- **Test fixtures** (reused this session — don't reinvent): Swift `steadyEntries` = claude5h 60/50/40 at −3600/−1800/0 → `steadyForecast` burn 20%/h, secondsToEmpty 7200, willEmptyBeforeReset true (reset +3h); warning fixtures `missingSevenDayUsage` (5h=73,7d=nil), `missingFiveHourUsage` (5h=nil,7d=42). C# `Usage(Provider, int? 5h, int? 7d, DateTimeOffset now, string? plan = null)` helper; **C# `now` is a FIXED date `new DateTimeOffset(2026, 5, 27, …)`** — wall-clock-comparing tests are date-bombs unless stamped with `DateTimeOffset.Now` (see memory file caveat).
- **Tool gotcha**: `gh release view --json isLatest` is invalid (`isLatest` not an available field — use `gh release list` to see the Latest marker; valid fields include isDraft, isImmutable, targetCommitish, assets…).
- **Release pipeline details** (`release.yml`): macOS job re-runs smoke tests before building; DMG via `hdiutil create -fs HFS+ -format UDZO`; sha256 files generated per asset; publish job = `softprops/action-gh-release@v2` with `generate_release_notes: true` + `fail_on_unmatched_files: true`; also supports `workflow_dispatch` with a `version` input (e.g. re-publish without a tag).

## Files Changed

### Source — Core (both platforms)
- `Sources/TokenTrackerCore/UsageForecast.swift` + `windows/TokenTracker.Windows.Core/UsageForecast.cs` — `shortLabel`/`ShortLabel`, durationText days tier, `menuLine`/`MenuLine` window param + `(7d)` marker, alert label refactor.
- `Sources/TokenTrackerCore/DisplayFormatter.swift` + `…Core/DisplayFormatter.cs` — `preferredForecastWindow`/`PreferredForecastWindow`.

### Source — apps
- `Sources/TokenTrackerMenuBar/AppDelegate.swift` — `forecastLines()` + `sparklines()` use the preferred window, matching reset, dynamic label.
- `windows/TokenTracker.Windows/TrayAppContext.cs` — `AddProvider` forecast block + `HistoryMenu` sparkline block mirrored.

### Tests
- `Sources/TokenTrackerSmokeTests/main.swift` + `windows/TokenTracker.Windows.Tests/Program.cs` — truth table, menu-line pinning (5h unchanged / 7d marked / nil), duration days tier.

### Build / docs / memory
- `scripts/build_app.sh` — defaults 1.1.2 / 4.
- `~/.claude/projects/-Users-jkl-Projects-Token-tracker/memory/local-verification.md` — WinForms macOS compile-check (`-p:EnableWindowsTargeting=true`) replaces "cannot compile on macOS" (outside repo, not committed).
- `plans/handoffs/HANDOFF_usage-insights_codex-7d-fallback_2026-07-23.md` + `PLAN_usage-insights_codex-7d-fallback_2026-07-23.md` — this handoff + paired plan.

## User Feedback & Preferences (REQUIRED — never omit)

- **Session opener (structured onboarding demand)**: read the handoff and "narrate your onboarding" in 4 numbered steps — summarize understanding, state verification plan, read key files **plus 2-3 adjacent files not listed** ("the handoff captures what the previous session focused on, not everything that matters"), explain first action — "**Then wait for my go-ahead before executing.**" This is a stronger, more explicit onboarding contract than the parent session's one-liner; expect it again.
- **"진행해"** — one-word go-ahead after the onboarding report; expects autonomous execution of the stated plan.
- **Option-menu answer: "7d 폴백 구현 (추천)" only** — user picked a single item even with multi-select available; the release cut was NOT selected then but requested later ("릴리스 컷 진행") — i.e., the user sequences work explicitly rather than batching; don't assume unselected options are rejected forever.
- **"머지 해줘"** — explicit merge directive; `gh pr merge` succeeded under it (vs. classifier-blocked in the parent session without a directive). Updated merge playbook: prepare PR → report → on explicit user merge request, run `gh pr merge {n} --rebase --delete-branch` directly; keep the `!` fallback only if it blocks again.
- **"릴리스 컷 진행"** — release approval; expects the tag-push flow reported in the previous turn to just happen and be verified.
- **"/handoffplan"** — close the session with a handoff + executable plan for the next session.
- Standing (inherited, honored): macOS⇄Windows parity mandatory; Korean-facing replies with English code/docs/artifacts; CI-equivalent checks locally before PR; branch+PR only (protected `main`); rebase-merge for linear history; never pipe a gate's exit code (self-caught once this session on `gh run watch | tail` and re-verified properly); proactive honesty when something is off.

## Where We're Going

See the paired `PLAN_usage-insights_codex-7d-fallback_2026-07-23.md` for full phasing. Summary:

1. **Phase 1 — Surface Codex account signals in Diagnostics**: `rate_limit_reset_credits.available_count`, `credits.balance`, `spend_control.reached` (field shapes already captured; zero extra API calls).
2. **Phase 2 — Forecast regression smoothing** (carried from grandparent): replace endpoint slope with least-squares over the post-reset segment, both platforms.
3. **Phase 3 — Sparkline Option B (bitmap)**: design in `plans/FEATURE_PLAN_usage-insights-and-controls_2026-07-06.md`; decide-then-implement.
4. **Standing watch**: has OpenAI restored the 5h window? (Quick Start has the probe; no code change needed either way — verify lanes repopulate.)
5. **Deferred/blocked**: macOS signing/notarization (needs Apple Developer decision from user); Windows `UsageSource.LocalLog` divergence; WinForms runtime smoke on a real Windows machine.

## Risks & Blockers

- **WinForms has STILL never been executed** — compile-verified (now locally too) + parity-by-construction only. The Codex 7d menu line/sparkline on Windows are untested at runtime.
- **The live forecast's "before reset" suffix is currently TRUE for Codex** (ETA ~5d 4h < reset in ~6d) — the 7d depletion alert may legitimately fire in the coming days. Not a bug; but if the user reports an unexpected notification, this is why.
- **Codex 7d burn estimate is endpoint-based and young** (11h of data on a 7-day window) — the ETA will swing with usage spikes until more history accumulates; Phase 2 (regression) will damp this.
- **OpenAI may restore the 5h window or change shapes again** — mapper self-heals by length; the fallback self-heals back to 5h (surfaces flip automatically when `remainingPercent5h` reports).
- **Release workflow actions pin Node-20-deprecated versions** (checkout@v4 etc.) — informational warnings today; will eventually need bumps.
- **dotnet is session-scoped** — re-bootstrap per session (two-step; in memory file).

## Open Questions

- Will OpenAI restore the 5h window, and with what `limit_window_seconds`? (Any value <86400 lands in the 5h lane automatically.)
- Should the menu also show a forecast for the 7d window even when 5h is present (two lines per provider)? Current design: one line, preferred window only. Revisit only if the user asks.
- Parent's `dist/` old-DMG disappearance — still unexplained, still harmless.

## Quick Start for Next Session

```bash
# Restore context
cd "/Users/jkl/Projects/Token tracker" && git status -sb && git log --oneline -5
# expect: main @ 088748d (or later), clean

# This handoff + the plan to execute
sed -n '1,120p' plans/handoffs/HANDOFF_usage-insights_codex-7d-fallback_2026-07-23.md
cat plans/handoffs/PLAN_usage-insights_codex-7d-fallback_2026-07-23.md

# Key files for the plan's Phase 1 (Diagnostics surfacing)
grep -n "plan_type\|rate_limit" Sources/TokenTrackerCore/CodexWindowMapper.swift
sed -n '1,60p' Sources/TokenTrackerMenuBar/DiagnosticsReporter.swift
sed -n '1,60p' windows/TokenTracker.Windows/DiagnosticsReporter.cs

# Verify current state — macOS
swift build && swift run TokenTrackerSmokeTests

# Verify — Windows (bootstrap dotnet fresh each session; then Core tests + WinForms compile check)
S="<this session's scratchpad>"; curl -fsSL https://dot.net/v1/dotnet-install.sh -o "$S/di.sh" && bash "$S/di.sh" --channel 10.0 --install-dir "$S/dotnet"
"$S/dotnet/dotnet" run --project windows/TokenTracker.Windows.Tests/TokenTracker.Windows.Tests.csproj
"$S/dotnet/dotnet" build windows/TokenTracker.Windows/TokenTracker.Windows.csproj -p:EnableWindowsTargeting=true

# Standing watch: has the Codex 5h window returned?
python3 - <<'EOF'
import json,urllib.request
a=json.load(open('/Users/jkl/.codex/auth.json'))['tokens']
r=urllib.request.Request('https://chatgpt.com/backend-api/wham/usage',headers={'Authorization':f"Bearer {a['access_token']}",'ChatGPT-Account-Id':a['account_id'],'User-Agent':'TokenTrackerMenuBar/1.0'})
d=json.load(urllib.request.urlopen(r,timeout=15))
rl=d.get('rate_limit') or {}
print({k:(v if not isinstance(v,dict) else {kk:v.get(kk) for kk in('used_percent','limit_window_seconds','reset_at')}) for k,v in rl.items()})
print('reset_credits:',d.get('rate_limit_reset_credits'),'credits:',d.get('credits'),'spend:',d.get('spend_control'))
EOF

# Verify the installed app (expect 1.1.2 / 4)
/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" -c "Print :CFBundleVersion" "/Applications/Token Tracker.app/Contents/Info.plist"

# Next action
# Execute PLAN Phase 1: add Codex reset-credits/credits/spend_control to the parsed
# model + Diagnostics text on both platforms (fields shapes are in this handoff's
# Evidence section — no new API calls needed).
```

## Session Closed

**Closed at:** 2026-07-23 ~24:00 KST
**Branch:** handoff + plan committed via `handoff/codex-7d-fallback-2026-07-23` (branch-protected `main` — PR merge)
**Session status:** Handed off to next session (plan-driven)
