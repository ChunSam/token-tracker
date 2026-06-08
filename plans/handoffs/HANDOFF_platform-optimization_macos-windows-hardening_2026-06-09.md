# macOS and Windows platform optimization hardening

**Date:** 2026-06-09
**Status:** COMPLETED
**Bead(s):** none
**Epic:** Token Tracker platform optimization
**Chain:** `platform-optimization` seq `1`
**Parent:** none — first in chain
**Prior chain:** none — first in chain

---

## Related Handoffs

- `HANDOFF_claude-usage-stability_macos-auth-fallback_2026-06-05.md` — earlier macOS Claude auth fallback and stale cache reliability work; related but narrower.
- `HANDOFF_claude-usage-stability_429-cooldown-plan_2026-06-06.md` — earlier macOS Claude 429 cooldown and plan display work; related because this session carried the same 429/plan ideas into Windows.

## Reference Documents

- `agent.md` — project architecture notes and validation cautions.
- `WORK_SUMMARY.md` — historical project summary, build commands, and feature scope.
- `SECURITY_AUDIT.md` — prior security hardening notes and release workflow context.
- `README.md` — user-facing install, build, and release instructions.

## The Goal

The user first asked to identify code improvements for macOS and Windows environment optimization.
After the review, they asked to proceed with macOS-only improvements, then Windows-related improvements.
The end state was a Token Tracker codebase with better platform-specific runtime behavior, more consistent macOS/Windows reliability semantics, and broader release architecture support.
The user then explicitly asked for `/handoff` plus commit and push.
This handoff preserves the exact state before the requested commit/push sequence.

## Where We Are

- Branch at handoff creation: `main`.
- Latest committed hash before this handoff: `099e506 Fix release Swift concurrency checks`.
- Working tree has source, workflow, docs, and this handoff file changed.
- macOS refresh now starts Claude and Codex fetches in parallel through `UsageService.refresh()`.
- macOS network clients were moved off `@MainActor` where practical.
- macOS Claude rate-limit state was moved to an actor to avoid data races after removing main-actor isolation from the client.
- macOS `HTTPClient` is now `Sendable`, and `UsageError` is `Sendable`.
- macOS `CodexUsageClient` and `ClaudeUsageClient` are now `Sendable`.
- macOS menu bar rendering now picks black or white text/icon tint based on the status button's effective appearance.
- macOS appearance changes are observed through `AppleInterfaceThemeChangedNotification`, and the status title is redrawn when the theme changes.
- macOS `.app` build script now accepts `APP_ARCHS`.
- macOS universal build was verified with `APP_ARCHS="arm64 x86_64" scripts/build_app.sh`.
- The generated `.build/Token Tracker.app/Contents/MacOS/TokenTrackerMenuBar` was verified as a fat binary with `x86_64 arm64`.
- Release workflow macOS build now sets `APP_ARCHS: arm64 x86_64`.
- Windows now has `UsageSource.StaleCache`.
- Windows now has `AppPaths.SnapshotCachePath` pointing to `usage-cache.json` under the app data directory.
- Windows now has `CacheStore` for JSON snapshot load/save with a temp-file move.
- Windows now has `UsageSnapshotCachePolicy.Apply()` for stale provider substitution.
- Windows tray refresh now loads stale cache for up to one hour and saves the resulting snapshot after each refresh.
- Windows stale cache is not applied for disabled providers.
- Windows `UsageClient` now reads `Retry-After` for non-success HTTP responses.
- Windows `UsageClient` now throws `UsageHttpException` internally for non-2xx HTTP statuses.
- Windows Claude fetch now stores cooldown state after HTTP 429.
- Windows Claude fetch now skips network calls during the active cooldown window.
- Windows Claude cooldown default is five minutes when no `Retry-After` is present.
- Windows Claude cooldown minimum is two minutes.
- Windows timeout handling now returns provider-specific unavailable messages instead of generic cancellation text.
- Windows `UsageClient` constructor now accepts an optional `homeDirectory` to make credential-dependent tests deterministic.
- Windows `CredentialReader` now exposes `ReadClaudeCredential()` with token plus optional plan.
- Windows `UsageParser.ParseClaudeUsage()` now reads plan fields from the Claude usage response and falls back to credential metadata.
- Windows tests now include Claude plan parsing, credential plan fallback, stale cache policy, cache store load/save, and Claude 429 backoff coverage.
- Windows app project now declares `RuntimeIdentifiers` as `win-x64;win-arm64`.
- Release workflow Windows job now runs a matrix for `win-x64` and `win-arm64`.
- Standalone Windows release workflow now runs the same runtime matrix.
- README now documents Windows ARM64 publish and macOS universal build usage.
- `git diff --check` passed after the macOS and Windows changes.
- `swift run TokenTrackerSmokeTests` passed after the macOS and Windows changes.
- `swift build -c release` passed after the macOS AppDelegate changes.
- `dotnet run --project windows/TokenTracker.Windows.Tests/TokenTracker.Windows.Tests.csproj` could not run locally because `dotnet` is not installed on this Mac.
- No Windows build was actually compiled in this local environment.
- No app UI was launched during the final Windows work.
- A prior unsupported SwiftPM command temporarily corrupted build state; `swift package clean` fixed it.

## What We Tried (Chronological)

1. The user asked: `작업 예정사항 있으면 알려줘`.
   The response was that no planned work was queued.

2. The user asked for code improvements needed for macOS and Windows environment optimization.
   The repository was inspected with `rg --files`, `git status --short`, and targeted `nl -ba` reads across Swift, C#, scripts, workflows, and docs.

3. Initial review found the project split:
   macOS is Swift/AppKit in `Sources/TokenTrackerCore` and `Sources/TokenTrackerMenuBar`.
   Windows is .NET WinForms in `windows/TokenTracker.Windows*`.

4. The review identified major macOS and Windows gaps:
   macOS fetch was sequential; Windows lacked stale cache, Claude 429 cooldown, Claude plan fallback, and ARM64 release artifacts.

5. The user then asked to proceed with macOS-related improvements only.
   A plan was created with four steps: parallel Swift refresh, appearance-aware menu rendering, universal app build support, and verification.

6. First macOS code path changed `HTTPClient`, `ClaudeUsageClient`, and `CodexUsageClient` from main-actor-isolated to `Sendable` where needed.
   `ClaudeRateLimitState` became an actor.

7. `UsageService.refresh()` was changed to use `async let` for Claude and Codex fetches.
   Local copies of the clients and enabled flags are captured before starting the async lets.

8. `AppDelegate` status rendering was changed to use appearance-aware text/icon tint.
   The initial attempt used `NSColor.resolvedColor(with:)`.

9. Universal macOS build support was added to `scripts/build_app.sh`.
   The script now reads `APP_ARCHS`, builds each architecture, and uses `xcrun lipo` when there is more than one architecture.

10. The macOS release workflow was updated with `APP_ARCHS: arm64 x86_64`.
    README was updated to document `APP_ARCHS="arm64 x86_64" scripts/build_app.sh`.

11. The first universal build attempt failed inside the sandbox because SwiftPM could not write to the user cache under `/Users/jkl/.cache/clang/ModuleCache`.
    The same command was re-run with escalation.

12. The escalated universal build then failed on a real compile error:
    `Sources/TokenTrackerMenuBar/AppDelegate.swift:271:22: error: value of type 'NSColor' has no member 'resolvedColor'`.

13. The AppDelegate color logic was changed away from `resolvedColor(with:)`.
    It now uses `effectiveAppearance.bestMatch(from: [.darkAqua, .aqua])` and returns white for dark and black otherwise.

14. `swift build -c release` and `swift run TokenTrackerSmokeTests` were re-run and passed.

15. A build script optimization was attempted:
    `swift build -c release --product TokenTrackerMenuBar --arch ...`.
    This was rejected because SwiftPM in this environment failed with:
    `No target named 'TokenTrackerMenuBar-arm64-apple-macosx-release.exe' in build description`.

16. The product-limited build attempt was reverted.
    A later retry failed with:
    `command ... swift-version--1AB21518FC5DEDBE.txt not registered`.

17. `swift package clean` was run to clear the bad SwiftPM build state.
    After that, the original `swift build -c release --arch ...` based script worked again.

18. The verified universal build command was:
    `APP_ARCHS="arm64 x86_64" scripts/build_app.sh`.
    It completed and printed `Built .build/Token Tracker.app`.

19. The generated binary was checked with `lipo -info`.
    Output included `Architectures in the fat file ... are: x86_64 arm64`.

20. The user then asked to proceed with Windows-related code.
    A plan was created: 429 handling, stale cache, tests, release architecture support, and validation.

21. Windows `Models.cs` was changed to add `UsageSource.StaleCache`.

22. Windows `AppPaths.cs` was changed to add `SnapshotCachePath`.

23. New Windows Core file `CacheStore.cs` was added.
    It contains `CacheStore` and `UsageSnapshotCachePolicy`.

24. Windows `CredentialReader.cs` was changed to add `ClaudeCredential` and `ReadClaudeCredential()`.
    `ReadClaudeAccessToken()` now delegates to `ReadClaudeCredential().AccessToken`.

25. Windows `UsageParser.cs` was changed so `ParseClaudeUsage()` accepts `fallbackPlan` and reads plan fields from Claude API response JSON.

26. Windows `UsageClient.cs` was changed substantially.
    `SendForJsonAsync()` now receives a service name and throws `UsageHttpException` for non-success status codes.

27. `UsageHttpException` was added in `UsageClient.cs`.
    Its message format matches the macOS style: `HTTP 429 from Claude API; retrying after 5m`.

28. `ClaudeRateLimitState` was added in `UsageClient.cs`.
    It stores a future retry time under a lock and exposes `CurrentError()`, `BackOff()`, and `Clear()`.

29. Windows `TrayAppContext.RefreshAsync()` now creates a fresh snapshot, applies stale cache with the current provider enabled flags, saves the snapshot, then updates icon and tooltip.

30. Windows tests were extended with an in-memory `QueueHttpMessageHandler`.
    This lets the smoke test verify 429 backoff without network access.

31. Windows release runtime support was expanded from `win-x64` only to `win-x64;win-arm64`.

32. `.github/workflows/release.yml` Windows build job was converted to a matrix over `win-x64` and `win-arm64`.

33. `.github/workflows/windows-release.yml` was converted to the same matrix.

34. README was updated to mention `-r win-arm64` and the `win-arm64/publish` output directory.

35. Validation after Windows work:
    `git diff --check` passed.
    `swift run TokenTrackerSmokeTests` passed.
    `dotnet run --project windows/TokenTracker.Windows.Tests/TokenTracker.Windows.Tests.csproj` failed because `dotnet` is not installed.

36. The user then asked: `/handoff 하고 커밋 푸쉬`.
    This handoff file was created before staging, committing, and pushing.

## Key Decisions

- Treat this as a new `platform-optimization` chain, not a child of the Claude usage stability chain.
- Keep older Claude stability handoffs as related references because they explain why 429, stale cache, and plan fallback matter.
- Use `async let` in macOS `UsageService` rather than adding a new abstraction.
- Move Claude cooldown state to an actor in Swift rather than keeping the whole Claude client on `MainActor`.
- Do not use `NSColor.resolvedColor(with:)` because the local SDK lacks that API.
- Use appearance best-match logic for macOS menu tinting because it compiled with the local SDK.
- Keep the macOS build script default to current architecture, and enable universal output only when `APP_ARCHS` specifies multiple architectures.
- Do not keep the attempted `swift build --product ... --arch` optimization because it broke SwiftPM in this environment.
- Use Windows stale cache only for enabled providers to avoid showing cached values for providers the user disabled.
- Store Windows usage cache as JSON in app data, parallel to the Windows settings location.
- Implement Windows 429 cooldown in `UsageClient`, not in the UI layer, so future callers also benefit.
- Keep Windows cooldown state in memory only; no persisted rate-limit state was added.
- Use `HttpResponseMessage.Headers.RetryAfter` rather than manually parsing the raw header string.
- Add optional `homeDirectory` to `UsageClient` for tests instead of introducing a full credential-reader interface.
- Expand Windows release artifacts to `win-arm64` now because the project already publishes self-contained single-file builds.
- Do not install .NET locally during this session; report that Windows tests were blocked by missing `dotnet`.

## Evidence & Data

| Command | Result | Notes |
| --- | --- | --- |
| `git branch --show-current` | `main` | Current branch before handoff. |
| `git status --short` | modified files plus new `CacheStore.cs` | Working tree is dirty before commit. |
| `git diff --stat` | `17 files changed, 456 insertions(+), 87 deletions(-)` before handoff file | Does not include this handoff file. |
| `git log --oneline -20` | latest `099e506 Fix release Swift concurrency checks` | Base commit before this session's commit. |
| `git diff --check` | passed | Run after macOS and Windows changes. |
| `swift run TokenTrackerSmokeTests` | passed | Re-run after Windows changes as a regression check. |
| `swift build -c release` | passed | Passed after macOS AppDelegate compile fix. |
| `APP_ARCHS="arm64 x86_64" scripts/build_app.sh` | passed | Required escalation because SwiftPM needed user cache access. |
| `lipo -info .build/Token\ Tracker.app/Contents/MacOS/TokenTrackerMenuBar` | `x86_64 arm64` | Verified universal binary. |
| `dotnet run --project windows/TokenTracker.Windows.Tests/TokenTracker.Windows.Tests.csproj` | `zsh:1: command not found: dotnet` | Windows tests not executed locally. |

macOS universal build failure history:

| Attempt | Command | Result | Follow-up |
| --- | --- | --- | --- |
| 1 | `APP_ARCHS="arm64 x86_64" scripts/build_app.sh` | sandbox denied SwiftPM user cache | Re-ran with escalation. |
| 2 | same command escalated | `NSColor` had no `resolvedColor` member | Replaced API usage. |
| 3 | product-limited script | SwiftPM `No target named ... .exe` error | Reverted product optimization. |
| 4 | original arch-loop script after bad state | `swift-version... not registered` | Ran `swift package clean`. |
| 5 | original arch-loop script after clean | passed | Verified with `lipo -info`. |

Windows test additions:

| Test area | Expected result |
| --- | --- |
| Claude API `plan_type` | `UsageParser.ParseClaudeUsage(...).Plan == "max"` |
| Claude fallback plan | `ParseClaudeUsage(..., fallbackPlan: "team").Plan == "team"` |
| Credentials plan | `ReadClaudeCredential(home).Plan == "max"` |
| Claude 429 first call | source unavailable, error begins `HTTP 429 from Claude API; retrying after`, HTTP call count `1` |
| Claude 429 during backoff | source unavailable, same error prefix, HTTP call count remains `1` |
| Stale cache policy | failed Claude replaced with stale Claude source `StaleCache` and prior percent `63` |
| Disabled provider policy | disabled Claude remains `Unavailable`, does not use stale cache |
| Cache store | saved snapshot loads and preserves Claude 5h percent `63` |

Changed file count before handoff file:

| Group | Count |
| --- | ---: |
| GitHub workflows | 2 |
| README/docs | 1 |
| macOS Swift/source scripts | 6 |
| Windows C# source/tests/project | 8 modified + 1 new |
| Total stat | 17 tracked files changed + 1 untracked new file |

Important raw outputs:

```text
Architectures in the fat file: .build/Token Tracker.app/Contents/MacOS/TokenTrackerMenuBar are: x86_64 arm64
```

```text
zsh:1: command not found: dotnet
```

```text
Sources/TokenTrackerMenuBar/AppDelegate.swift:271:22: error: value of type 'NSColor' has no member 'resolvedColor'
```

```text
error: No target named 'TokenTrackerMenuBar-arm64-apple-macosx-release.exe' in build description
```

```text
error: failed to write auxiliary file: command ... swift-version--1AB21518FC5DEDBE.txt not registered
```

## Code Analysis

- `Sources/TokenTrackerCore/UsageService.swift` remains `@MainActor`, but it captures settings and client values before starting parallel provider fetches.
- `Sources/TokenTrackerCore/ClaudeUsageClient.swift` is no longer `@MainActor`; only `ClaudeRateLimitState` serializes mutable cooldown state.
- `Sources/TokenTrackerCore/HTTPClient.swift` still returns `Any` from JSON parsing; no typed decoder was introduced.
- `Sources/TokenTrackerMenuBar/AppDelegate.swift` still renders status content as an `NSImage`; it now chooses tint based on `.darkAqua` vs `.aqua`.
- `scripts/build_app.sh` still copies the SwiftPM resource bundle from the first architecture's release directory.
- `scripts/build_app.sh` uses `mktemp -d` for both executable staging and iconset staging, and cleans both through a shared trap.
- `windows/TokenTracker.Windows.Core/CacheStore.cs` uses `File.Move(tempPath, Path, overwrite: true)` after writing JSON.
- `UsageSnapshotCachePolicy.Apply()` returns a new `UsageSnapshot` using `current.UpdatedAt`, while stale provider rows receive a fresh provider-level `UpdatedAt`.
- `windows/TokenTracker.Windows.Core/UsageClient.cs` stores Claude cooldown in memory only; app restart clears the cooldown.
- `UsageHttpException.FormatRetryAfter()` mirrors Swift formatting: seconds below 60, minutes below 60, then hours/minutes.
- `windows/TokenTracker.Windows/TrayAppContext.cs` applies cache after both provider tasks complete and before `SetIcon(snapshot)`.
- `windows/TokenTracker.Windows.Tests/Program.cs` uses a fake message handler instead of live HTTP.

## Files Changed

### macOS source code

- `Sources/TokenTrackerCore/HTTPClient.swift` — removed main-actor isolation, made `HTTPClient` `Sendable`, made `UsageError` `Sendable`.
- `Sources/TokenTrackerCore/CodexUsageClient.swift` — removed main-actor isolation and made the client `Sendable`.
- `Sources/TokenTrackerCore/ClaudeUsageClient.swift` — removed main-actor isolation, made the client `Sendable`, converted cooldown state to an actor.
- `Sources/TokenTrackerCore/UsageService.swift` — parallelized provider fetches with `async let`.
- `Sources/TokenTrackerMenuBar/AppDelegate.swift` — appearance-aware menu bar tinting and theme-change observer.

### macOS build/config/docs

- `scripts/build_app.sh` — added `APP_ARCHS`, per-arch Swift builds, `lipo` universal output, staged executable temp dir.
- `.github/workflows/release.yml` — macOS job now sets `APP_ARCHS: arm64 x86_64`.
- `README.md` — documented macOS universal build command.

### Windows source code

- `windows/TokenTracker.Windows.Core/AppPaths.cs` — added `SnapshotCachePath`.
- `windows/TokenTracker.Windows.Core/CacheStore.cs` — new Windows usage cache and stale-cache policy.
- `windows/TokenTracker.Windows.Core/CredentialReader.cs` — added `ClaudeCredential` and plan extraction from credentials.
- `windows/TokenTracker.Windows.Core/Models.cs` — added `UsageSource.StaleCache`.
- `windows/TokenTracker.Windows.Core/UsageClient.cs` — added `UsageHttpException`, `ClaudeRateLimitState`, Retry-After handling, timeout messages, optional test home.
- `windows/TokenTracker.Windows.Core/UsageParser.cs` — added Claude plan parsing and fallback plan support.
- `windows/TokenTracker.Windows/TrayAppContext.cs` — loads/saves cache and applies stale cache during refresh.

### Windows tests

- `windows/TokenTracker.Windows.Tests/Program.cs` — added plan parsing, credential plan, 429 backoff, stale cache, and cache store tests.

### Windows build/config/docs

- `windows/TokenTracker.Windows/TokenTracker.Windows.csproj` — runtime identifiers now include `win-x64;win-arm64`.
- `.github/workflows/release.yml` — Windows release job is now a runtime matrix.
- `.github/workflows/windows-release.yml` — standalone Windows release job is now a runtime matrix.
- `README.md` — documented `win-arm64` publish option and output path.

### Handoff

- `plans/handoffs/HANDOFF_platform-optimization_macos-windows-hardening_2026-06-09.md` — this file.

## User Feedback & Preferences

- User asked in Korean.
- User first asked if there were any planned tasks.
- User wanted macOS and Windows environment optimization improvement areas identified.
- User then explicitly scoped implementation to macOS only first.
- User asked to make a plan and proceed, not just propose.
- User then asked to proceed with Windows-related code as well.
- User again asked to make a plan and proceed.
- User did not ask for a Windows UI launch or live app test.
- User did not ask to install `.NET`; missing `dotnet` was reported rather than installing tooling.
- User now explicitly requested `/handoff` plus commit and push.
- User prefers direct execution once scope is clear.
- User accepts Korean status/final updates.

## Where We're Going

- Commit all current macOS, Windows, workflow, README, and handoff changes together.
- Push `main` to the configured remote.
- On a Windows machine or CI runner with .NET 10, run `dotnet run --project windows/TokenTracker.Windows.Tests/TokenTracker.Windows.Tests.csproj`.
- If CI catches C# compile issues that local macOS could not catch, fix them in a follow-up commit.
- Optionally trigger the release workflow manually to verify both `win-x64` and `win-arm64` artifacts plus macOS universal DMG.

## Risks & Blockers

- Local machine does not have `dotnet`, so Windows compile/tests are unverified locally.
- Windows C# changes were reviewed statically and covered by intended tests, but they need a real .NET 10 build.
- GitHub Actions matrix YAML was not executed locally.
- macOS status color selection is based on `.darkAqua`/`.aqua`; unusual high-contrast or wallpaper-driven menu appearances may need visual verification.
- Universal macOS build works locally after `swift package clean`, but SwiftPM product-limited arch builds should not be reintroduced without testing.

## Open Questions

- Does GitHub `windows-latest` with .NET 10 publish both `win-x64` and `win-arm64` self-contained single-file artifacts cleanly?
- Should Windows stale cache display text be localized as `Stale Cache` instead of enum `StaleCache`?
- Should macOS disabled providers also avoid stale cache, matching the Windows policy added here?
- Should Windows Credential Manager support be added later if Claude Code uses it on Windows?
- Should release workflow defaults be updated from older version examples such as `v1.0.3`?

## Quick Start for Next Session

```bash
# Branch and status
git branch --show-current
git status --short

# Related prior context
sed -n '1,360p' plans/handoffs/HANDOFF_claude-usage-stability_429-cooldown-plan_2026-06-06.md
sed -n '1,340p' plans/handoffs/HANDOFF_claude-usage-stability_macos-auth-fallback_2026-06-05.md

# Current handoff
sed -n '1,360p' plans/handoffs/HANDOFF_platform-optimization_macos-windows-hardening_2026-06-09.md

# Key files to read first
sed -n '1,260p' windows/TokenTracker.Windows.Core/UsageClient.cs
sed -n '1,180p' windows/TokenTracker.Windows.Core/CacheStore.cs
sed -n '1,230p' windows/TokenTracker.Windows.Tests/Program.cs
sed -n '1,150p' Sources/TokenTrackerCore/UsageService.swift
sed -n '1,330p' Sources/TokenTrackerMenuBar/AppDelegate.swift

# Verify current state on macOS
git diff --check
swift run TokenTrackerSmokeTests
APP_ARCHS="arm64 x86_64" scripts/build_app.sh
lipo -info ".build/Token Tracker.app/Contents/MacOS/TokenTrackerMenuBar"

# Verify current state on Windows or CI
dotnet run --project windows/TokenTracker.Windows.Tests/TokenTracker.Windows.Tests.csproj
dotnet publish windows/TokenTracker.Windows/TokenTracker.Windows.csproj -c Release -r win-x64 --self-contained true /p:PublishSingleFile=true /p:PublishReadyToRun=false
dotnet publish windows/TokenTracker.Windows/TokenTracker.Windows.csproj -c Release -r win-arm64 --self-contained true /p:PublishSingleFile=true /p:PublishReadyToRun=false

# Next action
Review the pushed commit and run the Windows test suite on a machine with .NET 10 installed.
```
