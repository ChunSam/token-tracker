# Windows parity for macOS diagnostics, alerts, history, and preferences UX

**Date:** 2026-06-22
**Status:** IN PROGRESS
**Bead(s):** none
**Epic:** Token Tracker usage UX hardening
**Chain:** `macos-usage-ux` seq `2`
**Parent:** `HANDOFF_macos-usage-ux_diagnostics-alerts-history_2026-06-15.md`
**Prior chain:** `HANDOFF_macos-usage-ux_diagnostics-alerts-history_2026-06-15.md` > this

---

## Related Handoffs

- `HANDOFF_macos-menubar-refactor_appdelegate-modularization_2026-06-15.md` - related macOS modularization after diagnostics, alerts, history, and preferences were added.
- `HANDOFF_platform-optimization_macos-windows-hardening_2026-06-09.md` - related Windows stale cache, Claude 429 cooldown, plan fallback, and win-arm64 packaging context.
- `HANDOFF_m4-menubar-stability_provider-controls-stable-width_2026-06-15.md` - related provider controls, refresh interval, and status/menu parity context.
- `HANDOFF_m4-menubar-stability_refresh-width-fix_2026-06-09.md` - earlier M4 menu bar disappearance investigation and first stable-width fix.

## Since Last Handoff

- Parent seq 1 added macOS diagnostics, status/recovery text, notification alerts, local history, CSV export, and a native Preferences window.
- Parent seq 1 explicitly left Windows parity as a future action: adding equivalent diagnostics/history UX to the Windows tray app if parity became important.
- The user later asked to keep the macOS updates consistent on Windows: `mac os 업데이트 사항 windows에도 통일성 있게 진행`.
- This session implemented the matching Windows features in native WinForms/C# rather than trying to share AppKit-specific UI code.
- Windows now has equivalents for issue classification, diagnostics copy/recovery actions, usage alerts, history persistence, CSV export, and a settings window.
- The Windows tray dropdown was shortened so configuration-heavy controls live under `Preferences...`, matching the macOS menu cleanup direction.
- Swift validation still passes after the Windows work, but Windows compile/tests remain blocked locally because this Mac does not have `dotnet`.
- The trajectory remains on the parent feature path, but status is `IN PROGRESS` until a Windows/.NET environment compiles and runs the C# tests.

## Reference Documents

- `README.md` - user-facing cross-platform feature list, menu/tray behavior, and development commands.
- `WORK_SUMMARY.md` - older project behavior summary for token usage display and provider details.
- `agent.md` - local behavior notes around display modes, provider labels, and menu contents.
- `SECURITY_AUDIT.md` - prior release/security hardening context, especially around not exposing credential contents.

## The Goal

The user wanted Windows to receive the same functional UX improvements that had already landed on macOS.
The practical goal is a consistent app experience across the macOS menu bar and Windows system tray: users should see understandable provider status, recovery guidance, diagnostics, alerts, history, CSV export, and centralized settings on both platforms.
The work intentionally excludes paid/Pro monetization features because the user postponed those earlier.
The remaining handoff risk is validation: the Windows source was updated and reviewed, but local compilation cannot run until a .NET SDK is available.

## Where We Are

- Current branch at handoff creation: `main`.
- Remote `origin/main` was checked before commit work and matched local `HEAD` at `5d65c94ea2cfa03eebbddddd44a459c3321d5f71`.
- Latest committed base before this Windows parity work: `5d65c94 Refactor macOS menu bar app delegate`.
- The working tree before this handoff had 6 modified tracked files and 5 new Windows source files.
- `README.md` now describes Token Tracker as a macOS menu bar and Windows system tray app.
- `README.md` now marks diagnostics, alerts, local history, CSV export, and the settings window as macOS/Windows features.
- `windows/TokenTracker.Windows.Core/AppPaths.cs` now exposes `UsageHistoryPath`.
- `windows/TokenTracker.Windows.Core/SettingsStore.cs` now persists notification and history settings.
- New default Windows settings are notifications off, 5h alert threshold `20`, 7d alert threshold `10`, reset alert window `10` minutes, and history retention `7` days.
- `windows/TokenTracker.Windows.Core/Localizer.cs` has expanded English and Korean strings for preferences, diagnostics, status/recovery, notifications, history, thresholds, and CSV export.
- `windows/TokenTracker.Windows.Core/UsageIssueFormatter.cs` was added.
- `UsageIssueFormatter.Kind(...)` classifies disabled providers, HTTP 429/rate limit, missing credentials, invalid response, timeout, network error, generic HTTP, stale cache, and unavailable states.
- `UsageIssueFormatter.Issue(...)` returns a user-facing title/detail/recovery plus technical detail.
- `windows/TokenTracker.Windows.Core/UsageAlertEvaluator.cs` was added.
- `UsageAlertEvaluator.Candidates(...)` emits alert candidates for low 5h usage, low 7d usage, and reset-soon warnings.
- Alert candidate IDs are stable strings such as `claude-5h-low`, `claude-7d-low`, and `claude-5h-reset-{unix}`.
- `UsageSnapshotExtensions.Usage(provider)` and `Provider.ToId()` were added for alert/history formatting.
- `windows/TokenTracker.Windows.Core/UsageHistoryStore.cs` was added.
- `UsageHistoryStore` persists JSON history at `AppPaths.UsageHistoryPath`.
- `UsageHistoryStore.Append(...)` merges entries inside a one-minute window and prunes entries outside retention days.
- `UsageHistoryFormatter.TrendSummary(...)` generates a 24h 5h-remaining delta summary.
- `UsageHistoryFormatter.CsvString(...)` exports provider rows with header `recorded_at,provider,remaining_5h,remaining_7d,reset_5h,reset_7d,source,plan,error`.
- `windows/TokenTracker.Windows/DiagnosticsReporter.cs` was added.
- `DiagnosticsReporter.DiagnosticsText()` includes app version, OS, architecture, settings, history count/trend, last successful update, running instance count, credential/auth file existence, and per-provider diagnostics.
- Diagnostics intentionally report credential/auth file existence only; they do not read token contents.
- `windows/TokenTracker.Windows/SettingsForm.cs` was added as a native WinForms settings window.
- `SettingsForm` exposes provider toggles, display mode, provider label style, refresh interval, language, notifications, alert thresholds, reset warning window, and history retention.
- `windows/TokenTracker.Windows/TrayAppContext.cs` now owns `UsageHistoryStore`, notification alert dedupe, last successful refresh tracking, and a reusable `SettingsForm`.
- `TrayAppContext.RefreshAsync()` appends history and evaluates notifications after applying stale cache and before updating the icon/tooltip.
- `TrayAppContext` now records `lastSuccessfulRefreshAt` when either provider snapshot comes from `UsageSource.Api`.
- The Windows tray dropdown is now shorter: provider details, updated time, last successful update, refresh, preferences, diagnostics, history, launch at login, always-show icon settings, quit.
- The old inline Windows settings submenus were removed from `TrayAppContext`: display mode, provider label style, provider toggles, refresh interval, and language now live in `SettingsForm`.
- The diagnostics menu includes copy diagnostics, open Claude credentials, open Codex auth, running instance count, and refresh interval warning when interval is under 60 seconds.
- The history menu includes trend text, retention days, and `Export History CSV...`.
- CSV export uses `SaveFileDialog` and writes the current history CSV to the user-selected path.
- Notifications use `NotifyIcon.ShowBalloonTip(...)` with in-memory delivered-alert ID dedupe.
- `windows/TokenTracker.Windows.Tests/Program.cs` now includes intended coverage for issue classification, stale-cache issue details, alert candidates, disabled notifications, history load/append, trend summary, CSV output, Korean diagnostics labels, and settings persistence.
- `RunningInstanceCount()` now disposes the `Process` objects returned by `Process.GetProcessesByName(...)`.
- A compile-risky positional record customization in `UsageAlertSettings` was refactored to an explicit constructor and read-only properties.
- `git diff --check` passed after the Windows parity changes.
- `swift build` passed after the Windows parity changes.
- `swift run TokenTrackerSmokeTests` passed after the Windows parity changes and printed `TokenTrackerSmokeTests passed`.
- `dotnet run --project windows/TokenTracker.Windows.Tests/TokenTracker.Windows.Tests.csproj` failed locally with `zsh:1: command not found: dotnet`.
- `which dotnet` also returned `dotnet not found`.
- Search confirmed the old inline settings menu helpers are gone from `TrayAppContext.cs`.

## What We Tried (Chronological)

1. The user asked to apply macOS update items consistently to Windows.
2. Reviewed the parent macOS usage UX handoff and confirmed its future direction named Windows parity as a likely follow-up.
3. Reviewed the macOS modularization handoff to understand the post-refactor ownership split between menu building, diagnostics, notifications, and status rendering.
4. Reviewed the platform optimization handoff because it contains the earlier Windows stale cache and 429 cooldown context.
5. Checked current git state; branch was `main` with no new remote commits beyond local `HEAD`.
6. Added Windows local history support by introducing `UsageHistoryStore`, `UsageHistoryEntry`, and `UsageHistoryFormatter`.
7. Added `AppPaths.UsageHistoryPath` under the existing app data directory convention.
8. Added Windows status/recovery classification through `UsageIssueFormatter`.
9. Mirrored macOS issue kinds in Windows without exposing token contents or credential contents.
10. Added Windows notification settings to `AppSettings`.
11. Added `UsageAlertEvaluator` with pure candidate generation so tests can exercise alert behavior without Windows UI automation.
12. Added Windows diagnostics reporting through `DiagnosticsReporter`.
13. Added provider snapshot lines to diagnostics, including remaining percent, reset time, source, status kind, plan, and technical error.
14. Added a native `SettingsForm` to centralize controls that had been making the tray menu too long.
15. Reworked `TrayAppContext.BuildMenu()` into a compact operational tray menu.
16. Removed obsolete inline tray settings menus for display mode, provider labels, providers, refresh interval, and language.
17. Connected `SettingsForm` callbacks to save settings, rebuild the menu, redraw the tray icon, reschedule the timer, and refresh provider data when provider toggles change.
18. Added `History` menu support with trend summary, retention display, and CSV export.
19. Added `Diagnostics` menu support with copy diagnostics and auth/credential reveal actions.
20. Added in-memory notification dedupe in `TrayAppContext.HandleNotifications(...)`.
21. Updated README so Windows is described alongside macOS for the newly matching features.
22. Extended the Windows smoke-test program with intended tests for new core behavior and settings persistence.
23. Ran `git diff --check`; it passed with no whitespace errors.
24. Ran `rg` against old settings menu helper names in `TrayAppContext.cs`; it returned no matches.
25. Ran `swift build`; it passed, confirming macOS/shared Swift code was not regressed by documentation or repository state.
26. Ran `swift run TokenTrackerSmokeTests`; it passed.
27. Tried `dotnet run --project windows/TokenTracker.Windows.Tests/TokenTracker.Windows.Tests.csproj`; it failed because `dotnet` is not installed on this Mac.
28. Re-read the handoff skill and Deep handoff reference files.
29. Collected branch, status, diff stat, recent log, existing handoffs, parent handoff context, and remote main hash.
30. Created this handoff before staging so the continuity document is included in the requested commit/push.

## Key Decisions

- Used the existing `macos-usage-ux` chain as seq 2 because parent seq 1 explicitly left Windows parity as the next likely step.
- Kept the handoff status as `IN PROGRESS` because the Windows code cannot be compiled or tested locally without a .NET SDK.
- Implemented Windows UI with WinForms, matching the existing Windows app stack instead of trying to share macOS AppKit controllers.
- Kept notification default off, matching macOS behavior and avoiding noisy first-run behavior.
- Put settings in a dedicated settings window to keep the tray menu operational and short.
- Preserved `Always Show Icon Settings...` in the Windows tray menu because it is platform-specific and still important for tray visibility.
- Used `NotifyIcon.ShowBalloonTip(...)` for alerts because the app already runs as a Windows tray app and no new notification dependency is needed.
- Stored history as JSON in the existing app data directory and exported CSV only by explicit user action.
- Kept diagnostics credential-safe: file existence checks are allowed, credential contents are not read or copied.
- Kept alert dedupe in memory, not persisted, because this matches the macOS first-pass behavior and avoids another persistence file.
- Added core-level formatters/evaluators so behavior can be tested outside the WinForms tray app once .NET is available.
- Did not install `.NET` during this session; the environment blocker is documented instead.
- Did not touch paid purchase/non-purchase gating because the user postponed monetized features.

## Evidence & Data

| Git item | Value |
| --- | --- |
| Branch | `main` |
| Local `HEAD` before commit | `5d65c94ea2cfa03eebbddddd44a459c3321d5f71` |
| Remote `origin/main` before commit | `5d65c94ea2cfa03eebbddddd44a459c3321d5f71` |
| Latest commit | `5d65c94 Refactor macOS menu bar app delegate` |
| Dirty tracked files before handoff | 6 |
| New untracked Windows files before handoff | 5 |

| Changed area | Files |
| --- | ---: |
| README/docs | 1 |
| Windows Core modified | 4 |
| Windows Core new | 3 |
| Windows tray app modified | 1 |
| Windows tray app new | 2 |
| Windows tests modified | 1 |
| Handoff added | 1 |

| File | Current line count |
| --- | ---: |
| `windows/TokenTracker.Windows.Core/UsageAlertEvaluator.cs` | 136 |
| `windows/TokenTracker.Windows.Core/UsageHistoryStore.cs` | 178 |
| `windows/TokenTracker.Windows.Core/UsageIssueFormatter.cs` | 158 |
| `windows/TokenTracker.Windows/DiagnosticsReporter.cs` | 118 |
| `windows/TokenTracker.Windows/SettingsForm.cs` | 280 |
| `windows/TokenTracker.Windows/TrayAppContext.cs` | 462 |
| `windows/TokenTracker.Windows.Tests/Program.cs` | 284 |
| `windows/TokenTracker.Windows.Core/Localizer.cs` | 280 |

| Validation command | Result |
| --- | --- |
| `git diff --check` | passed, no output |
| `rg "DisplayModeMenu|ProviderLabelStyleMenu|ProvidersMenu|RefreshIntervalMenu|LanguageMenu|ProviderToggleItem|DisplayModeLabel\\(" windows/TokenTracker.Windows/TrayAppContext.cs` | no matches, exit 1 |
| `swift build` | passed, `Build complete! (0.17s)` |
| `swift run TokenTrackerSmokeTests` | passed, `TokenTrackerSmokeTests passed` |
| `which dotnet` | `dotnet not found`, exit 1 |
| `dotnet run --project windows/TokenTracker.Windows.Tests/TokenTracker.Windows.Tests.csproj` | `zsh:1: command not found: dotnet`, exit 127 |

| Windows parity feature | macOS parent equivalent | Windows implementation |
| --- | --- | --- |
| Status/recovery issue text | `UsageIssueFormatter.swift` | `UsageIssueFormatter.cs` |
| Low-usage/reset alerts | `UsageAlertEvaluator.swift` + `UserNotifications` | `UsageAlertEvaluator.cs` + `NotifyIcon.ShowBalloonTip` |
| Local history | `UsageHistoryStore.swift` | `UsageHistoryStore.cs` |
| CSV export | `NSSavePanel` action | `SaveFileDialog` action |
| Diagnostics report | `DiagnosticsReporter.swift` after refactor | `DiagnosticsReporter.cs` |
| Preferences window | `PreferencesWindowController.swift` | `SettingsForm.cs` |
| Short operational menu | `StatusMenuBuilder.swift` | compact `TrayAppContext.BuildMenu()` |

Current `git status -s` before adding this handoff:

```text
 M README.md
 M windows/TokenTracker.Windows.Core/AppPaths.cs
 M windows/TokenTracker.Windows.Core/Localizer.cs
 M windows/TokenTracker.Windows.Core/SettingsStore.cs
 M windows/TokenTracker.Windows.Tests/Program.cs
 M windows/TokenTracker.Windows/TrayAppContext.cs
?? windows/TokenTracker.Windows.Core/UsageAlertEvaluator.cs
?? windows/TokenTracker.Windows.Core/UsageHistoryStore.cs
?? windows/TokenTracker.Windows.Core/UsageIssueFormatter.cs
?? windows/TokenTracker.Windows/DiagnosticsReporter.cs
?? windows/TokenTracker.Windows/SettingsForm.cs
```

Tracked diff stat before adding this handoff:

```text
 README.md                                          |  14 +-
 windows/TokenTracker.Windows.Core/AppPaths.cs      |   3 +
 windows/TokenTracker.Windows.Core/Localizer.cs     | 168 +++++++++++++-
 windows/TokenTracker.Windows.Core/SettingsStore.cs |   5 +
 windows/TokenTracker.Windows.Tests/Program.cs      |  64 +++++-
 windows/TokenTracker.Windows/TrayAppContext.cs     | 253 ++++++++++++---------
 6 files changed, 387 insertions(+), 120 deletions(-)
```

Recent commit context:

```text
5d65c94 Refactor macOS menu bar app delegate
89d8db5 Add macOS diagnostics alerts history preferences
210c36c Add macOS provider controls and stable status width
d304a12 Fix menu bar refresh visibility
3a61da4 Optimize macOS and Windows platform handling
099e506 Fix release Swift concurrency checks
160c45d Prepare v1.0.6 release
c89e86f Improve Claude usage fetch diagnostics
```

Windows test project target:

```text
TargetFramework: net10.0
LangVersion: latest
Nullable: enable
```

Windows app project target:

```text
TargetFramework: net10.0-windows10.0.17763.0
UseWindowsForms: true
RuntimeIdentifiers: win-x64;win-arm64
```

Key persisted settings added:

```text
NotificationsEnabled = false
FiveHourAlertThreshold = 20
SevenDayAlertThreshold = 10
ResetAlertMinutes = 10
HistoryRetentionDays = 7
```

CSV header verified by intended Windows test:

```text
recorded_at,provider,remaining_5h,remaining_7d,reset_5h,reset_7d,source,plan,error
```

## Code Analysis

- `UsageIssueFormatter` is a pure core formatter and does not depend on WinForms.
- `UsageIssueFormatter` intentionally classifies by error text because current provider clients return errors as strings on `ProviderUsage`.
- `UsageIssueFormatter.Issue(...)` treats `UsageSource.StaleCache` as cached-data status while preserving the underlying technical error.
- `UsageAlertEvaluator.Candidates(...)` is pure with injectable `now` and `Localizer`, so it can be tested deterministically.
- `UsageAlertSettings` now clamps thresholds in an explicit constructor to reduce record-synthesis compile risk.
- `UsageHistoryStore.Load()` returns empty history on missing or unreadable files, matching the app's resilient local-cache pattern.
- `UsageHistoryStore.Append(...)` replaces sub-minute duplicate entries to avoid noisy history when manual refreshes happen quickly.
- `UsageHistoryFormatter.TrendSummary(...)` compares 5h remaining percent between the first entry inside the 24h window and the current snapshot.
- `UsageHistoryFormatter.CsvString(...)` escapes commas, quotes, and newlines for CSV cells.
- `DiagnosticsReporter` owns diagnostics generation instead of leaving that text assembly in `TrayAppContext`.
- `DiagnosticsReporter` exposes static credential/auth paths so tray menu reveal actions share the same paths as diagnostics.
- `SettingsForm` directly mutates the shared `AppSettings` object and calls callbacks; this matches the existing lightweight WinForms app style.
- `TrayAppContext.RefreshAsync()` still coordinates provider fetch, stale cache, icon/tooltip update, and menu rebuild because it is the tray application context.
- `TrayAppContext.BuildMenu()` now focuses on operational items instead of duplicating every setting in the tray dropdown.
- `RunningInstanceCount()` now disposes returned process handles after counting.
- No Windows service layer abstraction was added in this pass; the feature is still small enough to keep directly wired through existing classes.

## Files Changed

### Source code

- `windows/TokenTracker.Windows.Core/AppPaths.cs` - added `UsageHistoryPath` for persisted Windows usage history.
- `windows/TokenTracker.Windows.Core/SettingsStore.cs` - added notification threshold and history retention settings.
- `windows/TokenTracker.Windows.Core/Localizer.cs` - added English/Korean labels for preferences, diagnostics, status/recovery, notifications, history, and CSV export.
- `windows/TokenTracker.Windows.Core/UsageIssueFormatter.cs` - new provider issue classifier and localized status/recovery formatter.
- `windows/TokenTracker.Windows.Core/UsageAlertEvaluator.cs` - new low-usage/reset alert candidate evaluator plus provider/snapshot helpers.
- `windows/TokenTracker.Windows.Core/UsageHistoryStore.cs` - new JSON history store, trend summary, and CSV formatter.
- `windows/TokenTracker.Windows/DiagnosticsReporter.cs` - new diagnostics text and history trend reporter for the Windows tray app.
- `windows/TokenTracker.Windows/SettingsForm.cs` - new native WinForms settings window for provider, display, refresh, language, alert, and history controls.
- `windows/TokenTracker.Windows/TrayAppContext.cs` - integrated settings window, diagnostics menu, history menu/export, notification handling, last-success tracking, compact tray menu, and process-count cleanup.

### Tests

- `windows/TokenTracker.Windows.Tests/Program.cs` - added intended tests for issue classification, stale-cache issue detail, alert candidates, disabled alerts, history store behavior, trend summary, CSV output, Korean diagnostics labels, and settings persistence.

### Documentation

- `README.md` - updated feature/menu descriptions so Windows is listed consistently with macOS for diagnostics, alerts, history, CSV export, and settings.

### Handoffs

- `plans/handoffs/HANDOFF_macos-usage-ux_windows-parity_2026-06-22.md` - this continuity document.

### Generated artifacts

- `.build/` content may have been refreshed by Swift validation, but generated build output is not intended to be committed.

## User Feedback & Preferences (REQUIRED - never omit)

- User communicates in Korean.
- User wants direct execution once the scope is clear.
- User asked not to receive mid-progress reports for the earlier implementation series and wanted only completed work summarized.
- User reported an M4 menu bar disappearance symptom where the process stayed alive.
- User asked to check whether another worker had pushed to Git.
- User asked to inspect functionally missing or improvable project areas.
- User chose to postpone money-making/paid features for now.
- User wanted non-monetized recommendation items implemented first.
- User asked to restart the modified process and do real-use validation for the macOS work.
- User noticed settings-related menu contents made the menu/dropdown too long and asked to move/remove them.
- User asked to review modularization from an object-oriented perspective.
- User accepted decomposing the large macOS app delegate.
- User asked to keep Windows consistent with the macOS update items.
- User explicitly requested `[$handoff] ... 하고 푸시`.
- User expects handoff and push after implementation phases.

## Where We're Going

- Stage the Windows parity source/docs/tests plus this handoff file.
- Commit with a message describing Windows tray parity with macOS usage UX.
- Push `main` to `origin`.
- On a Windows machine or CI runner with .NET 10 installed, run the Windows test project.
- If compile errors appear in C# or WinForms wiring, fix them in a follow-up commit.
- After .NET tests pass, manually run the Windows tray app and click through Preferences, Diagnostics, History CSV export, provider toggles, and notification settings.
- If Windows notification UX is too limited with balloon tips, consider a future native toast implementation.

## Risks & Blockers

- Local machine does not have `dotnet`, so Windows compile/tests could not run here.
- WinForms tray UI was not manually launched in a Windows desktop session from this Mac environment.
- `SettingsForm` localizes labels at creation time; switching language may require reopening the settings window to relabel controls.
- Balloon notifications can behave differently depending on Windows notification/tray settings.
- Alert dedupe is in-memory; restarting the app can allow an unchanged active alert to show again.
- History files are stored locally as JSON without encryption, but they contain usage percentages/source/errors only, not tokens.

## Open Questions

- Does the Windows project compile cleanly under .NET 10 after these changes?
- Should Windows settings relabel live immediately after language change, or is reopening Preferences acceptable?
- Should Windows alert dedupe persist across restarts later?
- Should diagnostics include a one-click issue report template in both macOS and Windows?
- Should Windows eventually use native toast notifications rather than tray balloon tips?

## Quick Start for Next Session

```bash
# Current handoff
sed -n '1,380p' plans/handoffs/HANDOFF_macos-usage-ux_windows-parity_2026-06-22.md

# Parent context
sed -n '1,380p' plans/handoffs/HANDOFF_macos-usage-ux_diagnostics-alerts-history_2026-06-15.md

# Related architecture context
sed -n '1,360p' plans/handoffs/HANDOFF_macos-menubar-refactor_appdelegate-modularization_2026-06-15.md
sed -n '1,360p' plans/handoffs/HANDOFF_platform-optimization_macos-windows-hardening_2026-06-09.md

# Key Windows files to read first
sed -n '1,520p' windows/TokenTracker.Windows/TrayAppContext.cs
sed -n '1,320p' windows/TokenTracker.Windows/SettingsForm.cs
sed -n '1,220p' windows/TokenTracker.Windows/DiagnosticsReporter.cs
sed -n '1,220p' windows/TokenTracker.Windows.Core/UsageIssueFormatter.cs
sed -n '1,240p' windows/TokenTracker.Windows.Core/UsageAlertEvaluator.cs
sed -n '1,240p' windows/TokenTracker.Windows.Core/UsageHistoryStore.cs

# Verify current state on macOS
git status --short --branch
git diff --check
swift build
swift run TokenTrackerSmokeTests

# Verify current state on Windows or CI with .NET 10
dotnet run --project windows/TokenTracker.Windows.Tests/TokenTracker.Windows.Tests.csproj
dotnet publish windows/TokenTracker.Windows/TokenTracker.Windows.csproj -c Release -r win-x64 --self-contained true /p:PublishSingleFile=true /p:PublishReadyToRun=false
dotnet publish windows/TokenTracker.Windows/TokenTracker.Windows.csproj -c Release -r win-arm64 --self-contained true /p:PublishSingleFile=true /p:PublishReadyToRun=false

# Next action
# Run the Windows tests on a .NET 10 machine, then manually verify tray Preferences, Diagnostics, History CSV export, and balloon alerts.
```
