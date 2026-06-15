# macOS AppDelegate modularization and menu cleanup

**Date:** 2026-06-15
**Status:** COMPLETED
**Bead(s):** none
**Epic:** Token Tracker macOS maintainability hardening
**Chain:** `macos-menubar-refactor` seq `1`
**Parent:** none - first in chain
**Prior chain:** none - first in chain

---

## Related Handoffs

- `HANDOFF_macos-usage-ux_diagnostics-alerts-history_2026-06-15.md` - related source context for diagnostics, alerts, history, and preferences that were later modularized.
- `HANDOFF_m4-menubar-stability_provider-controls-stable-width_2026-06-15.md` - related status width and provider-control work that created part of the AppDelegate complexity.
- `HANDOFF_m4-menubar-stability_refresh-width-fix_2026-06-09.md` - related M4 menu bar disappearance investigation and status item width fix.
- `HANDOFF_claude-usage-stability_429-cooldown-plan_2026-06-06.md` - related provider error/cooldown context that informs menu diagnostics.
- `HANDOFF_platform-optimization_macos-windows-hardening_2026-06-09.md` - related cross-platform tray/menu behavior context.

## Reference Documents

- `README.md` - user-facing feature list and app behavior.
- `WORK_SUMMARY.md` - older project summary and original menu behavior notes.
- `agent.md` - local behavior notes around display modes and provider information.
- `SECURITY_AUDIT.md` - prior hardening context.

## The Goal

The user asked to verify whether the code was well modularized from an object-oriented perspective.
The review found that `TokenTrackerCore` was reasonably separated from AppKit, but `AppDelegate` had accumulated too many responsibilities.
The user then asked to set a decomposition plan and proceed with the refactor.
The target end state was no functional behavior change, but a smaller `AppDelegate` with status rendering, menu construction, diagnostics, and notification handling split into focused collaborator objects.
The user finally requested `/handoff` and push.

## Where We Are

- Current branch at handoff creation: `main`.
- Remote `origin/main` checked with `git ls-remote origin refs/heads/main`.
- Remote `origin/main` was `89d8db5d2856c3ecfa02edae8324b713924d231f`, matching the local base commit before this refactor.
- Latest committed base before this work: `89d8db5 Add macOS diagnostics alerts history preferences`.
- The working tree before writing this handoff contained five intended source changes.
- `Sources/TokenTrackerMenuBar/AppDelegate.swift` was reduced from roughly 740 lines after the previous UX work to 228 lines after this refactor.
- `AppDelegate` now focuses on app lifecycle, refresh orchestration, settings window action wiring, history CSV export, launch-at-login toggle, and Finder reveal actions.
- `Sources/TokenTrackerMenuBar/StatusItemRenderer.swift` was added.
- `StatusItemRenderer` now owns `NSStatusItem`, status title image generation, icon loading, icon tint drawing, status item reserved width, appearance-sensitive text color, and loading/placeholder rendering.
- `StatusItemRenderer.setPlaceholder(mode:labelStyle:)` and `setLoading(mode:labelStyle:)` keep the existing reserved-width behavior even before a snapshot is loaded.
- `Sources/TokenTrackerMenuBar/StatusMenuBuilder.swift` was added.
- `StatusMenuBuilder` now owns `NSMenu` construction for usage rows, refresh, preferences, diagnostics, history, launch-at-login, and quit.
- `StatusMenuActions` carries the target object and selectors used by menu items.
- `StatusMenuContext` carries the current snapshot, settings, localization, history trend text, launch-at-login state, and running instance count.
- `InfoMenuItemView` moved from `AppDelegate.swift` into `StatusMenuBuilder.swift`.
- `Sources/TokenTrackerMenuBar/DiagnosticsReporter.swift` was added.
- `DiagnosticsReporter` now owns diagnostics text generation, English history trend text, app version/build extraction, architecture reporting, credential/auth path constants, and per-provider diagnostics lines.
- `Sources/TokenTrackerMenuBar/UsageNotificationCoordinator.swift` was added.
- `UsageNotificationCoordinator` now owns notification permission requests, in-memory delivered alert ID tracking, alert candidate evaluation, and local notification submission.
- `AppDelegate` now composes `StatusItemRenderer`, `UsageNotificationCoordinator`, `DiagnosticsReporter`, and `StatusMenuBuilder`.
- The earlier menu-shortening change remains in place: settings-related controls are no longer duplicated in the status menu because they live in the Preferences window.
- The visible status menu after validation contained usage details, `지금 새로고침`, `설정...`, `진단`, `히스토리`, `로그인 시 실행: 켜짐`, and `종료`.
- Removed menu duplicates did not reappear after the refactor.
- Preferences window still opens through `설정...` and closes normally.
- The rebuilt app is running from `.build/Token Tracker.app`.
- Final observed process: PID `46699` at `.build/Token Tracker.app/Contents/MacOS/TokenTrackerMenuBar`.
- The handoff file itself is `plans/handoffs/HANDOFF_macos-menubar-refactor_appdelegate-modularization_2026-06-15.md`.
- This handoff is not a continuation parent of `macos-usage-ux`; that prior handoff is related context because it introduced diagnostics/alerts/history/preferences, but the current workstream is object-oriented decomposition.

## What We Tried (Chronological)

1. The user first asked for a review of the current changes against `origin/main`.
2. Ran `git diff 89d8db5d2856c3ecfa02edae8324b713924d231f` and saw only the status-menu shortening change in `AppDelegate.swift`.
3. Confirmed that removed menu selectors such as `selectDisplayMode`, `toggleProvider`, `selectRefreshInterval`, `selectLanguage`, and `toggleNotifications` only still existed inside `PreferencesWindowController`, where they are valid.
4. Ran `swift build`; it passed.
5. Reported no actionable code-review findings for the menu-shortening diff.
6. The user then asked whether the code was well modularized from an object-oriented point of view.
7. Gathered file structure with `rg --files Sources Tests plans` and `find Sources -maxdepth 3 -type f -name '*.swift' -print`.
8. Counted Swift file sizes with `wc -l`; `AppDelegate.swift` was the clear outlier at 740 lines.
9. Read `Package.swift` and confirmed `TokenTrackerCore` is separate from `TokenTrackerMenuBar`.
10. Read `Models.swift`, `UsageService.swift`, `ClaudeUsageClient.swift`, `CodexUsageClient.swift`, `HTTPClient.swift`, `Settings.swift`, `DisplayFormatter.swift`, `UsageIssueFormatter.swift`, `UsageAlertEvaluator.swift`, `UsageHistoryStore.swift`, `Localization.swift`, and `PreferencesWindowController.swift`.
11. Verified `TokenTrackerCore` does not import AppKit/UserNotifications/ServiceManagement; AppKit imports are confined to `TokenTrackerMenuBar`.
12. Ran `swift run TokenTrackerSmokeTests`; it passed.
13. Reported that Core was modular enough, but `AppDelegate` had too many responsibilities: status rendering, menu construction, timer refresh orchestration, notifications, diagnostics, history export, and Finder reveal.
14. Recommended first extracting `StatusItemRenderer`, `StatusMenuBuilder`, `NotificationCoordinator`, `DiagnosticsProvider`, and later provider protocols.
15. User asked to plan and execute the decomposition.
16. Added `StatusItemRenderer.swift` by moving the status item renderer, status segment image drawing, icon loading, warning color, status text color, and reserved-width logic out of `AppDelegate`.
17. Adjusted placeholder/loading APIs to accept `DisplayMode` and `ProviderLabelStyle` so loading/initial states preserve width reservation.
18. Added `StatusMenuBuilder.swift` by moving menu construction, usage row creation, diagnostics submenu, history submenu, launch-at-login row, action item setup, relative time formatting, and `InfoMenuItemView`.
19. Added `DiagnosticsReporter.swift` by moving diagnostics text generation, provider diagnostics line formatting, app metadata, architecture reporting, auth path constants, and history trend text.
20. Added `UsageNotificationCoordinator.swift` by moving `deliveredAlertIDs`, notification authorization request, alert candidate handling, and notification request creation.
21. Patched `AppDelegate.swift` to own collaborators instead of renderer/menu/diagnostics/notification implementation details.
22. Replaced direct status image calls in `applicationDidFinishLaunching`, refresh loading, and `updateStatusTitle` with `StatusItemRenderer`.
23. Replaced direct notification handling in refresh and preferences callbacks with `UsageNotificationCoordinator`.
24. Replaced direct menu construction with `StatusMenuBuilder(actions:context:).build()`.
25. Replaced direct diagnostics generation and credential path helpers with `DiagnosticsReporter`.
26. Removed leftover render helpers and menu helper code from `AppDelegate`.
27. Fixed a patch artifact where the tail of the old `InfoMenuItemView` briefly remained after `AppDelegate.runningInstanceCount()`.
28. Ran `rg` for old symbols and confirmed no unwanted leftover AppDelegate references remained.
29. Ran `swift build`; it passed.
30. Ran `swift run TokenTrackerSmokeTests`; it passed.
31. Ran `git diff --check`; it passed with no output.
32. Ran `scripts/build_app.sh`; it passed and rebuilt `.build/Token Tracker.app`.
33. Restarted the app with `pkill -x TokenTrackerMenuBar` and `open ".build/Token Tracker.app"`.
34. Confirmed the process was running with `ps ax -o pid,comm | rg TokenTrackerMenuBar`.
35. Opened the status menu with AppleScript and listed menu item names.
36. Confirmed the menu had expected operational items and did not include duplicated settings submenus.
37. Clicked `설정...` via AppleScript and confirmed a `Token Tracker` window opened and closed.
38. Checked final process state again; `TokenTrackerMenuBar` remained alive.
39. Read the handoff skill and its Deep handoff references.
40. Collected git branch, status, diff stat, recent log, existing handoffs, related handoffs, and remote main hash before writing this file.

## Key Decisions

- Treated this as a new `macos-menubar-refactor` chain because the goal is maintainability and object decomposition, not direct continuation of the diagnostics/history feature chain.
- Kept all new collaborator types in `Sources/TokenTrackerMenuBar` because they use AppKit or UserNotifications and should not pollute `TokenTrackerCore`.
- Did not introduce provider protocols in this pass because the user's immediate ask was to decompose the code already identified as too large, and protocol extraction would touch Core service seams with more behavioral risk.
- Moved code instead of rewriting behavior; this keeps the refactor low risk and easier to validate.
- Preserved selectors in `AppDelegate` through `StatusMenuActions` because AppKit menu items still need Objective-C-visible targets/actions.
- Kept `StatusMenuBuilder` as a value type with explicit context and action dependencies, so menu construction is isolated but still simple.
- Kept `DiagnosticsReporter` free of AppKit UI APIs except Foundation bundle/process/file checks, making it easier to unit-test later if needed.
- Kept `UsageNotificationCoordinator` as a reference type because delivered alert IDs are mutable session state.
- Kept `PreferencesWindowController` unchanged because it already owns the settings window UI and its controls.
- Kept the existing runtime behavior around menu contents after the previous user request: configuration-heavy items stay in Preferences instead of the status dropdown.
- Did not create a separate `HistoryExportCoordinator` yet because CSV export still includes `NSSavePanel` and is a small remaining responsibility in `AppDelegate`.
- Did not create a separate `FinderRevealCoordinator` because revealing auth paths is two small action wrappers and not currently a maintenance bottleneck.
- Did not commit before writing this handoff because the user asked for handoff and push, and the handoff file should be part of the pushed commit.

## Evidence & Data

| Item | Value |
| --- | --- |
| Branch | `main` |
| Base commit | `89d8db5 Add macOS diagnostics alerts history preferences` |
| Remote `origin/main` before handoff | `89d8db5d2856c3ecfa02edae8324b713924d231f` |
| Main tracked diff before adding handoff | `Sources/TokenTrackerMenuBar/AppDelegate.swift` modified |
| New source files before handoff | 4 |
| AppDelegate line count after refactor | `228` |
| StatusItemRenderer line count | `312` |
| StatusMenuBuilder line count | `209` |
| DiagnosticsReporter line count | `115` |
| UsageNotificationCoordinator line count | `59` |
| Combined new/changed macOS refactor files | `923` lines |

| Validation command | Result |
| --- | --- |
| `swift build` | Passed; `Build complete!` |
| `swift run TokenTrackerSmokeTests` | Passed; `TokenTrackerSmokeTests passed` |
| `git diff --check` | Passed; no output |
| `scripts/build_app.sh` | Passed; `Built .build/Token Tracker.app` |
| `pkill -x TokenTrackerMenuBar` | Exited 0 before relaunch |
| `open ".build/Token Tracker.app"` | Exited 0 |
| `ps ax -o pid,comm | rg TokenTrackerMenuBar` | Found PID `46699` |
| AppleScript menu listing | Returned expected menu items |
| AppleScript settings action | Opened `Token Tracker` preferences window |

Runtime menu listing after refactor included:

```text
Claude: 5h 91%, 7d 70%
상태: 정상
Codex: 5h 63%, 7d 76%
지금 새로고침
설정...
진단
히스토리
로그인 시 실행: 켜짐
종료
```

Settings window verification output:

```text
button 1 of window Token Tracker of application process TokenTrackerMenuBar
```

Current `git status -s` before writing this handoff:

```text
 M Sources/TokenTrackerMenuBar/AppDelegate.swift
?? Sources/TokenTrackerMenuBar/DiagnosticsReporter.swift
?? Sources/TokenTrackerMenuBar/StatusItemRenderer.swift
?? Sources/TokenTrackerMenuBar/StatusMenuBuilder.swift
?? Sources/TokenTrackerMenuBar/UsageNotificationCoordinator.swift
```

Recent commit history before this handoff:

```text
89d8db5 Add macOS diagnostics alerts history preferences
210c36c Add macOS provider controls and stable status width
d304a12 Fix menu bar refresh visibility
3a61da4 Optimize macOS and Windows platform handling
099e506 Fix release Swift concurrency checks
160c45d Prepare v1.0.6 release
c89e86f Improve Claude usage fetch diagnostics
```

Main decomposition result:

```text
AppDelegate.swift                  228 lines
StatusItemRenderer.swift           312 lines
StatusMenuBuilder.swift            209 lines
DiagnosticsReporter.swift          115 lines
UsageNotificationCoordinator.swift  59 lines
```

Primary changed ownership:

| Responsibility | Before | After |
| --- | --- | --- |
| `NSStatusItem` and image rendering | `AppDelegate` | `StatusItemRenderer` |
| Menu construction | `AppDelegate.configureMenu()` | `StatusMenuBuilder.build()` |
| Info menu item custom view | `AppDelegate.swift` private class | `StatusMenuBuilder.swift` private class |
| Diagnostics text | `AppDelegate.diagnosticsText()` | `DiagnosticsReporter.diagnosticsText()` |
| Notification alert dedupe | `AppDelegate.deliveredAlertIDs` | `UsageNotificationCoordinator.deliveredAlertIDs` |
| Notification permission | `AppDelegate.requestNotificationAuthorization()` | `UsageNotificationCoordinator.requestAuthorization()` |
| App lifecycle and refresh orchestration | `AppDelegate` | `AppDelegate` |

## Code Analysis

- `AppDelegate` remains `@MainActor` because it owns AppKit lifecycle and UI callbacks.
- `StatusItemRenderer` is `@MainActor` because it owns `NSStatusBar.system.statusItem`, `NSStatusBarButton`, `NSImage.lockFocus`, and appearance reads.
- `StatusItemRenderer` preserves `statusItemHorizontalPadding = 10` and the sample `100%` snapshot reservation strategy from the prior M4 width fix.
- `StatusSegment` is now private to `StatusItemRenderer.swift`; no other file depends on its representation.
- `StatusMenuBuilder` accepts `StatusMenuContext` instead of reading global state, which keeps menu building explicit and easier to test manually.
- `StatusMenuActions` centralizes Objective-C selectors used in menu items while keeping AppDelegate as the target object.
- `DiagnosticsReporter` exposes static `claudeCredentialsURL` and `codexAuthURL`, so `AppDelegate` no longer owns credential path construction.
- `DiagnosticsReporter.historyTrendText(language:)` reuses `UsageHistoryFormatter.trendSummary`, preserving the previous diagnostics/history behavior.
- `UsageNotificationCoordinator.handleNotifications(for:localizer:)` preserves the previous `UsageAlertEvaluator.candidates` behavior and active-ID intersection.
- `PreferencesWindowController` still mutates `Settings` directly and calls callbacks; this is acceptable for now but is still a future ViewModel candidate.
- `UsageService` and Core provider clients were not modified in this refactor.
- `TokenTrackerCore` still has no AppKit dependency after this work.
- The refactor intentionally leaves `exportHistoryCSV()` in `AppDelegate` because it combines menu action, `NSSavePanel`, and error alert UI.
- `runningInstanceCount()` remains in `AppDelegate` because it depends on `Bundle.main.bundleIdentifier` and is only used to populate menu/diagnostics context.

## Files Changed

### Source code

- `Sources/TokenTrackerMenuBar/AppDelegate.swift` - removed status rendering, menu-building, diagnostics text, notification coordination, and custom menu item view responsibilities; now wires focused collaborators.
- `Sources/TokenTrackerMenuBar/StatusItemRenderer.swift` - new focused status item renderer for menu bar image content, icon rendering, colors, and reserved width.
- `Sources/TokenTrackerMenuBar/StatusMenuBuilder.swift` - new focused status menu builder and menu info item view.
- `Sources/TokenTrackerMenuBar/DiagnosticsReporter.swift` - new diagnostics and history-trend reporter.
- `Sources/TokenTrackerMenuBar/UsageNotificationCoordinator.swift` - new notification permission, dedupe, and delivery coordinator.

### Tests

- No test source file changed in this refactor.
- Existing smoke tests still passed with `swift run TokenTrackerSmokeTests`.

### Data & results

- `.build/Token Tracker.app` was rebuilt by `scripts/build_app.sh`; generated artifact and not intended for git.
- Runtime validation used AppleScript against the rebuilt app and process PID `46699`.

### Config

- No package, workflow, or project config changed.

### Handoffs

- `plans/handoffs/HANDOFF_macos-menubar-refactor_appdelegate-modularization_2026-06-15.md` - this continuity document.

## User Feedback & Preferences (REQUIRED - never omit)

- User originally reported an M4-only symptom where the menu bar app disappears from the menu bar while the process stays alive.
- User asked to add GitHub collaborator `sim9609` with write permission earlier in the broader thread.
- User asked multiple times to handoff, commit, and push work when a phase is complete.
- User asked whether automatic updates could work when users are already running the program.
- User clarified that app updates should check GitHub releases, not every push.
- User asked about Apple developer registration and Windows signing/certification costs.
- User asked whether ads or donation links are realistic monetization options.
- User asked whether a one-time purchase model implies a private repo.
- User asked what `HTTP 429 Claude API` means.
- User asked to think about functional project improvements.
- User decided to postpone paid/pro monetization features.
- User wanted recommendation items 2 through 6 implemented first.
- User asked to set a plan and execute, not only discuss.
- User explicitly requested no mid-progress reports and asked for only completed work summaries.
- User asked to restart the modified process and perform real-use validation.
- User noticed settings-related content remained in the menu tab/dropdown and asked to remove it.
- User then asked to validate object-oriented modularization.
- User accepted the finding that `AppDelegate` was too large and asked to proceed with the decomposition plan.
- User now asked `/handoff 하고 푸시`.
- User communicates in Korean and prefers concise, execution-oriented reports.

## Where We're Going

- Stage the refactor files and this handoff file.
- Commit with a message that reflects the AppDelegate modularization.
- Push `main` to `origin`.
- If future menu functionality grows, consider extracting history export and Finder reveal actions from `AppDelegate`.
- If future provider count grows, revisit `UsageSnapshot` fixed Claude/Codex structure and introduce provider collection modeling.
- If test coverage is expanded, add unit-level tests around `DiagnosticsReporter` and possibly snapshot-based checks for `StatusMenuBuilder` item ordering.

## Risks & Blockers

- AppKit UI code remains mostly smoke/manual validated; there are no automated AppKit menu tests.
- `StatusItemRenderer` still uses bitmap drawing with `NSImage.lockFocus`; this preserves behavior but does not remove all possible appearance/tint risks on unusual macOS menu bar configurations.
- `StatusMenuBuilder` uses selectors passed from `AppDelegate`; compile-time coverage exists, but invalid selector wiring would still be mostly caught by runtime menu testing.
- `PreferencesWindowController` still directly mutates `Settings`, which is acceptable now but could become harder to reason about if settings validation becomes more complex.
- Generated `.build/Token Tracker.app` should not be committed.

## Open Questions

- Should `History CSV Export` become its own coordinator in a later cleanup?
- Should `PreferencesWindowController` move to a ViewModel-style object if settings grow further?
- Should Core provider access be protocol-based to make `UsageService` fully mockable?
- Should `UsageSnapshot` become provider-keyed instead of fixed `claude`/`codex` fields before adding more providers?

## Quick Start for Next Session

```bash
# Current handoff
sed -n '1,380p' plans/handoffs/HANDOFF_macos-menubar-refactor_appdelegate-modularization_2026-06-15.md

# Related context
sed -n '1,260p' plans/handoffs/HANDOFF_macos-usage-ux_diagnostics-alerts-history_2026-06-15.md
sed -n '1,260p' plans/handoffs/HANDOFF_m4-menubar-stability_provider-controls-stable-width_2026-06-15.md

# Key files to read first
sed -n '1,260p' Sources/TokenTrackerMenuBar/AppDelegate.swift
sed -n '1,360p' Sources/TokenTrackerMenuBar/StatusItemRenderer.swift
sed -n '1,260p' Sources/TokenTrackerMenuBar/StatusMenuBuilder.swift
sed -n '1,180p' Sources/TokenTrackerMenuBar/DiagnosticsReporter.swift
sed -n '1,120p' Sources/TokenTrackerMenuBar/UsageNotificationCoordinator.swift

# Verify current state
swift build
swift run TokenTrackerSmokeTests
scripts/build_app.sh

# Next action
Review whether remaining AppDelegate responsibilities, especially history CSV export and Finder reveal actions, are worth extracting or should stay for now.
```
