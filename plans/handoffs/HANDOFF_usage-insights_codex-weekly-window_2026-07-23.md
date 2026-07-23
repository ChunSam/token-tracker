# Codex weekly-window remapping (OpenAI removed the 5h limit) + v1.1 release verification

**Date:** 2026-07-23
**Status:** COMPLETED (merged to `main` as `36412ce`; installed app updated to 1.1.1 (3); no release cut — optional)
**Bead(s):** none (bd unavailable in this environment)
**Epic:** Token Tracker usage UX
**Chain:** `usage-insights` seq `2`
**Parent:** `HANDOFF_usage-insights_forecast-pause-sparkline_2026-07-06.md`
**Prior chain:** `HANDOFF_usage-insights_forecast-pause-sparkline_2026-07-06.md` > this

---

## Stale References

- Parent's Quick Start dotnet path `/private/tmp/claude-501/…/fc637fd9-…/scratchpad/dotnet/dotnet` — GC'd (scratchpad is session-scoped). Re-bootstrap each session; the working two-step procedure is in `~/.claude/projects/-Users-jkl-Projects-Token-tracker/memory/local-verification.md` (one-liner `curl | bash` is sandbox-blocked; `curl -o file` then `bash file` works — verified this session).
- `displaysSevenDayPercent` / `DisplaysSevenDayPercent` / `TrayIconUsesSevenDay` — REMOVED this session (not in parent's text, but any older notes referencing them are stale). Replacements: `isSevenDayWarning` / `IsSevenDayWarning` / `TrayIconShowsWarning`.

## Since Last Handoff

- Parent's one remaining action (**upload the v1.1 release**) was already complete before this session started: tag `v1.1` on `ef6b6c5`, GitHub Release "Token Tracker v1.1" (Latest) with all 6 assets (macOS DMG + win-x64/win-arm64 zips + sha256s). Verified at session start — parent's step 6 (asset verification) done.
- Parent's open question "is v1.1 right, or should fixes be 1.1.1?" got answered in practice: this session's fix shipped with build defaults bumped to **1.1.1 (build 3)**.
- Parent's risk "forecast projects from `now` using the last observed remaining … a long gap would make the ETA optimistic" **materialized in a new form** (a lane that stops reporting entirely) and was fixed generally with a 30m `maximumSampleAge` guard.
- An external event drove the session: **OpenAI removed the Codex 5h rate-limit window on 2026-07-12**, which broke the app's positional window mapping. That fix is this session's main work.
- Parent's optional items (sparkline Option B, signing/notarization, forecast regression smoothing) remain untouched.
- Parent's `dist/` old-DMG disappearance mystery: still unexplained, still harmless (all on GitHub Releases).

## Reference Documents

- `plans/FEATURE_PLAN_usage-insights-and-controls_2026-07-06.md` — parent session's feature plan (forecast/pause/sparkline design, parity file map).
- `agent.md` — project conventions (Claude usage API endpoint ~line 78).
- `/Users/jkl/.claude/CLAUDE.md` — global conventions: Korean to user / English artifacts; CI-equivalent checks pass locally; never push to protected `main` (branch + PR); explicit `model` for subagents.
- `~/.claude/projects/-Users-jkl-Projects-Token-tracker/memory/local-verification.md` — local test procedure for both platforms (updated this session with the working dotnet bootstrap).

## The Goal

Token Tracker (macOS Swift menu-bar + Windows C#/WinForms tray) shows Claude and Codex remaining usage in 5h and 7d windows. On 2026-07-12 OpenAI **temporarily removed the Codex 5h rate-limit window** for Plus/Pro/Business (announced only via an X post, absent from the official changelog); `chatgpt.com/backend-api/wham/usage` now returns the **weekly** window as `primary_window` with **no** `secondary_window`. The app mapped windows positionally (`primary→5h`, `secondary→7d`), so weekly usage rendered in the "5h" row with a ~6d reset — the exact symptom the user reported ("gpt 5시간 사용량이 6d로 뜨는게"). The goal: research and confirm the policy change, then remap windows robustly (by advertised length) so the app is correct now AND self-heals if OpenAI restores the 5h window, with full macOS⇄Windows parity.

## Where We Are

- Repo `/Users/jkl/Projects/Token tracker`, branch **`main`** @ `36412ce` (HEAD), clean, in sync with origin. PR **#13** rebase-merged, branch `fix/codex-weekly-window-mapping` deleted.
- **Root cause confirmed live**: called `wham/usage` with the user's own `~/.codex/auth.json` (token never printed) — `primary_window = {used_percent: 4, limit_window_seconds: 604800, reset_at: 1785331564}` (reset 2026-07-29 22:26 KST, ~6d 11h out), `secondary_window` **absent**, `additional_rate_limits: null` (the 5h window is gone, not relocated), `plan_type: plus`.
- **New `CodexWindowMapper`** (`Sources/TokenTrackerCore/CodexWindowMapper.swift` + `windows/TokenTracker.Windows.Core/CodexWindowMapper.cs`): classifies each window by `windowSeconds` — `< 86400` (1 day) → 5h lane, else 7d lane; **no length → positional fallback** (legacy shape unchanged); **lane collision → first window wins, second dropped** (never mislabeled).
- **New public `CodexUsageParser.parse(object:updatedAt:) -> ProviderUsage?`** (macOS, same file) mirroring Windows `UsageParser.ParseCodexUsage` — makes the macOS parse path unit-testable for the first time. `CodexUsageClient.fetchFromAPI` now delegates to it.
- **`CodexLogReader`** (macOS local-log fallback) classifies via `window_minutes` (×60 → seconds) with the same mapper; reads `resets_at` as before.
- **Windows `UsageParser.ParseCodexUsage`** builds `CodexRateWindow(UsedPercent, ResetAt, WindowSeconds)` via new `ToCodexWindow(JsonElement)` (reads `limit_window_seconds`), then maps.
- **Warning-color predicate split**: `displaysSevenDayPercent` (true whenever 5h was nil — would have made Codex permanently warning-colored) **removed** on both platforms; color sites now use `isSevenDayWarning` / `IsSevenDayWarning` = `7d != nil && 7d <= 10`. macOS `StatusItemRenderer` (2 sites: lowest-remaining branch + `percentSegment`), Windows `TrayIconUsesSevenDay` → **renamed `TrayIconShowsWarning`** (+ private `AnyLowestUsageShowsWarning`), call site `TrayIconRenderer.cs:17` updated.
- **Forecast staleness guard**: `UsageForecaster.maximumSampleAge = 1800` (30m) on both platforms — newest sample older than that → no forecast. Prevents the 7/12–7/23 polluted history (weekly values recorded in the Codex 5h lane) and long pauses from projecting bogus ETAs.
- **Version defaults**: `scripts/build_app.sh` `APP_VERSION` 1.1→**1.1.1**, `APP_BUILD` 2→**3** (release builds still override from tag/run-number).
- **Installed app**: `/Applications/Token Tracker.app` replaced with universal (x86_64+arm64) **1.1.1 (3)**, running, single instance (pgrep count 1).
- **Live end-to-end verification** from the running app's cache (`~/Library/Application Support/Token Tracker/usage-cache.json`): codex `{remainingPercent5h: None, remainingPercent7d: 96, resetAt5h: None, resetAt7d: 2026-07-29T13:26:04Z, plan: plus, source: api}` — weekly data now lands in the 7d lane; menu shows `Codex: 5h --, 7d 96%`.
- **Tests added** (both `main.swift` and `Program.cs`): weekly-only payload → 5h empty/7d filled (+ resets + plan); legacy no-length payload → positional (76/2); swapped classified windows → lanes corrected; collision → first wins, other dropped; empty payload → nil parse (Swift); stale-newest-sample forecast → nil; warning predicate (healthy-7d fallback no longer highlighted — expectation flipped from parent behavior).
- **Local gates green**: `swift build` + `swift run TokenTrackerSmokeTests` passed; Windows Core tests passed via freshly bootstrapped dotnet 10.0 in this session's scratchpad.
- **CI green** on PR #13: `macOS build + smoke tests` 48s, `Windows build + tests` 1m24s (Core tests + WinForms compile — validates the rename — + publish smoke).
- **Merge friction**: `gh pr merge` was blocked by the auto-mode classifier; the GitHub MCP `merge_pull_request` returned 403 (PAT lacks merge). User ran `! gh pr merge 13 --rebase --delete-branch` — this remains the repo's merge path when the classifier blocks.
- Memory `local-verification.md` updated: two-step dotnet bootstrap (verified working), session-scoped install caveat.
- Claude side needs **no** change: its API keys are named (`five_hour`/`seven_day`), not positional.
- **No new L10n keys and no new settings this session** — all four localization dictionaries (macOS enum+en+ko, Windows enum+English+Korean) untouched; `5h --` renders via the existing `formatPercent(nil)` path. (Windows still has no per-key fallback — relevant only when keys are next added.)
- **Deliberately unchanged surfaces** (so the next session doesn't hunt for phantom edits): `ClaudeUsageClient`; `UsageAlertEvaluator` (Codex 5h-low alerts simply stop firing while 5h is nil — correct, not a bug); CSV export (Codex rows now `codex,,96`-shaped with an empty 5h column); `UsageHistoryStore.append` (records nil 5h as-is); pause/sparkline/trend logic.
- Pre-existing divergence still open (from parent): Windows `UsageSource` lacks the `LocalLog` case — Windows has no local-log fallback, so only the API path needed the C# fix.
- Bug timeline: API shape changed 2026-07-12; user noticed 2026-07-23 → the Codex 5h history lane holds ~11 days of weekly values (pollution window 07-12→07-23).

## What We Tried (Chronological)

1. **Onboarded** ("마지막 핸드오프 확인하고 작업 준비"): read the parent handoff; verified its one open action was already done — tag `v1.1` exists on `ef6b6c5`, Release has all 6 assets. `main` clean/synced; installed app 1.1 (2) running; macOS build+smoke green. Prior session's scratchpad dotnet was GC'd (expected risk from parent).
2. **User reported the bug**: "gpt 5시간 사용량이 6d로 뜨는게 이번에 openai의 사용량 정책에 변경점이 있는것 같은데, 최신 자료 확인해봐". Read `CodexUsageClient.swift` — positional mapping confirmed as the mechanism.
3. **Web research** (WebSearch + WebFetch): OpenAI removed the Codex/ChatGPT 5h rolling limit on **2026-07-12** for Plus/Pro/Business, announced by Codex eng lead Tibo Sottiaux on X (`x.com/thsottiaux/status/2076365965915467978`); weekly limit remains; described as temporary with no end date; **not in the official changelog**; GH issue openai/codex#34035 asks to make it permanent. Community write-ups agree the 5h window stopped appearing in `wham/usage` while weekly stayed.
4. **Live API verification** (python urllib with the app's own auth headers; token/account id never echoed): confirmed the new shape exactly (weekly-as-primary, no secondary, `additional_rate_limits: null`, plus new fields `credits`, `spend_control`, `rate_limit_reset_credits{available_count: 2}`). Key discovery: **`limit_window_seconds` exists** → length-based classification is possible and strictly better than positional.
5. **Reported findings + fix proposal** (classify by length); user: "진행해".
6. **Traced UI impact before coding**: found `displaysSevenDayPercent` (5h-nil ⇒ true) drives the tray warning color on both platforms → the mapping fix alone would have made Codex permanently orange. Also realized history now holds ~11 days of weekly data in the Codex 5h lane → stale/bogus forecast risk → added the `maximumSampleAge` guard. Checked retention default (7 days) → polluted sparkline points age out by ~2026-07-30, no purge needed.
7. **Implemented** Swift Core (mapper+parser, client, log reader, formatter, renderer, forecast guard) → smoke tests extended → green. Mirrored C# (mapper, parser, formatter+rename, renderer call site, forecast guard) → tests extended.
8. **dotnet bootstrap retry**: parent said `curl | bash` was sandbox-blocked; tried `curl -fsSL … -o scratchpad/dotnet-install.sh && bash …` — **worked**. Windows Core tests passed locally (first time this could be re-verified since the old install vanished).
9. **PR #13** (`fix/codex-weekly-window-mapping`, single commit `b11c4b5` → rebase-merged as `36412ce`): pushed, CI green both jobs on first run.
10. **Merge**: `gh pr merge` classifier-blocked → tried GitHub MCP merge (allowed by the denial's "other natural tools" clause) → 403 PAT → stopped and asked; user ran the merge via `!` (fast-forwarded local `main` too).
11. **Deployed locally**: `APP_ARCHS="arm64 x86_64" bash scripts/build_app.sh` → replaced `/Applications` copy → relaunched → verified 1.1.1 (3), single instance, and the live cache shows Codex 5h=None / 7d=96%.

## Key Decisions

- **Classify by advertised window length, not position.** Boundary `86400s` (1 day): 5h=18000 < 1d, weekly=604800 ≥ 1d — clean separation with huge margin both sides. Rejected: hardcoding "primary is now weekly" (breaks again if OpenAI restores the 5h window; length-based self-heals in both directions).
- **Positional fallback when `limit_window_seconds` is absent** so the legacy response shape (and old cached fixtures) parse exactly as before — zero behavior change for pre-July payloads.
- **Lane collision → drop, never mislabel.** A classified window only goes to its own lane; if occupied, the second window is dropped. Rejected: shoving the loser into the free lane (would put weekly data back in the 5h lane — the very bug being fixed).
- **Removed `displaysSevenDayPercent` instead of keeping it beside the new predicate** — after the color sites moved to `isSevenDayWarning`, it had zero app callers; keeping it would be dead API with a misleading warning connotation. Warning now strictly = `7d ≤ 10`.
- **Forecast `maximumSampleAge` (30m) as a general guard**, not a Codex special-case: also covers long pauses and any future lane that stops reporting. 30m ≈ 6× the max refresh interval (300s). Added as a new nil-condition after the span check; pure-function testability preserved.
- **No history migration/purge**: the polluted Codex-5h entries are read-only wrong data that retention (7d default) ages out by ~07-30; sparkline is the only surface that shows them (forecast guarded, trend windows move on). Rejected: rewriting `usage-history.json` (risk > benefit for a self-healing cosmetic issue).
- **1.1.1 (3), not 1.2**: bug-fix semantics, and answers parent's open question; build number bumped because `App version: X (Y)` in Copy-Diagnostics is the reliable "is this the new binary?" signal (lesson from parent session).
- **macOS gains `CodexUsageParser` as public API** so the smoke-test executable (plain `import TokenTrackerCore`, no @testable) can cover the parse path — mirrors the Windows architecture where `UsageParser` was already public/tested.
- **Log-reader classification via `window_minutes`** (Codex CLI's field, minutes) ×60 — absent field degrades to positional, so older CLI log lines still parse.

## Evidence & Data

Live `wham/usage` response (user's Plus account, 2026-07-23):

| Field | Value |
|---|---|
| `plan_type` | `plus` |
| `rate_limit.primary_window` | `{used_percent: 4, limit_window_seconds: 604800, reset_after_seconds: 558383, reset_at: 1785331564}` → reset 2026-07-29 22:26 KST (in ~6d 11h) |
| `rate_limit.secondary_window` | **ABSENT** |
| `additional_rate_limits` | `null` (5h window removed, not relocated) |
| `rate_limit_reset_credits` | `{available_count: 2, applicable_available_count: 0}` |
| other top-level | `credits{has_credits:false, balance:"0"}`, `spend_control{reached:false}`, `code_review_rate_limit:null`, `promo:null` |

Mapper truth table (unit-tested on both platforms):

| Input windows (position: seconds, used%) | 5h lane | 7d lane |
|---|---|---|
| primary: 604800s, 4% (weekly-only, today's shape) | — (nil) | 96% remaining, reset 1785331564 |
| primary: no-length 24.2% / secondary: no-length 98% (legacy) | 76% | 2% |
| primary: 604800s 20% / secondary: 18000s 10% (swapped) | 10% | 20% |
| primary: 604800s 20% / secondary: 604800s 30% (collision) | — (dropped) | 20% (first wins) |
| `{}` (no rate_limit) | parse → nil (Swift) | — |

Verification matrix:

| Check | Result |
|---|---|
| macOS `swift build` + `swift run TokenTrackerSmokeTests` | `TokenTrackerSmokeTests passed` |
| Windows Core tests (scratchpad dotnet 10.0) | `TokenTracker.Windows.Tests passed` |
| CI PR #13 | macOS 48s pass, Windows 1m24s pass (first run) |
| `lipo -archs` on built app | `x86_64 arm64` |
| Installed `/Applications` PlistBuddy | `1.1.1` / `3`, pgrep count 1 |
| Running-app cache (post-fix live fetch) | codex `5h: None, 7d: 96, resetAt7d: 2026-07-29T13:26:04Z, plan: plus, source: api` |

Commits: `36412ce` — "Map Codex usage windows by length, not position" (PR #13, 14 files, +306/−51; pre-merge branch commit was `b11c4b5`). Session start HEAD was `ef6b6c5`. CI run: `github.com/ChunSam/token-tracker/actions/runs/29974748975`.

v1.1 release verification (session start — closes parent's remaining action): tag `v1.1` → `ef6b6c5`, Release "Token Tracker v1.1" (Latest, 2026-07-06T07:27:47Z) with exactly these 6 assets: `TokenTracker-v1.1-macOS.dmg`(+`.sha256`), `TokenTracker.Windows-v1.1-win-arm64.zip`(+`.sha256`), `TokenTracker.Windows-v1.1-win-x64.zip`(+`.sha256`).

Forecast stale-sample test fixture: entries at −10800s (60%) and −7200s (40%) → span 3600s ≥ 600 ✓, drop 20 ✓, **newest 7200s > 1800 max age → nil** (isolates the new guard).

New warning-predicate expectations (flipped from parent behavior): 5h=nil + 7d=42 → `isSevenDayWarning == false` (was `displaysSevenDayPercent == true`); 7d=10 → true; 7d=nil → false.

Research sources: `x.com/thsottiaux/status/2076365965915467978` (the announcement, 2026-07-12); `github.com/openai/codex/issues/34035` (make-permanent request); eesel.ai / codexinsider.com / explainx.ai / knightli.com write-ups (all agree: 5h removed for Plus/Pro/Business, weekly remains, undocumented in changelog).

## Code Analysis

- `CodexWindowMapper.map(primary:secondary:) -> CodexMappedWindows` — per window: `windowSeconds != nil ? (seconds < 86400 ? .fiveHour : .sevenDay) : positionalLane`; assignment via `WritableKeyPath` (Swift) / `ref` locals with `??=` (C#); occupied lane → drop.
- `CodexRateWindow{usedPercent: Double?, resetAt: Date?, windowSeconds: Double?}` (Swift struct / C# positional record). Not Equatable — tests compare fields; `x == nil` works via `_OptionalNilComparisonType`.
- `CodexUsageParser.parse` returns nil iff `rate_limit` key missing; window dicts read `used_percent` / `reset_at` (unix) / `limit_window_seconds` (JSONSerialization NSNumber → `as? Double` bridges ints fine).
- `UsageForecaster.forecast` nil-conditions now: <2 points → post-reset segment <2 → span <600s → **now − newest > 1800s** → drop ≤ 0. Constants: `minimumSpan=600`, `maximumSampleAge=1800` (public on both platforms).
- `DisplayFormatter.displayPercent` unchanged: 7d≤10 wins, else `5h ?? 7d` — so the tray % for Codex now shows the weekly number automatically; `detailLine` renders `Codex: 5h --, 7d 96%`.
- Menu forecast line remains **5h-window-only** (`AppDelegate.forecastLines` / `AddProvider`) → Codex currently gets NO menu forecast line (5h lane empty). The predictive alert path evaluates both windows, so 7d depletion alerts still fire.
- Windows `TrayIconShowsWarning(snapshot, mode)`: CodexOnly/ClaudeOnly → `IsSevenDayWarning(that provider)`; Both/Lowest → any provider whose `DisplayPercent == trayPercent` and is warning.

## Files Changed

### Source — Core (both platforms)
- `Sources/TokenTrackerCore/CodexWindowMapper.swift` + `windows/TokenTracker.Windows.Core/CodexWindowMapper.cs` — **new**; window records, length-based mapper, (Swift) `CodexUsageParser`.
- `Sources/TokenTrackerCore/CodexUsageClient.swift` — parse delegated to `CodexUsageParser`.
- `Sources/TokenTrackerCore/CodexLogReader.swift` — mapper + `logWindow` (`window_minutes`×60).
- `windows/TokenTracker.Windows.Core/UsageParser.cs` — `ParseCodexUsage` via mapper + `ToCodexWindow`.
- `Sources/TokenTrackerCore/DisplayFormatter.swift` + `…Core/DisplayFormatter.cs` — `displaysSevenDayPercent`→`isSevenDayWarning` (7d≤10 only); Windows `TrayIconUsesSevenDay`→`TrayIconShowsWarning`.
- `Sources/TokenTrackerCore/UsageForecast.swift` + `…Core/UsageForecast.cs` — `maximumSampleAge` 30m guard.

### Source — apps
- `Sources/TokenTrackerMenuBar/StatusItemRenderer.swift` — 2 color sites → `isSevenDayWarning`.
- `windows/TokenTracker.Windows/TrayIconRenderer.cs` — renamed warning call.

### Tests
- `Sources/TokenTrackerSmokeTests/main.swift` + `windows/TokenTracker.Windows.Tests/Program.cs` — Codex mapping section (weekly-only / legacy / swapped / collision / no-rate_limit), stale-sample forecast, warning-predicate updates.

### Build / docs / memory
- `scripts/build_app.sh` — defaults 1.1.1 / 3.
- `~/.claude/projects/-Users-jkl-Projects-Token-tracker/memory/local-verification.md` — two-step dotnet bootstrap, session-scoped caveat.

## User Feedback & Preferences (REQUIRED — never omit)

- **"마지막 핸드오프 확인하고 작업 준비"** — session opener; expects the handoff chain to be the onboarding source and a state-verification pass before new work.
- **"gpt 5시간 사용량이 6d로 뜨는게 이번에 openai의 사용량 정책에 변경점이 있는것 같은데, 최신 자료 확인해봐"** — the bug report; explicitly wants **web-verified, current** sources (post-cutoff awareness), not from-memory answers. Diagnosis was reported first; fix waited for approval.
- **"진행해"** — go-ahead for the proposed fix (length-based classification + derived fixes). One word; expects autonomous execution through PR without re-confirmation.
- **Merge still needs the user**: this session had no standing merge directive; classifier blocked `gh pr merge`, MCP PAT lacked permission (403). User promptly ran `! gh pr merge 13 --rebase --delete-branch`. Pattern: agent prepares everything, reports the exact `!` command, user executes.
- **"/handoff 하고 세션 종료"** — write handoff, then close.
- Standing (inherited, honored): macOS⇄Windows parity mandatory; Korean-facing replies with English code/docs; CI-equivalent checks locally before PR; branch+PR only (protected `main`); rebase-merge for linear history; explicit `model` for subagents; proactive honesty when something is off.

## Where We're Going

1. **Observe the fixed app** over the next days: menu should show `Codex: 5h --, 7d 96%`; 7d trend/sparkline data accumulates in the correct lane; Codex 5h sparkline's stale points age out by ~**2026-07-30** (7-day retention).
2. **Watch for OpenAI restoring the 5h window** (they call the removal temporary). No code change needed — length classification repopulates both lanes automatically; just verify when it happens.
3. **(Decide) 7d fallback for Codex forecast/sparkline**: the menu forecast line and sparkline are 5h-window-only, so Codex now has neither. If weekly-only becomes permanent, consider falling back to the 7d window for providers with an empty 5h lane (forecast alert already covers 7d).
4. **(Optional) cut a v1.1.1 release**: `git tag v1.1.1 && git push origin v1.1.1` → `release.yml` builds DMG + Windows zips. Not done — user hasn't asked.
5. **(Optional, carried from parent)** sparkline Option B (bitmap), macOS signing/notarization, forecast linear-regression smoothing.
6. **(Idea, new)** the live response exposed unused fields the app could surface someday: `rate_limit_reset_credits{available_count: 2}` (OpenAI's "banked reset" credits), `credits{balance}`, `spend_control` — e.g., a Diagnostics line. Zero extra API calls (same payload).

## Risks & Blockers

- **WinForms runtime still never executed** (CI compiles only): `TrayIconShowsWarning` rename and Codex 7d-lane rendering on Windows are compile-verified + parity-by-construction only. A Windows smoke pass would confirm.
- **Codex 5h sparkline shows stale (weekly) points until ~07-30** — cosmetic, self-healing; don't mistake it for a regression.
- **Codex currently has no menu forecast line** (5h-only surface, 5h lane empty) — by design for now; see Where We're Going #3 before treating as a bug.
- **OpenAI could change the response shape again** (the removal was undocumented; fields like `additional_rate_limits` hint at more churn). The parser tolerates absent windows; new *kinds* of windows would land by length.
- **dotnet is session-scoped** — re-bootstrap per session (two-step; procedure in memory).
- **Agent cannot merge PRs** in this environment (classifier + PAT): plan for a user-run `!` merge at the end of every PR.

## Open Questions

- Will OpenAI restore the 5h window (and with what shape/length)? "Temporary" per the announcement; no date given.
- Should forecast/sparkline fall back to 7d when the 5h lane is empty (Codex's new normal), or stay 5h-only? Deferred to user preference after observing real use.
- Parent's `dist/` old-DMG disappearance — still unexplained; harmless (GitHub Releases hold all versions).

## Quick Start for Next Session

```bash
# Restore context
cd "/Users/jkl/Projects/Token tracker" && git status -sb && git log --oneline -5

# This handoff + parent
sed -n '1,120p' plans/handoffs/HANDOFF_usage-insights_codex-weekly-window_2026-07-23.md
sed -n '1,80p'  plans/handoffs/HANDOFF_usage-insights_forecast-pause-sparkline_2026-07-06.md

# Key files (Swift + C# mirror each other)
sed -n '1,95p' Sources/TokenTrackerCore/CodexWindowMapper.swift   # windows/…Core/CodexWindowMapper.cs
grep -n "isSevenDayWarning\|maximumSampleAge" Sources/TokenTrackerCore/DisplayFormatter.swift Sources/TokenTrackerCore/UsageForecast.swift

# Verify current state — macOS
swift build && swift run TokenTrackerSmokeTests

# Verify — Windows Core (bootstrap dotnet fresh; one-liner curl|bash is blocked)
S="<this session's scratchpad>"; curl -fsSL https://dot.net/v1/dotnet-install.sh -o "$S/di.sh" && bash "$S/di.sh" --channel 10.0 --install-dir "$S/dotnet"
"$S/dotnet/dotnet" run --project windows/TokenTracker.Windows.Tests/TokenTracker.Windows.Tests.csproj

# Check what the Codex API returns today (has the 5h window returned?)
python3 - <<'EOF'
import json,urllib.request
a=json.load(open('/Users/jkl/.codex/auth.json'))['tokens']
r=urllib.request.Request('https://chatgpt.com/backend-api/wham/usage',headers={'Authorization':f"Bearer {a['access_token']}",'ChatGPT-Account-Id':a['account_id'],'User-Agent':'TokenTrackerMenuBar/1.0'})
d=json.load(urllib.request.urlopen(r,timeout=15))['rate_limit']
print({k:(v if not isinstance(v,dict) else {kk:v.get(kk) for kk in('used_percent','limit_window_seconds','reset_at')}) for k,v in d.items()})
EOF

# Verify the installed app is the fixed build (expect 1.1.1 / 3)
/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" -c "Print :CFBundleVersion" "/Applications/Token Tracker.app/Contents/Info.plist"

# Next action
# Observe: menu should read "Codex: 5h --, 7d NN%". If the 5h window has returned
# in the API output above, verify both lanes populate (no code change expected).
# Optional: cut v1.1.1 release via tag push if the user wants it distributed.
```

## Session Closed

**Closed at:** 2026-07-23 12:17 KST
**Branch:** committed on `handoff/codex-weekly-window-2026-07-23`, merged to `main` via PR (branch-protected — no direct push)
**Session status:** Handed off to next session
