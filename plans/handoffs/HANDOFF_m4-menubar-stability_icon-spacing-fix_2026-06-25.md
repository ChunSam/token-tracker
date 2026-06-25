# M4 menu bar icon spacing fix

**Date:** 2026-06-25
**Status:** COMPLETED
**Bead(s):** none
**Epic:** Token Tracker macOS runtime stability
**Chain:** `m4-menubar-stability` seq `3`
**Parent:** `HANDOFF_m4-menubar-stability_provider-controls-stable-width_2026-06-15.md`
**Prior chain:** `HANDOFF_m4-menubar-stability_refresh-width-fix_2026-06-09.md` > `HANDOFF_m4-menubar-stability_provider-controls-stable-width_2026-06-15.md` > this

---

## Stale References

- `AppDelegate.setStatusImage(_:, on:)` - not found in current source; status rendering was moved into `Sources/TokenTrackerMenuBar/StatusItemRenderer.swift` during the macOS menu bar refactor.
- `reservedStatusItemLength()` - removed by this session; it was the parent seq 2 width reservation helper and caused the visible extra menu bar spacing the user reported.
- `sampleUsage(_:)` - removed by this session because it only existed to feed `reservedStatusItemLength()`.

## Related Handoffs

- `HANDOFF_macos-menubar-refactor_appdelegate-modularization_2026-06-15.md` - related refactor that introduced `StatusItemRenderer` as the owner of status item rendering.
- `HANDOFF_macos-usage-ux_windows-parity_2026-06-22.md` - related cross-platform UX work; not part of the M4 stability chain.
- `HANDOFF_platform-optimization_macos-windows-hardening_2026-06-09.md` - related platform hardening and macOS status tinting context.

## Since Last Handoff

- Parent seq 2 stabilized status item width by reserving the maximum expected width for the current display mode and provider label style.
- That reduced periodic M4 disappearance risk, but it left visible unused space around the menu bar item, especially in `both + icon` mode.
- User supplied a screenshot showing the Token Tracker menu bar item with extra blank space around the icon/text group.
- Current source no longer has the parent `AppDelegate.setStatusImage` path because rendering now lives in `StatusItemRenderer`.
- This session narrowed the fix to `StatusItemRenderer` rather than touching menu building, provider settings, cache policy, or Windows code.
- The trajectory stays on the M4 menu bar stability path: reduce layout churn and make the item consume only the space it needs.

## Reference Documents

- `README.md` - user-facing app behavior, build, and install notes.
- `WORK_SUMMARY.md` - project overview and prior macOS menu bar architecture notes.
- `agent.md` - local project notes for menu bar behavior and build commands.

## The Goal

The user reported that the macOS menu bar icon had empty space on both sides.
The visual issue appeared after the prior stable-width work that intentionally reserved a wider menu bar slot to reduce M4 disappearance risk.
The goal for this session was to remove the unnecessary horizontal gap without reintroducing the old interval-based width collapse.
The result should keep the menu bar item compact while still rendering the same provider percentages and warning color.

## Where We Are

- Current branch is `main`.
- Working tree before this handoff had one modified source file: `Sources/TokenTrackerMenuBar/StatusItemRenderer.swift`.
- This handoff adds `plans/handoffs/HANDOFF_m4-menubar-stability_icon-spacing-fix_2026-06-25.md`.
- Latest pushed commit before this work was `d2d94ff Align Windows tray UX with macOS updates`.
- `StatusItemRenderer` owns `NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)`.
- `StatusItemRenderer` still renders the whole status item as an `NSImage`.
- `statusItemHorizontalPadding` was reduced from `10` to `4`.
- `setStatusImage(_:, on:)` now uses `ceil(image.size.width + statusItemHorizontalPadding)`.
- The prior `max(image width, reservedStatusItemLength(...))` behavior was removed.
- `reservedStatusItemLength(mode:labelStyle:)` was removed.
- `sampleUsage(_:)` was removed.
- `button.imageScaling = .scaleNone` was added so AppKit does not stretch the generated status image.
- A new `StatusIcon` struct wraps an `NSImage` and its visible `contentRect`.
- `StatusSegment.icon` now carries `StatusIcon` instead of raw `NSImage`.
- `loadIcon(named:)` now computes a visible content rectangle for each PNG.
- `drawIcon(_:in:tint:)` draws only the alpha-bounded visible content rect into the 14x14 menu bar icon slot.
- `visibleContentRect(for:)` scans the decoded `CGImage` alpha channel to find non-transparent bounds.
- The alpha scan handles `.first`, `.premultipliedFirst`, `.none`, `.noneSkipFirst`, and `.noneSkipLast` alpha layouts.
- If the image cannot be decoded or has no visible alpha bounds, the full image rect is used as a fallback.
- Placeholder and loading functions now keep their external signatures but ignore mode/style internally because those values are no longer needed for width reservation.
- The supplied icon resources were checked: `claudeTemplate@2x.png` is `48x48`; `codexTemplate@2x.png` is `36x36`.
- Alpha-bound check showed both icons have visible content of `34x34` pixels.
- Claude's raw image had transparent alpha bounds from `7,7` to `40,40`, explaining part of the apparent side padding.
- Codex's raw image had transparent alpha bounds from `1,1` to `34,34`.
- `swift build` passed after the renderer change.
- `swift run TokenTrackerSmokeTests` passed after the renderer change.
- `git diff --check` passed after the renderer change.
- `scripts/build_app.sh` passed and rebuilt `.build/Token Tracker.app`.
- Existing `TokenTrackerMenuBar` process was terminated and `.build/Token Tracker.app` was reopened.
- The new process started with PID `58986`.
- A full screenshot was captured to `/private/tmp/token-tracker-full-after.png`.
- The full screenshot was `3840x2160`.
- Visual inspection confirmed the item displayed as `66% · 8%` and no longer held the larger maximum reserved width from seq 2.
- The generated screenshot and `.build/Token Tracker.app` are local artifacts and should not be committed.

## What We Tried (Chronological)

1. Started from the user's screenshot showing empty space around the menu bar icon/status group.
2. Searched for macOS status item code with `rg` and found `Sources/TokenTrackerMenuBar/StatusItemRenderer.swift`.
3. Read `StatusItemRenderer.swift` and confirmed it still used a bitmap status image and `NSStatusItem.variableLength`.
4. Found `statusItemHorizontalPadding = 10`.
5. Found `setStatusImage` used `max(image.size.width + padding, reservedStatusItemLength(...))`.
6. Connected the visible blank space to the seq 2 reserved-width strategy.
7. Checked icon resource dimensions with `file` and `sips`; Claude was `48x48`, Codex was `36x36`.
8. Ran a Swift alpha-bound check over both PNGs.
9. Confirmed both icons have the same visible `34x34` content, but Claude carries larger transparent margins.
10. Replaced raw `NSImage` icon segments with a `StatusIcon` wrapper containing `image` plus `contentRect`.
11. Removed `reservedStatusItemLength()` and `sampleUsage(_:)` to stop reserving a maximum mode width.
12. Reduced horizontal padding from `10` to `4`.
13. Set status item length to the actual image width plus padding, rounded up.
14. Added `button.imageScaling = .scaleNone`.
15. Added `visibleContentRect(for:)` to crop transparent PNG margins when drawing provider icons.
16. First alpha scan assumed the alpha byte was last; then it was tightened to account for `CGImage.alphaInfo`.
17. Added explicit fallback for alpha-less images so a future non-alpha icon is not accidentally clipped.
18. Ran `swift build`; it passed.
19. Ran `git diff --check`; it passed.
20. Ran `swift run TokenTrackerSmokeTests`; it passed.
21. Rebuilt the app bundle with `scripts/build_app.sh`; it passed.
22. Confirmed the running app was from `/Users/jkl/Projects/Token tracker/.build/Token Tracker.app/Contents/MacOS/TokenTrackerMenuBar`.
23. Terminated the old process with `pkill -x TokenTrackerMenuBar`.
24. Reopened `.build/Token Tracker.app`.
25. Confirmed the new process with `pgrep -x TokenTrackerMenuBar -laf`, returning PID `58986`.
26. Captured a small menu bar screenshot first, but the app item was partly off the captured region.
27. Captured the full screen to `/private/tmp/token-tracker-full-after.png`.
28. Visual inspection of the full screenshot confirmed the menu item was compact compared with the user's original screenshot.

## Key Decisions

- Kept this on the `m4-menubar-stability` chain because the issue is a direct follow-up to the M4 status width work.
- Used parent seq 2 because it introduced the maximum-width reservation that created the new visual spacing tradeoff.
- Removed the maximum reserved width instead of just lowering the `100%` sample because the user specifically objected to empty space.
- Kept a small `4pt` padding rather than `0` to avoid clipping against adjacent menu extras.
- Cropped PNG transparent margins at draw time instead of editing the resource files, so the renderer remains robust if resources are regenerated.
- Left the bitmap renderer in place because this was a compact spacing fix, not a full AppKit-native status item rewrite.
- Did not modify Windows tray code because the reported issue and screenshot were macOS menu bar specific.
- Did not commit `.build/Token Tracker.app` or screenshots because they are generated/local verification artifacts.

## Evidence & Data

| Item | Evidence |
| --- | --- |
| Branch | `main` |
| Pre-handoff status | ` M Sources/TokenTrackerMenuBar/StatusItemRenderer.swift` |
| Tracked diff stat | `1 file changed, 77 insertions(+), 76 deletions(-)` |
| Latest prior commit | `d2d94ff Align Windows tray UX with macOS updates` |
| Running process after relaunch | PID `58986` |
| Screenshot path | `/private/tmp/token-tracker-full-after.png` |
| Screenshot size | `3840x2160` |

| Resource | Raw size | Visible alpha bounds | Visible size |
| --- | ---: | --- | ---: |
| `claudeTemplate@2x.png` | `48x48` | `7,7-40,40` | `34x34` |
| `codexTemplate@2x.png` | `36x36` | `1,1-34,34` | `34x34` |

| Command | Result |
| --- | --- |
| `swift build` | passed, `Build complete!` |
| `swift run TokenTrackerSmokeTests` | passed, `TokenTrackerSmokeTests passed` |
| `git diff --check` | passed, no output |
| `scripts/build_app.sh` | passed, `Built .build/Token Tracker.app` |
| `pgrep -x TokenTrackerMenuBar -laf` | returned `58986` after relaunch |

Current source diff summary:

```text
.../TokenTrackerMenuBar/StatusItemRenderer.swift | 153 +++++++++++----------
1 file changed, 77 insertions(+), 76 deletions(-)
```

Important behavior change:

```swift
let targetLength = ceil(image.size.width + statusItemHorizontalPadding)
if abs(statusItem.length - targetLength) > 0.5 {
    statusItem.length = targetLength
}
```

## Code Analysis

- `StatusItemRenderer` remains `@MainActor` because it owns AppKit status item and drawing operations.
- `StatusSegment.icon(StatusIcon)` avoids passing around image data without knowing its visible bounds.
- `statusTitleImage(segments:iconTint:)` still uses a fixed `14x14` icon slot and `5pt` icon-to-text spacing.
- `drawIcon` now uses `icon.image.draw(in: rect, from: icon.contentRect, operation: .destinationIn, fraction: 1.0)`.
- `visibleContentRect(for:)` maps pixel bounds back into `NSImage` point coordinates using `scaleX` and `scaleY`.
- The y-coordinate conversion uses `height - maxY - 1` to convert from top-left pixel iteration to AppKit image coordinates.
- Removing `reservedStatusItemLength` means the status item can change width as values change, but it no longer holds the visibly oversized 100% sample width.
- Automatic refresh still avoids the old `AI ...` shrink path from seq 1, so the worst periodic width collapse remains fixed.

## Files Changed

### Source code

- `Sources/TokenTrackerMenuBar/StatusItemRenderer.swift` - removed maximum reserved status width, reduced padding, disabled image scaling, and added alpha-bound icon drawing to reduce visible blank menu bar space.

### Handoffs

- `plans/handoffs/HANDOFF_m4-menubar-stability_icon-spacing-fix_2026-06-25.md` - this continuity record.

### Generated artifacts

- `.build/Token Tracker.app` - rebuilt locally for real app verification; not committed.
- `/private/tmp/token-tracker-full-after.png` - verification screenshot; not committed.
- `/private/tmp/token-tracker-menubar-after.png` - first cropped screenshot; not committed.

## User Feedback & Preferences (REQUIRED - never omit)

- User reported the original M4 symptom: app disappears from the menu bar while process remains alive.
- User prefers direct fixes and verification over only explanation.
- User later asked to remove duplicated settings items from the tray/menu and accepted code changes without extra planning overhead.
- User supplied a screenshot showing blank space around the menu bar icon/status item.
- User requested: "메뉴바 아이콘 양옆으로 빈공간이 생기는데 수정해줘".
- User then requested: `[$handoff](/Users/jkl/.codex/skills/handoff/SKILL.md) 하고 푸시`.
- User expects handoff, commit, and push after implementation phases.
- User communicates in Korean.

## Where We're Going

- Stage `StatusItemRenderer.swift` plus this handoff file.
- Commit with a focused message for the menu bar icon spacing fix.
- Push the commit to `origin/main`.
- Have the M4 user verify the compact menu item across several automatic refresh intervals.
- If disappearance or invisible rendering returns, prioritize a full AppKit-native status item renderer over further bitmap tuning.

## Risks & Blockers

- The full fix has only been visually verified on the current Mac, not on the user's affected M4 hardware.
- Removing maximum width reservation may allow small width changes when values move between `9%`, `10%`, and `100%`; the prior automatic `AI ...` collapse remains fixed.
- The renderer still uses bitmap drawing, so future macOS appearance/tint issues remain possible.
- Push requires network access.

## Open Questions

- Does the affected M4 still show any spacing after pulling this commit?
- Does compact width remain stable enough over several automatic refresh cycles?
- Should the next M4 stability pass replace bitmap drawing with AppKit text/template image rendering?

## Quick Start for Next Session

```bash
# Parent chain context
sed -n '1,360p' plans/handoffs/HANDOFF_m4-menubar-stability_refresh-width-fix_2026-06-09.md
sed -n '1,360p' plans/handoffs/HANDOFF_m4-menubar-stability_provider-controls-stable-width_2026-06-15.md

# Current handoff
sed -n '1,260p' plans/handoffs/HANDOFF_m4-menubar-stability_icon-spacing-fix_2026-06-25.md

# Key file to read first
sed -n '1,330p' Sources/TokenTrackerMenuBar/StatusItemRenderer.swift

# Verify current state
git status --short --branch
swift build
swift run TokenTrackerSmokeTests
git diff --check

# Next action
# Ask the M4 user to test the pushed build through multiple automatic refresh intervals and report if width or visibility still changes.
```
