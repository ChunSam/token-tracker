# M4 menu bar refresh width stability fix

**Date:** 2026-06-09
**Status:** COMPLETED
**Bead(s):** none
**Epic:** Token Tracker macOS runtime stability
**Chain:** `m4-menubar-stability` seq `1`
**Parent:** none - first in chain
**Prior chain:** none - first in chain

---

## Related Handoffs

- `HANDOFF_platform-optimization_macos-windows-hardening_2026-06-09.md` - related platform hardening work that changed macOS status tinting, universal builds, and Windows reliability behavior; this handoff is a separate M4 menu bar stability investigation.
- `HANDOFF_claude-usage-stability_429-cooldown-plan_2026-06-06.md` - related Claude usage cooldown context, not directly part of this chain.
- `HANDOFF_claude-usage-stability_macos-auth-fallback_2026-06-05.md` - related stale-cache and auth fallback context, not directly part of this chain.

## Reference Documents

- `WORK_SUMMARY.md` - project scope, app structure, build commands, and prior validation notes.
- `README.md` - user-facing build and install guidance.
- `agent.md` - local project notes and workflow guidance.
- `SECURITY_AUDIT.md` - prior security hardening context.

## The Goal

The user reported that Token Tracker works on a MacBook M1 but disappears from the macOS menu bar on an M4 machine after a fixed interval.
The process remains alive, so the goal was to find a UI/runtime cause rather than a crash.
The immediate fix was to stop the automatic refresh loop from changing the status item width every interval.
The same session also handled a GitHub repository collaborator invite for `sim9609` with `write` permission.

## Where We Are

- Current branch at handoff creation: `main`.
- Base commit before this session's code change: `3a61da4 Optimize macOS and Windows platform handling`.
- Working tree before handoff creation had one modified source file: `Sources/TokenTrackerMenuBar/AppDelegate.swift`.
- New handoff file added: `plans/handoffs/HANDOFF_m4-menubar-stability_refresh-width-fix_2026-06-09.md`.
- macOS menu bar app code lives in `Sources/TokenTrackerMenuBar`.
- Shared usage logic lives in `Sources/TokenTrackerCore`.
- The status item is retained strongly as `private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)`.
- The process-still-alive symptom does not match a local status item deallocation bug.
- The default refresh interval is still `60.0` seconds from `Settings.registerDefaults()`.
- The user's local app settings showed `displayMode = both` and `providerLabelStyle = icon`.
- With `both + icon`, the normal status item is wider than the temporary loading label.
- Before the fix, every timer tick called `refreshNow()`.
- Before the fix, `refreshNow()` always called `setStatusTitle("AI ...")` before the network refresh.
- `setStatusImage(_:, on:)` sets `statusItem.length = image.size.width + 10`.
- The likely failure path was a periodic width collapse from the full provider display to `AI ...`, followed by a width expansion back to the full provider display.
- On M4 MacBook menu bars, especially with a notch and limited right-side item space, that repeated width churn can make macOS move or hide a menu extra.
- A secondary risk was identified in the current bitmap tint path.
- A quick Swift check on macOS 26.5.1 showed a new status item button reported `NSAppearanceNameVibrantLight` and best-matched `NSAppearanceNameAqua` even while global appearance was Dark.
- That means the current direct black/white bitmap tint logic can be wrong on newer macOS configurations.
- The implemented fix does not yet replace the bitmap rendering architecture.
- The implemented fix keeps the existing display visible during automatic refreshes.
- The implemented fix still shows `AI ...` for explicit manual refreshes and first-load state.
- `swift build` passed after the fix.
- `swift run TokenTrackerSmokeTests` passed after the fix.
- `git diff --check` passed after the fix.
- `scripts/build_app.sh` passed after the fix and rebuilt `.build/Token Tracker.app`.
- GitHub collaborator invite was sent to `sim9609` for `ChunSam/token-tracker`.
- The collaborator invite permission was `write`.
- GitHub invitation API response ID was `321760079`.
- The invitation URL reported by GitHub was `https://github.com/ChunSam/token-tracker/invitations`.
- The invitee still needs to accept the GitHub invitation before collaborator access is active.
- The GitHub MCP integration could not check collaborator permission due to `FORBIDDEN`.
- The local `gh api` request initially failed inside the sandbox due to network restriction.
- The same `gh api` request succeeded after an approved escalated network run.

## What We Tried (Chronological)

1. Inspected the repository layout with `rg --files`, `pwd`, and `git status --short`.
2. Identified the macOS menu bar app entry points: `Sources/TokenTrackerMenuBar/main.swift` and `Sources/TokenTrackerMenuBar/AppDelegate.swift`.
3. Read `AppDelegate.swift` around the `NSStatusItem`, timer, refresh task, status image rendering, and menu construction.
4. Confirmed `statusItem` is a strong property, so a simple object lifetime bug was unlikely.
5. Confirmed the timer path uses `Timer.scheduledTimer(withTimeInterval: settings.refreshInterval, repeats: true)`.
6. Confirmed the refresh path was setting `AI ...` on every refresh before awaiting `UsageService.refresh()`.
7. Confirmed `setStatusImage(_:, on:)` resizes `statusItem.length` from the generated bitmap width.
8. Read `Settings.swift` and confirmed the default refresh interval is `60.0`.
9. Read local defaults for `local.token-tracker.menubar` and found `displayMode = both` and `providerLabelStyle = icon`.
10. Read previous platform hardening handoff and saw a recent status tinting change based on `effectiveAppearance`.
11. Compared `AppDelegate.swift` against commit `099e506` to see that tinting behavior changed recently, while timer behavior was older.
12. Ran `swift -e` to inspect a fresh status item appearance on local macOS; it returned `NSAppearanceNameVibrantLight` and `NSAppearanceNameAqua`.
13. Treated the appearance result as a secondary risk because it can make a rendered image look invisible on some menu bar backgrounds.
14. Chose a narrow fix: keep the current status image during automatic timer refreshes instead of showing `AI ...`.
15. First implementation introduced `refreshNow(showLoadingIndicator:)`, but `#selector(refreshNow)` became ambiguous because there were two methods with the same base name.
16. Fixed the selector ambiguity by naming the helper `startRefresh(showLoadingIndicator:)`.
17. Re-ran `swift build`; it passed.
18. Re-ran `swift run TokenTrackerSmokeTests`; it passed.
19. Re-ran `git diff --check`; it passed.
20. Rebuilt the app bundle with `scripts/build_app.sh`; it passed and produced `.build/Token Tracker.app`.
21. For the GitHub collaborator request, looked up public `followers` and `following` for `ChunSam`.
22. Found one public candidate in both lists: `sim9609`, with a Korean public display name on the profile.
23. User selected `sim9609` and requested `write` permission.
24. Tried GitHub MCP collaborator permission lookup; it failed with `FORBIDDEN`.
25. Tried `gh api -X PUT repos/ChunSam/token-tracker/collaborators/sim9609 -f permission=write` inside the sandbox; it failed with network connection error.
26. Re-ran the same `gh api` command with approved network escalation; it succeeded and returned a repository invitation payload.

## Key Decisions

- Treated the bug as a menu bar UI visibility issue, not a process crash, because the user reported the process remains alive.
- Prioritized the timer-driven status width change because it matched the "fixed interval" symptom exactly.
- Did not change `NSStatusItem` ownership because the existing `private let statusItem` is already strong enough.
- Did not rewrite the status renderer in this commit because the most direct M4 symptom can be addressed by eliminating automatic width churn.
- Kept the `AI ...` loading indicator for manual refreshes because user-triggered refresh feedback is still useful.
- Kept the `AI ...` loading indicator for first load because there is no existing value to preserve before the first snapshot.
- Rejected keeping automatic `AI ...` feedback because it causes status item width churn every 60 seconds.
- Left the appearance/tint issue as a follow-up because it needs a broader rendering change and possibly manual UI verification on the affected M4.
- Used the public GitHub followers/following API only to show candidate usernames; no private friend list API exists.
- Used `gh api` for collaborator invitation because the available GitHub MCP tools did not expose an add-collaborator mutation.

## Evidence & Data

| Item | Evidence |
| --- | --- |
| Refresh interval | `Settings.registerDefaults()` sets `refreshInterval` to `60.0`. |
| User settings | `defaults read local.token-tracker.menubar` returned `displayMode = both`, `providerLabelStyle = icon`, and no saved `refreshInterval`. |
| Status item retention | `AppDelegate` line 13 keeps `private let statusItem = NSStatusBar.system.statusItem(...)`. |
| Width mutation | `setStatusImage(_:, on:)` sets `statusItem.length = image.size.width + 10`. |
| Prior loading behavior | Previous `refreshNow()` called `setStatusTitle("AI ...")` on every refresh. |
| Fixed timer behavior | Timer now calls `startRefresh(showLoadingIndicator: false)`. |
| Fixed manual behavior | `@objc refreshNow()` now calls `startRefresh(showLoadingIndicator: true)`. |
| Initial load behavior | `startRefresh(showLoadingIndicator:)` still shows `AI ...` when `snapshot == nil`. |
| Appearance probe | `swift -e` returned `NSAppearanceNameVibrantLight` and `NSAppearanceNameAqua` for a fresh status item on local macOS. |
| Local macOS | `sw_vers` returned macOS `26.5.1`, build `25F80`. |
| Architecture | `uname -m` returned `arm64`. |
| Build | `swift build` completed successfully after the fix. |
| Smoke test | `swift run TokenTrackerSmokeTests` completed with `TokenTrackerSmokeTests passed`. |
| Whitespace | `git diff --check` completed with no output. |
| App bundle | `scripts/build_app.sh` completed with `Built .build/Token Tracker.app`. |
| GitHub candidate | Public followers/following for `ChunSam` both returned `sim9609`. |
| GitHub invite | Escalated `gh api` returned invitation id `321760079` and `"permissions":"write"`. |

Key source diff:

```diff
-                self?.refreshNow()
+                self?.startRefresh(showLoadingIndicator: false)
...
     @objc private func refreshNow() {
+        startRefresh(showLoadingIndicator: true)
+    }
+
+    private func startRefresh(showLoadingIndicator: Bool) {
         guard refreshTask == nil else { return }
-        setStatusTitle("AI ...")
+        if showLoadingIndicator || snapshot == nil {
+            setStatusTitle("AI ...")
+        }
```

Validation commands and results:

```bash
swift build
# Build complete

swift run TokenTrackerSmokeTests
# TokenTrackerSmokeTests passed

git diff --check
# no output

scripts/build_app.sh
# Built .build/Token Tracker.app
```

GitHub collaborator command:

```bash
gh api -X PUT repos/ChunSam/token-tracker/collaborators/sim9609 -f permission=write
# Returned repository invitation id 321760079 with permissions "write"
```

## Code Analysis

- `scheduleTimer()` is the only repeating refresh source in the macOS menu bar UI.
- `refreshTask` prevents overlapping refreshes with `guard refreshTask == nil else { return }`.
- `startRefresh(showLoadingIndicator:)` centralizes the refresh launch path while keeping the AppKit selector name unambiguous.
- Automatic refreshes now preserve the previous `snapshot` render while the network calls run.
- Manual refreshes still provide immediate visual feedback.
- The first refresh after launch still provides immediate visual feedback because `snapshot == nil`.
- `updateStatusTitle()` still redraws status text after the refreshed `UsageSnapshot` is available.
- `configureMenu()` is still called after each refresh so menu details remain current.
- The change is intentionally isolated to `AppDelegate.swift`; no core usage parsing, network, cache, or settings logic was modified.
- The direct `NSImage.lockFocus()` bitmap rendering remains in place and is the likely next area to revisit if M4 visibility issues continue.

## Files Changed

### Source code

- `Sources/TokenTrackerMenuBar/AppDelegate.swift` - split refresh triggering into `refreshNow()` and `startRefresh(showLoadingIndicator:)`; automatic timer refreshes now avoid temporary loading text and preserve the existing status item width during background updates.

### Handoffs

- `plans/handoffs/HANDOFF_m4-menubar-stability_refresh-width-fix_2026-06-09.md` - this continuity record.

### Generated artifacts

- `.build/Token Tracker.app` - rebuilt locally by `scripts/build_app.sh`; this is a generated build artifact and is not expected to be committed.

### GitHub remote state

- `sim9609` was invited to `ChunSam/token-tracker` with `write` permission using the GitHub API.

## User Feedback & Preferences (REQUIRED - never omit)

- User reported: the app works on a MacBook M1.
- User reported: on M4, the app disappears from the menu bar after a fixed interval.
- User clarified: the process remains alive when the menu bar item disappears.
- User wanted the cause investigated, not just a speculative explanation.
- User later asked whether a GitHub collaborator could be added.
- User asked to look at the GitHub "friend list" and present candidates.
- User selected `sim9609`.
- User requested `write` permission for `sim9609`.
- User requested a handoff, commit, and push after the work.
- The user communicates in Korean and prefers direct operational handling.

## Where We're Going

- Commit the AppDelegate fix and this handoff file.
- Push the commit to `origin/main`.
- Ask the M4 user to run the rebuilt or pulled app long enough to cross multiple 60-second refresh intervals.
- If the issue persists, replace direct bitmap tinting with AppKit-managed status text/template-image rendering or a custom view with stable width.
- If the user wants confirmation of collaborator activation, check after `sim9609` accepts the invitation.

## Risks & Blockers

- The fix addresses the strongest interval-matched root cause but does not prove behavior on the user's M4 without live UI verification.
- The direct status bitmap tinting path can still render with the wrong color on newer macOS appearance combinations.
- Menu bar overflow behavior depends on the user's installed menu extras, notch layout, and display configuration.
- GitHub invitation is pending until `sim9609` accepts it.

## Open Questions

- Does the M4 machine run the same macOS version as the local machine or a different build?
- Does the menu item disappear exactly at the 60-second refresh interval after launch?
- Does the issue happen only in `both + icon` display mode or also in `lowestRemaining`?
- After this fix, does the M4 still show invisible text due to bitmap tinting?

## Quick Start for Next Session

```bash
# Restore context
sed -n '1,240p' plans/handoffs/HANDOFF_m4-menubar-stability_refresh-width-fix_2026-06-09.md

# Related prior context
sed -n '1,220p' plans/handoffs/HANDOFF_platform-optimization_macos-windows-hardening_2026-06-09.md

# Key files to read first
sed -n '1,130p' Sources/TokenTrackerMenuBar/AppDelegate.swift
sed -n '1,120p' Sources/TokenTrackerCore/Settings.swift
sed -n '1,220p' scripts/build_app.sh

# Verify current state
git status --short
swift build
swift run TokenTrackerSmokeTests

# Next action
# If M4 still reproduces the issue, remove direct bitmap status rendering and use stable-width AppKit-managed status content.
```
