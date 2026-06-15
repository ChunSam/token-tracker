# macOS diagnostics, alerts, history, and preferences UX

**Date:** 2026-06-15
**Status:** COMPLETED
**Bead(s):** none
**Epic:** Token Tracker usage UX hardening
**Chain:** `macos-usage-ux` seq `1`
**Parent:** none - first in chain
**Prior chain:** none - first in chain

---

## Related Handoffs

- `HANDOFF_m4-menubar-stability_provider-controls-stable-width_2026-06-15.md` - immediately prior pushed work that added macOS provider controls, refresh interval controls, and stable status width.
- `HANDOFF_m4-menubar-stability_refresh-width-fix_2026-06-09.md` - earlier M4 menu bar disappearance investigation and first refresh-width fix.
- `HANDOFF_claude-usage-stability_429-cooldown-plan_2026-06-06.md` - related Claude 429/cooldown context that informed this session's error UX.
- `HANDOFF_platform-optimization_macos-windows-hardening_2026-06-09.md` - related cross-platform tray/menu behavior context.

## Reference Documents

- `README.md` - updated user-facing feature list and development commands.
- `WORK_SUMMARY.md` - older project summary and intended menu behavior.
- `agent.md` - project behavior notes and menu display rules.
- `SECURITY_AUDIT.md` - prior security hardening context.

## The Goal

The user wanted to postpone paid/Pro functionality and implement the non-monetized recommendations numbered 2 through 6 from the functional review.
The requested flow was strict: set a detailed plan for each implementation phase, define its completion point, complete that point, then move to the next phase.
The final phase required full validation, a handoff document, commit, and push if validation was clean.
The user later clarified they did not want mid-progress status reports and only wanted the completed work summarized at the end.

## Where We Are

- Branch at handoff creation: `main`.
- Base commit before this work: `210c36c Add macOS provider controls and stable status width`.
- The work targets the macOS app and shared Swift core; Windows C# code was not changed in this session.
- `Sources/TokenTrackerCore/UsageIssueFormatter.swift` was added.
- `UsageIssueFormatter.kind(forError:)` classifies disabled, HTTP 429, missing credentials, invalid response, timeout, network, generic HTTP, and unavailable states.
- `UsageIssueFormatter.issue(for:localizer:)` returns user-facing title/detail/recovery plus the technical error string.
- `Sources/TokenTrackerMenuBar/AppDelegate.swift` now displays provider `Status`, detail, `Recovery`, and `Technical error` instead of only raw `Error`.
- `AppDelegate` now has a `Diagnostics` submenu.
- `Diagnostics` includes `Copy Diagnostics`, `Open Claude Credentials`, and `Open Codex Auth`.
- Copied diagnostics include app version/build, bundle id, macOS version, architecture, display settings, provider enabled flags, notification settings, history count, snapshot values, and file-existence checks.
- Diagnostics intentionally do not read or copy token contents from credential files.
- `AppDelegate` tracks `lastSuccessfulRefreshAt` when either provider returns `.api`.
- `Diagnostics` shows running instance count via `NSRunningApplication.runningApplications(withBundleIdentifier:)`.
- A short refresh interval warning appears when the refresh interval is under 60 seconds.
- `Sources/TokenTrackerCore/UsageAlertEvaluator.swift` was added.
- Notifications are controlled by `Settings.notificationsEnabled`, default false.
- Low 5h threshold default is `20`.
- Low 7d threshold default is `10`.
- Reset warning window default is `10` minutes.
- `UsageAlertEvaluator.candidates(...)` returns low-usage and reset-soon alert candidates.
- `AppDelegate` sends local macOS notifications through `UserNotifications`.
- `AppDelegate.deliveredAlertIDs` prevents repeated alerts while the same alert condition remains active.
- The `Notifications` menu shows enabled state and current thresholds.
- `Sources/TokenTrackerCore/UsageHistoryStore.swift` was added.
- `UsageHistoryStore` persists snapshots to `Application Support/Token Tracker/usage-history.json`.
- History file writes use owner-only `0o600` permissions, matching cache privacy style.
- History retention default is `7` days via `Settings.historyRetentionDays`.
- `UsageHistoryStore.append(...)` replaces the last entry if it is less than 60 seconds old to avoid rapid duplicate rows.
- `UsageHistoryFormatter.trendSummary(...)` generates a 24h 5h-remaining delta summary for Claude and Codex.
- `UsageHistoryFormatter.csvString(for:)` exports history as CSV with provider rows and no credential content.
- `AppDelegate` now appends to history after each refresh.
- `History` menu shows trend summary, retention days, and `Export History CSV...`.
- `Sources/TokenTrackerMenuBar/PreferencesWindowController.swift` was added.
- Preferences window is a native AppKit window, not a web view.
- Preferences exposes provider toggles, display mode, provider label style, refresh interval, language, notification enable, alert thresholds, reset warning window, and history retention.
- App menu now has `Preferences...` with key equivalent comma.
- README feature list now mentions diagnostics, alerts, history, CSV export, and preferences.
- `Sources/TokenTrackerSmokeTests/main.swift` now tests issue classification, stale-cache issue classification, alert candidate generation, notification-disabled behavior, history trend summary, and CSV output.
- Validation before this handoff passed: `swift build`, `swift run TokenTrackerSmokeTests`, `git diff --check`, and `scripts/build_app.sh`.
- `.build/Token Tracker.app` was rebuilt by `scripts/build_app.sh`.
- Windows tests were not run because this session changed no Windows C# files and the active local environment does not have `dotnet`.
- The new diagnostics report deliberately uses file-existence booleans rather than file contents for auth-related paths.
- The new Preferences window uses steppers for numeric settings to keep values bounded by the same ranges as `Settings`.
- Notification thresholds can be set to `0`, which effectively disables that threshold in `UsageAlertEvaluator`.
- Reset alert windows can also be set to `0`, which disables reset-soon alert candidates.

## What We Tried (Chronological)

1. Reconfirmed repo state with `git status --short --branch`; `main` matched `origin/main` at start and the working tree was clean.
2. Read macOS `AppDelegate.swift`, core `Models.swift`, `Settings.swift`, `Localization.swift`, and `Paths.swift`.
3. Compared existing macOS menus with Windows `TrayAppContext.cs` through search results from prior review.
4. Converted the user's numbered recommendations into six implementation phases: error UX, diagnostics/recovery, notifications, history/trend, preferences, and validation/handoff/push.
5. Implemented Phase 1 by adding `UsageIssueFormatter.swift`.
6. Added localization keys for user-facing status, recovery, and technical error labels.
7. Updated `AppDelegate.addUsage(_:,to:)` to show status/recovery/technical error rows for each provider.
8. Added `Copy Diagnostics` to the macOS menu and wrote `diagnosticsText()` in `AppDelegate`.
9. Added smoke tests for error kind classification and stale-cache issue formatting.
10. Ran `swift build` and `swift run TokenTrackerSmokeTests`; both passed after Phase 1.
11. Implemented Phase 2 by adding last successful update tracking, running instance count, credential/auth file reveal actions, and refresh interval warning.
12. Added diagnostics lines for last successful update, running instances, short refresh warning, and auth file existence.
13. Ran `swift build` and `swift run TokenTrackerSmokeTests`; both passed after Phase 2.
14. Implemented Phase 3 by extending `Settings` with notification flags and thresholds.
15. Added `UsageAlertEvaluator.swift` and tested low-usage/reset-soon candidate generation.
16. Added `UserNotifications` integration to `AppDelegate` and a menu toggle for notifications.
17. Ran `swift build` and `swift run TokenTrackerSmokeTests`; both passed after Phase 3.
18. Implemented Phase 4 by adding `UsageHistoryStore.swift`, `UsageHistoryFormatter`, and `AppPaths.usageHistory`.
19. Added history append after refresh, 24h trend menu text, retention setting, and CSV export through `NSSavePanel`.
20. Added smoke tests for trend summary and CSV formatting.
21. Ran `swift build` and `swift run TokenTrackerSmokeTests`; both passed after Phase 4.
22. Implemented Phase 5 by adding `PreferencesWindowController.swift`.
23. Added `Preferences...` menu item and wiring from preference changes back into timer scheduling, menu rebuild, status redraw, provider refresh, and notification authorization.
24. Ran `swift build` and `swift run TokenTrackerSmokeTests`; both passed after Phase 5.
25. Updated `README.md` to document the new diagnostics, alerts, history, CSV export, and preferences features.
26. Ran final validation commands: `swift build`, `swift run TokenTrackerSmokeTests`, `git diff --check`, and `scripts/build_app.sh`.
27. Read the handoff skill and required output/validation references.
28. Collected git state, existing handoffs, recent notes, and validation evidence.
29. Created this handoff as a new `macos-usage-ux` chain because the work is functional UX hardening rather than direct M4 width stabilization.

## Key Decisions

- Kept paid/Pro features out of scope because the user explicitly wanted to delay money-making features.
- Focused implementation on macOS and shared Swift core because the original app investigation and current UX features are in the macOS menu bar app.
- Did not change Windows C# code in this session to avoid unverified cross-platform churn in an environment without `dotnet`.
- Added issue classification in core rather than only in `AppDelegate`, so tests can validate the behavior without UI automation.
- Kept technical error strings available in diagnostics and menu detail, but separated them from user-facing status/recovery text.
- Diagnostics report file existence only for credential/auth paths; it never reads or copies credential contents.
- Notifications default to off to keep the app quiet until a user opts in.
- Alert deduping is in-memory for this pass; it prevents repeated alerts during a running session without adding another persistence file.
- History stores usage snapshots and error/source metadata but not token or credential data.
- CSV export is explicit through a save panel instead of auto-writing to user-visible locations.
- Preferences is native AppKit and intentionally compact; it centralizes settings now that menus have grown.
- Left the direct bitmap status renderer untouched because this work focused on functional UX, not the prior M4 rendering architecture.

## Evidence & Data

| Validation command | Result |
| --- | --- |
| `swift build` | Passed, `Build complete!` |
| `swift run TokenTrackerSmokeTests` | Passed, `TokenTrackerSmokeTests passed` |
| `git diff --check` | Passed, no output |
| `scripts/build_app.sh` | Passed, `Built .build/Token Tracker.app` |

| Phase | Completion evidence |
| --- | --- |
| Phase 1 error UX | `UsageIssueFormatter` added, `addUsage` displays status/recovery, smoke tests classify errors |
| Phase 2 diagnostics/recovery | `Diagnostics` menu, copy report, credential/auth reveal actions, last success and instance count |
| Phase 3 notifications | `UsageAlertEvaluator`, notification settings, local notification send path, alert tests |
| Phase 4 history/trend | `UsageHistoryStore`, trend summary, CSV export, history tests |
| Phase 5 preferences | `PreferencesWindowController`, menu entry, settings callbacks, build success |
| Phase 6 validation | final Swift build/test/diff-check/app-bundle build passed |

| New Swift file | Purpose |
| --- | --- |
| `Sources/TokenTrackerCore/UsageIssueFormatter.swift` | Error classification and user-facing issue messages |
| `Sources/TokenTrackerCore/UsageAlertEvaluator.swift` | Low-usage/reset notification candidate generation |
| `Sources/TokenTrackerCore/UsageHistoryStore.swift` | Local snapshot history persistence, trend summary, CSV formatting |
| `Sources/TokenTrackerMenuBar/PreferencesWindowController.swift` | Native macOS preferences window |

Current working tree before adding this handoff:

```text
 M README.md
 M Sources/TokenTrackerCore/Localization.swift
 M Sources/TokenTrackerCore/Paths.swift
 M Sources/TokenTrackerCore/Settings.swift
 M Sources/TokenTrackerMenuBar/AppDelegate.swift
 M Sources/TokenTrackerSmokeTests/main.swift
?? Sources/TokenTrackerCore/UsageAlertEvaluator.swift
?? Sources/TokenTrackerCore/UsageHistoryStore.swift
?? Sources/TokenTrackerCore/UsageIssueFormatter.swift
?? Sources/TokenTrackerMenuBar/PreferencesWindowController.swift
```

Recent commit context:

```text
210c36c Add macOS provider controls and stable status width
d304a12 Fix menu bar refresh visibility
3a61da4 Optimize macOS and Windows platform handling
099e506 Fix release Swift concurrency checks
160c45d Prepare v1.0.6 release
```

Key tested alert output:

```text
["claude-5h-low", "claude-7d-low", "claude-5h-reset-{epoch}"]
```

Key tested history trend output:

```text
24h trend: Claude 5h +23% Codex 5h +1%
```

CSV output header verified by smoke test:

```text
recorded_at,provider,remaining_5h,remaining_7d,reset_5h,reset_7d,source,plan,error
```

## Code Analysis

- `UsageIssueFormatter.kind(forError:)` is string-based because provider clients currently return `ProviderUsage.unavailable` with localized/error-description strings.
- `UsageIssueFormatter.issue(for:)` treats `.staleCache` specially: it reports cached data while preserving the underlying technical error.
- `UsageAlertEvaluator.candidates(...)` is pure and deterministic with an injectable `now`, making it suitable for smoke testing.
- Alert IDs use stable provider/window keys for low-usage alerts and include reset timestamps for reset alerts.
- `Settings` now owns notification thresholds and history retention so preferences, menus, and future automation use one source of truth.
- `UsageHistoryStore.append(...)` prunes by retention days and replaces sub-minute entries to avoid noisy history files.
- `UsageHistoryFormatter.csvString(for:)` escapes CSV values with quotes when needed.
- `AppDelegate.diagnosticsText()` builds diagnostics locally because it needs app bundle, OS, and menu state not owned by core.
- `PreferencesWindowController` updates the same `Settings` instance used by `AppDelegate`; callbacks then redraw status, rebuild menus, reschedule timers, or refresh providers as needed.
- `UserNotifications` authorization is requested only when notifications are enabled.
- `NSSavePanel.allowedContentTypes = [.commaSeparatedText]` is used for history export, so macOS presents the CSV as a real comma-separated text file.
- `UsageHistoryFormatter.trendSummary` currently uses 5h remaining percentages only; it does not attempt to infer token burn rate.

## Files Changed

### Source code

- `Sources/TokenTrackerCore/UsageIssueFormatter.swift` - new issue classification and recovery text model.
- `Sources/TokenTrackerCore/UsageAlertEvaluator.swift` - new alert candidate evaluator for low usage and reset-soon notifications.
- `Sources/TokenTrackerCore/UsageHistoryStore.swift` - new local history store, trend formatter, and CSV formatter.
- `Sources/TokenTrackerCore/Settings.swift` - added notification thresholds and history retention settings.
- `Sources/TokenTrackerCore/Paths.swift` - added `usageHistory` file path.
- `Sources/TokenTrackerCore/Localization.swift` - added English/Korean labels for diagnostics, statuses, recovery, notifications, history, and preferences.
- `Sources/TokenTrackerMenuBar/AppDelegate.swift` - added diagnostics menu, provider status UX, recovery actions, notification handling, history menu/export, preferences menu, and diagnostics text.
- `Sources/TokenTrackerMenuBar/PreferencesWindowController.swift` - new native preferences window.

### Tests

- `Sources/TokenTrackerSmokeTests/main.swift` - added tests for error classification, stale-cache issue details, alert candidates, disabled notifications, history trend summary, and CSV output.

### Documentation

- `README.md` - added diagnostics, alerts, history, CSV export, and preferences to the feature/menu list.

### Generated artifacts

- `.build/Token Tracker.app` - regenerated by `scripts/build_app.sh`; generated artifact, not expected to be committed.

### Handoffs

- `plans/handoffs/HANDOFF_macos-usage-ux_diagnostics-alerts-history_2026-06-15.md` - this handoff.

## User Feedback & Preferences (REQUIRED - never omit)

- User asked what `HTTP 429 Claude API` means.
- User asked to think about functional improvements for the current project.
- User chose to delay features that directly monetize the app.
- User wanted recommendation items 2 through 6 implemented.
- User requested an execution plan.
- User explicitly requested each implementation phase to have a detailed plan and completion point before moving to the next phase.
- User required final validation, handoff documentation, and push after successful validation.
- User later instructed not to report intermediate progress and to summarize only completed work at the end.
- User communicates in Korean and prefers direct execution.

## Where We're Going

- Stage the changed Swift source, README, smoke tests, and this handoff.
- Commit with a message describing diagnostics, alerts, history, and preferences.
- Push `main` to `origin`.
- Have a user run the rebuilt `.build/Token Tracker.app` or release build and verify notification permission flow plus Preferences UI.
- In a future session, consider adding equivalent diagnostics/history UX to the Windows tray app if Windows parity becomes important.

## Risks & Blockers

- Preferences window has compile coverage but no automated UI screenshot or click-through test.
- Local notification delivery depends on macOS notification permission and Focus settings.
- Alert deduping is in-memory, so restarting the app may allow the same still-active alert to fire again.
- Windows parity is not implemented for the new diagnostics/alerts/history UX in this session.
- The app is still unsigned/not notarized, so distribution UX remains separate work.

## Open Questions

- Should notification dedupe state persist across app restarts?
- Should history retention default remain 7 days, or be longer now that CSV export exists?
- Should Windows receive matching diagnostics/alerts/history/preferences features?
- Should diagnostics include a one-click issue report template later?
- Should future releases add Sparkle auto-update before broader external distribution?

## Quick Start for Next Session

```bash
# Current handoff
sed -n '1,380p' plans/handoffs/HANDOFF_macos-usage-ux_diagnostics-alerts-history_2026-06-15.md

# Related previous macOS UX/stability handoff
sed -n '1,360p' plans/handoffs/HANDOFF_m4-menubar-stability_provider-controls-stable-width_2026-06-15.md

# Key files to read first
sed -n '1,260p' Sources/TokenTrackerMenuBar/AppDelegate.swift
sed -n '1,260p' Sources/TokenTrackerMenuBar/PreferencesWindowController.swift
sed -n '1,220p' Sources/TokenTrackerCore/UsageIssueFormatter.swift
sed -n '1,220p' Sources/TokenTrackerCore/UsageAlertEvaluator.swift
sed -n '1,260p' Sources/TokenTrackerCore/UsageHistoryStore.swift

# Verify current state
git status --short --branch
swift build
swift run TokenTrackerSmokeTests
git diff --check
scripts/build_app.sh

# Next action
# Manually run the app and click through Preferences, Diagnostics, notification enable, and History CSV export on macOS.
```
