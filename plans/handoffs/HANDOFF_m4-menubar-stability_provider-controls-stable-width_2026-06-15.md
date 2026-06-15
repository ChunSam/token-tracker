# M4 menu bar provider controls and stable width follow-up

**Date:** 2026-06-15
**Status:** COMPLETED
**Bead(s):** none
**Epic:** Token Tracker macOS runtime stability
**Chain:** `m4-menubar-stability` seq `2`
**Parent:** `HANDOFF_m4-menubar-stability_refresh-width-fix_2026-06-09.md`
**Prior chain:** `HANDOFF_m4-menubar-stability_refresh-width-fix_2026-06-09.md` > this

---

## Related Handoffs

- `HANDOFF_platform-optimization_macos-windows-hardening_2026-06-09.md` - related platform hardening work that introduced cross-platform tray/menu behavior and status tinting context.
- `HANDOFF_claude-usage-stability_429-cooldown-plan_2026-06-06.md` - related Claude API cooldown, stale-cache, and provider plan context, separate from this M4 menu bar chain.
- `HANDOFF_claude-usage-stability_macos-auth-fallback_2026-06-05.md` - related earlier Claude auth/cache reliability work, separate from this M4 menu bar chain.

## Since Last Handoff

- Parent seq 1 fixed the highest-confidence interval-matched M4 symptom by preventing automatic timer refreshes from replacing the full status item with the shorter `AI ...` loading image.
- The parent explicitly left direct bitmap status rendering and appearance tinting as follow-up risks.
- The user then asked whether any functional additions or fixes were still needed.
- A functional review found macOS provider enable/disable settings existed in `Settings.swift`, but no macOS menu exposed them.
- The same review found macOS stale-cache fallback ignored provider enabled state, unlike the Windows cache policy.
- The same review found the status item still resized directly to each rendered image width, leaving residual width churn when displayed values or modes changed.
- This session addressed those follow-ups in priority order before creating this handoff.
- The current working tree at handoff creation contains five modified files plus this new handoff file.

## Reference Documents

- `README.md` - user-facing feature list, install/build commands, and menu behavior.
- `WORK_SUMMARY.md` - prior project summary, app scope, and earlier validation notes.
- `agent.md` - local project behavior notes and intended menu/status display.
- `SECURITY_AUDIT.md` - prior security hardening context.

## The Goal

The user wanted the functional follow-up work to proceed by priority after the M4 menu bar investigation.
The target end state was a macOS menu bar app that is closer to Windows feature parity, avoids disabled providers leaking stale values, and reduces remaining menu bar width instability.
The work also needed to stay small enough to verify locally with Swift build/smoke tests and produce a new app bundle.
After the code work, the user explicitly requested `/handoff` and a push to GitHub.

## Where We Are

- Current branch is `main`.
- Base commit before this follow-up work was `d304a12 Fix menu bar refresh visibility`.
- Remote `origin/main` matched local `HEAD` before this work when checked with `git ls-remote origin main`.
- Working tree before this handoff had five modified files:
- `README.md`
- `Sources/TokenTrackerCore/Localization.swift`
- `Sources/TokenTrackerCore/UsageService.swift`
- `Sources/TokenTrackerMenuBar/AppDelegate.swift`
- `Sources/TokenTrackerSmokeTests/main.swift`
- This handoff adds `plans/handoffs/HANDOFF_m4-menubar-stability_provider-controls-stable-width_2026-06-15.md`.
- `UsageService.refresh()` now calls `UsageSnapshotCachePolicy.apply(...)`.
- `UsageSnapshotCachePolicy.apply(...)` is public so the smoke test executable can directly validate stale-cache behavior.
- Stale cache is now only applied when the corresponding provider is enabled.
- Disabled Claude/Codex now preserve `ProviderUsage.unavailable(..., error: "Disabled")` instead of being replaced by stale cached API values.
- `Sources/TokenTrackerSmokeTests/main.swift` now tests that enabled Claude can use stale cache while disabled Codex does not.
- macOS `AppDelegate.configureMenu()` now adds a `Providers` submenu.
- The `Providers` submenu exposes Claude and Codex toggles using `Provider.allCases`.
- Selecting a provider toggle updates `settings.claudeEnabled` or `settings.codexEnabled`.
- Provider toggle changes rebuild the menu and call `refreshNow()` so the new enabled state is reflected promptly.
- macOS `AppDelegate.configureMenu()` now adds a `Refresh Interval` submenu.
- Refresh interval options are `30`, `60`, and `300` seconds.
- Selecting a refresh interval writes `settings.refreshInterval`, calls `scheduleTimer()`, and rebuilds the menu.
- `scheduleTimer()` now clamps the timer interval to at least `15` seconds with `max(15, settings.refreshInterval)`.
- `Localizer` now has `.providers` and `.refreshInterval` keys in English and Korean.
- `README.md` now lists refresh interval in the menu features.
- `AppDelegate.setStatusImage(_:, on:)` no longer always sets status length to the current image width.
- `setStatusImage` now uses `max(image.size.width + padding, reservedStatusItemLength())`.
- `reservedStatusItemLength()` renders a sample `UsageSnapshot` with `100%` values for the current display mode and provider label style.
- The reserved width reduces visible menu item shrink/expand during loading and value changes.
- `statusItemHorizontalPadding` is `10`, preserving the previous padding value.
- The 60-second timer no longer shows `AI ...` after parent seq 1, and this session further stabilizes the length for manual refresh and value-width changes.
- `relative(_:)` now uses `localizer.text(.ago)` even for values under 60 seconds.
- Korean language mode now formats recent updates as `5s` plus the localized suffix instead of hard-coded English `ago`.
- Swift build passed after all changes.
- Swift smoke tests passed after all changes.
- `git diff --check` passed after all changes.
- `scripts/build_app.sh` passed and rebuilt `.build/Token Tracker.app`.
- Windows tests were not run because `dotnet --info` returned `zsh:1: command not found: dotnet` earlier in the review.

## What We Tried (Chronological)

1. Confirmed no other worker had pushed after the prior commit by comparing local `HEAD` to `git ls-remote origin main`; both were `d304a124d65f5cb90809195243884523bbd97ca0`.
2. Ran a functional review at the user's request, starting from `rg --files`, `git status --short --branch`, and recent commit history.
3. Read `Sources/TokenTrackerMenuBar/AppDelegate.swift` around timer refresh, image rendering, menu construction, language changes, and relative time formatting.
4. Read `Sources/TokenTrackerCore/UsageService.swift`, `Settings.swift`, `DisplayFormatter.swift`, `Models.swift`, `CacheStore.swift`, and provider clients.
5. Read Windows `TrayAppContext.cs` and `CacheStore.cs` for feature parity comparison.
6. Found that Windows has `ProvidersMenu()` and `RefreshIntervalMenu()`, but macOS only had display mode, provider label style, language, launch at login, refresh, and quit.
7. Found that macOS `Settings` already had `claudeEnabled`, `codexEnabled`, and `refreshInterval`, so the missing feature was mainly UI and behavior wiring.
8. Found that macOS stale-cache fallback replaced unavailable current values with stale values regardless of `claudeEnabled` and `codexEnabled`.
9. Compared that with Windows `UsageSnapshotCachePolicy.Apply(...)`, which gates stale fallback on provider enabled state.
10. Ran `swift build`, `swift run TokenTrackerSmokeTests`, and `git diff --check` during review; all passed before making new changes.
11. Tried `dotnet --info` to see whether Windows tests could be run locally; it failed because `dotnet` is not installed.
12. Reported four priority items to the user: stale-cache disabled bug, macOS provider controls, residual status width churn, and Korean relative time.
13. User asked to create a plan and execute by priority.
14. Added public Swift `UsageSnapshotCachePolicy.apply(current:stale:claudeEnabled:codexEnabled:updatedAt:)`.
15. Updated `UsageService.refresh()` to call the new policy with the current enabled flags from `Settings`.
16. Added smoke test coverage proving enabled Claude can use stale cache and disabled Codex keeps `source == .unavailable`.
17. Added macOS menu provider controls with `isProviderEnabled(_:)`, `setProvider(_:enabled:)`, and `toggleProvider(_:)`.
18. Added macOS refresh interval controls with `refreshIntervalOptions`, `refreshIntervalTitle(_:)`, and `selectRefreshInterval(_:)`.
19. Added English/Korean localization for `Providers` and `Refresh Interval`.
20. Updated README's menu list to include refresh interval.
21. Added `statusItemHorizontalPadding` and `reservedStatusItemLength()` to avoid shrinking status item length below the current mode's expected maximum.
22. Used a sample snapshot with 100% values because `100%` is wider than `99%`, `10%`, `0%`, and `--`.
23. Kept the existing bitmap renderer instead of replacing it with a native AppKit attributed-title/template-image architecture in this pass.
24. Changed the sub-60-second branch of `relative(_:)` to use `localizer.text(.ago)`.
25. Re-ran `swift build`; it passed.
26. Re-ran `swift run TokenTrackerSmokeTests`; it passed and printed `TokenTrackerSmokeTests passed`.
27. Re-ran `git diff --check`; it passed with no output.
28. Rebuilt the app bundle with `scripts/build_app.sh`; it passed and printed `Built .build/Token Tracker.app`.
29. Checked `git status --short --branch`; only the intended five files were modified before this handoff.
30. User then requested `/handoff` and push, triggering this handoff.

## Key Decisions

- Kept this work on the existing `m4-menubar-stability` chain because it directly continues the parent's unresolved M4 width/rendering follow-up.
- Treated `HANDOFF_m4-menubar-stability_refresh-width-fix_2026-06-09.md` as the parent because its "Where We're Going" explicitly named stable-width AppKit status content as the next step if issues persisted.
- Fixed stale-cache behavior before adding provider UI because adding UI first would expose a broken disabled state.
- Made `UsageSnapshotCachePolicy` public rather than leaving the stale logic private in `UsageService`, because the current smoke test target can only access public APIs from `TokenTrackerCore`.
- Mirrored Windows cache policy semantics: stale data is useful for transient API failures, but only for providers the user has left enabled.
- Added macOS provider toggles rather than only correcting README, because settings and Windows UI already showed this was an intended feature.
- Added refresh interval menu because Windows already exposes it and macOS already had a persisted `refreshInterval` setting.
- Chose `30s`, `1m`, and `5m` options to match the Windows menu options.
- Clamped the scheduled timer to at least 15 seconds to avoid a bad external defaults value creating a very tight repeating timer.
- Stabilized width with a reserved maximum for the current display mode instead of forcing a single global width for every mode, so changing from `both` to `codexOnly` can still intentionally use less space.
- Did not replace the entire status renderer with AppKit native attributed titles in this pass because the smaller change addresses residual width churn and is easier to verify locally.
- Left the known appearance/tinting risk open because it needs direct UI verification on affected macOS/M4 configurations.
- Updated README minimally rather than rewriting broader docs.
- Did not commit automatically before the handoff because the handoff file itself must be included in the requested commit.

## Evidence & Data

| Git item | Value |
| --- | --- |
| Branch | `main` |
| Base commit | `d304a12 Fix menu bar refresh visibility` |
| Previous remote compare | local `HEAD` and `origin/main` both `d304a124d65f5cb90809195243884523bbd97ca0` |
| Pre-handoff modified files | 5 |
| Handoff file added | 1 |

| File | Change count before handoff |
| --- | ---: |
| `README.md` | 1 insertion |
| `Sources/TokenTrackerCore/Localization.swift` | 6 insertions |
| `Sources/TokenTrackerCore/UsageService.swift` | 44 line diff, 7 net additions shown by stat context |
| `Sources/TokenTrackerMenuBar/AppDelegate.swift` | 132 line diff, largest source change |
| `Sources/TokenTrackerSmokeTests/main.swift` | 21 insertions |
| Total before handoff | 191 insertions, 13 deletions |

| Command | Result |
| --- | --- |
| `swift build` | passed, `Build complete!` |
| `swift run TokenTrackerSmokeTests` | passed, `TokenTrackerSmokeTests passed` |
| `git diff --check` | passed, no output |
| `scripts/build_app.sh` | passed, `Built .build/Token Tracker.app` |
| `dotnet --info` | not available, `zsh:1: command not found: dotnet` |

Current changed files before adding this handoff:

```text
 M README.md
 M Sources/TokenTrackerCore/Localization.swift
 M Sources/TokenTrackerCore/UsageService.swift
 M Sources/TokenTrackerMenuBar/AppDelegate.swift
 M Sources/TokenTrackerSmokeTests/main.swift
```

Recent commit history at handoff creation:

```text
d304a12 Fix menu bar refresh visibility
3a61da4 Optimize macOS and Windows platform handling
099e506 Fix release Swift concurrency checks
160c45d Prepare v1.0.6 release
c89e86f Improve Claude usage fetch diagnostics
f7e3ee7 Merge pull request #1 from ChunSam/claude/code-security-audit-iOaYj
afba55a Add security audit summary document
88e545c Add defensive file-handling hardening
eed7c92 Harden Windows release workflow
962ffda Add app icon to macOS bundle
```

Core stale-cache policy shape:

```swift
public enum UsageSnapshotCachePolicy {
    public static func apply(
        current: UsageSnapshot,
        stale: UsageSnapshot?,
        claudeEnabled: Bool = true,
        codexEnabled: Bool = true,
        updatedAt: Date = Date()
    ) -> UsageSnapshot
}
```

New smoke test assertions:

```swift
expectEqual(enabledStaleSnapshot.claude.source, .staleCache, "Enabled Claude can use stale cache")
expectEqual(enabledStaleSnapshot.codex.source, .unavailable, "Disabled Codex does not use stale cache")
expectEqual(enabledStaleSnapshot.codex.error, "Disabled", "Disabled Codex keeps disabled reason")
```

Mac menu additions:

```swift
private let refreshIntervalOptions: [TimeInterval] = [30, 60, 300]
private func isProviderEnabled(_ provider: Provider) -> Bool
private func setProvider(_ provider: Provider, enabled: Bool)
@objc private func toggleProvider(_ sender: NSMenuItem)
@objc private func selectRefreshInterval(_ sender: NSMenuItem)
```

Stable width behavior:

```swift
let targetLength = max(image.size.width + statusItemHorizontalPadding, reservedStatusItemLength())
if abs(statusItem.length - targetLength) > 0.5 {
    statusItem.length = targetLength
}
```

App bundle output:

```text
Built .build/Token Tracker.app
```

## Code Analysis

- `UsageService.refresh()` reads `settings.claudeEnabled` and `settings.codexEnabled` before launching async fetch tasks.
- Disabled providers are represented as `ProviderUsage.unavailable(provider, error: "Disabled")`.
- Before this work, the stale-cache fallback ran only on availability, not enabled state, so disabled providers could be replaced by stale cached values.
- `UsageSnapshotCachePolicy.apply` now matches the Windows condition shape: enabled flag plus unavailable current plus available stale.
- `UsageSnapshotCachePolicy.apply` preserves `current.updatedAt` in the returned snapshot, matching prior behavior and Windows policy behavior.
- `markStale` updates the provider usage `source` to `.staleCache`, carries through the current failure error, and uses an injectable `updatedAt` for test determinism.
- `AppDelegate.configureMenu()` rebuilds the full menu each time settings change, so checkmarks and submenu state remain synchronized.
- `toggleProvider(_:)` calls `refreshNow()` after persisting the setting, so disabling a provider causes a refresh rather than waiting for the next timer tick.
- `selectRefreshInterval(_:)` calls `scheduleTimer()` immediately so the newly selected interval applies without restarting the app.
- `scheduleTimer()` retains the old repeating timer invalidation behavior and only changes the effective interval calculation.
- `reservedStatusItemLength()` uses the same existing render helpers as the live status path, so width reservation tracks current font, label style, icons, separator spacing, and display mode.
- `reservedStatusItemLength()` reserves width for the current mode/style, not for all possible modes.
- `sampleUsage(_:)` uses 100 percent values because the status title font is monospaced and `100%` is the widest expected percent token.
- The direct `NSImage.lockFocus()` renderer still exists; the work reduced width churn but did not solve all appearance/tint risks.
- `relative(_:)` still uses compact time units (`s`, `m`, `h`) and now only delegates the suffix to localization.

## Files Changed

### Source code

- `Sources/TokenTrackerCore/UsageService.swift` - extracted and reused `UsageSnapshotCachePolicy`; stale cache now respects provider enabled flags.
- `Sources/TokenTrackerMenuBar/AppDelegate.swift` - added provider toggles, refresh interval menu, timer interval clamp, stable status item reserved width, and localized sub-minute relative time.
- `Sources/TokenTrackerCore/Localization.swift` - added English/Korean labels for provider and refresh interval menu roots.

### Tests

- `Sources/TokenTrackerSmokeTests/main.swift` - added stale-cache policy assertions for enabled versus disabled providers.

### Documentation

- `README.md` - added refresh interval to the menu feature list.

### Handoffs

- `plans/handoffs/HANDOFF_m4-menubar-stability_provider-controls-stable-width_2026-06-15.md` - this continuity record.

### Generated artifacts

- `.build/Token Tracker.app` - regenerated locally by `scripts/build_app.sh`; not expected to be committed.

## User Feedback & Preferences (REQUIRED - never omit)

- User initially reported that the app works on MacBook M1 but disappears from the menu bar on M4 after a regular interval.
- User clarified that the process remains alive when the menu bar item disappears.
- User wanted the root cause investigated.
- User asked to add a GitHub collaborator.
- User asked to inspect the GitHub friend/follow list and present usernames.
- User selected `sim9609`.
- User requested `write` permission for `sim9609`.
- User previously asked for handoff, commit, and push after the first M4 fix.
- User asked whether there were functional additions or modifications left.
- User accepted the priority ordering and asked to create an execution plan.
- User asked to execute the plan in priority order, not just propose it.
- User now explicitly requested `/handoff` and push.
- User communicates in Korean and prefers direct execution over extended back-and-forth.

## Where We're Going

- Commit the five changed files plus this handoff file.
- Push the commit to `origin/main`.
- Ask the M4 user to test the new build across multiple automatic refresh intervals and at least one manual refresh.
- If the M4 item still disappears or becomes invisible, replace the direct bitmap renderer with AppKit-native status content or a stable custom view.
- If collaborator access matters, verify `sim9609` has accepted the pending invite before assuming repository access is active.

## Risks & Blockers

- The M4 menu bar issue still needs live verification on the affected machine.
- The current renderer still uses direct `NSImage.lockFocus()` bitmap drawing, so appearance/tint edge cases can remain on newer macOS.
- The reserved-width approach may leave extra horizontal padding when the user manually refreshes or displays a shorter mode, but it avoids periodic shrink/expand behavior.
- Windows tests were not run locally because `.NET` is not installed in this environment.
- GitHub push requires network access; previous push commands in this workspace have used approved `git push` escalation when needed.

## Open Questions

- Does the affected M4 still reproduce after this reserved-width follow-up?
- Does the affected M4 reproduce in `lowestRemaining`, or only `both + icon`?
- Should macOS later move from bitmap status images to AppKit-managed template images/attributed titles?
- Should the app expose custom refresh intervals beyond `30s`, `1m`, and `5m`?
- Should Swift core add more unit-testable injection points for `UsageService` clients?

## Quick Start for Next Session

```bash
# Parent context
sed -n '1,360p' plans/handoffs/HANDOFF_m4-menubar-stability_refresh-width-fix_2026-06-09.md

# Current handoff
sed -n '1,360p' plans/handoffs/HANDOFF_m4-menubar-stability_provider-controls-stable-width_2026-06-15.md

# Key files to read first
sed -n '1,220p' Sources/TokenTrackerMenuBar/AppDelegate.swift
sed -n '1,120p' Sources/TokenTrackerCore/UsageService.swift
sed -n '1,120p' Sources/TokenTrackerCore/Localization.swift
sed -n '1,120p' Sources/TokenTrackerSmokeTests/main.swift

# Verify current state
git status --short --branch
swift build
swift run TokenTrackerSmokeTests
git diff --check

# Next action
# After push, have the M4 user test the rebuilt app across several 30s/60s refresh intervals and one manual refresh.
```
