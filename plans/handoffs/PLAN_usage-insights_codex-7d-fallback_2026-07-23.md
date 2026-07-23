# Plan: Codex account signals in Diagnostics, forecast regression smoothing, sparkline Option B

**Date:** 2026-07-23
**Status:** PLANNED
**Bead(s):** none (bd unavailable in this environment)
**Epic:** Token Tracker usage UX
**Chain:** `usage-insights` seq `3` (copied from paired handoff)
**Context:** See `HANDOFF_usage-insights_codex-7d-fallback_2026-07-23.md` for session data, live API captures, test fixtures, and prior approaches.

---

## Problem Statement

The Codex weekly-window emergency work is fully shipped (window mapping fixed in seq 2, 7d forecast/sparkline fallback shipped in seq 3 as v1.1.2). What remains is the quality backlog that has been carried across two handoffs: (a) the live Codex API exposes account signals the app already downloads but throws away — `rate_limit_reset_credits.available_count: 2`, `credits.balance`, `spend_control.reached` — which would explain "why did my limit reset early?" moments for free; (b) the depletion forecast still uses an endpoint slope over the post-reset segment, so a single noisy first/last sample swings the ETA — visible right now on Codex, whose 7d ETA (~5d 4h from only 11h of data) will jitter until smoothed; (c) the Unicode sparkline (`▁▂▃▄▅▆▇█`) was always "Option A" — the grandparent's feature plan defines a bitmap "Option B" that was deferred twice. See Evidence & Data in the handoff for the exact field shapes and forecast numbers.

## Key Findings

- Live `wham/usage` returns `rate_limit_reset_credits {available_count: 2, applicable_available_count: 0}`, `credits {has_credits, balance}`, `spend_control {reached}` on every poll — zero extra API calls needed to surface them. → drives Phase 1
- Diagnostics surfaces already exist on both platforms (macOS `DiagnosticsReporter` + Copy Diagnostics; Windows `DiagnosticsMenu`/`DiagnosticsReporter.cs`) — Phase 1 is additive lines, not new UI. → drives Phase 1
- `UsageForecaster.forecast` slope = `(first.r − last.r) / elapsed` over the post-reset segment (`UsageForecast.swift` ~line 73, `UsageForecast.cs` mirror); all other guards (span ≥600s, age ≤1800s) are sound and stay. → drives Phase 2
- The existing pinned forecast tests use **perfectly linear, evenly spaced** fixtures (`steadyEntries` 60/50/40 → 7200s; `resetEntries` post-reset 80/70/60 → 5400s) — a least-squares slope produces IDENTICAL results for them, so the pins survive Phase 2 unchanged. Only new uneven fixtures show a difference. → drives Phase 2 test strategy
- Codex 7d lane now has real declining data (137 pts, 96→88% over 11.3h, burn 0.71%/h) — a live case to sanity-check Phase 2 against. → validates Phase 2
- Sparkline internals are fully mapped (handoff Code Analysis): `SparklineSeries.build` (bucket-averaged, maxPoints 20) is rendering-agnostic; only `SparklineText.render` and the menu attachment are Option-A-specific. → drives Phase 3 scoping
- WinForms compile-checks locally now (`dotnet build …TokenTracker.Windows.csproj -p:EnableWindowsTargeting=true`) — app-layer C# changes in every phase get validated before CI. → all phases
- Merge playbook updated: prepare PR → report → on the user's explicit merge request run `gh pr merge {n} --rebase --delete-branch` directly (worked this session; `!` escape only as fallback). → all phases

## Anti-Goals (What NOT To Do)

- **Do NOT touch `CodexWindowMapper` or `preferredForecastWindow`** — both shipped, tested, and self-healing in both directions. There is no code to write for "OpenAI restores the 5h window"; only verify lanes repopulate if it happens.
- **Do NOT purge or migrate `usage-history.json`** — the polluted Codex 5h entries are invisible since the fallback and age out by ~07-30 (decision re-affirmed twice; risk > benefit).
- **Do NOT localize the `5h`/`7d`/window-marker literals** — established language-neutral convention; adding L10n keys triggers the Windows no-per-key-fallback gap for zero user value.
- **Do NOT hardcode "primary window is weekly"-style positional assumptions anywhere new** — that's the exact class of bug seq 2 removed.
- **Do NOT change the forecast guards** (`minimumSpan` 600s, `maximumSampleAge` 1800s) while smoothing the slope — they solve different failure modes (sparse data / stale lanes) and are pinned by tests.

## Plan

### Phase 1: Surface Codex account signals in Diagnostics

**Goal:** Show `reset credits`, `credit balance`, and `spend-limit reached` for Codex in both platforms' Diagnostics so the user can explain quota anomalies without opening chatgpt.com.

**Why this approach:** The data is already in every poll response (handoff Evidence has exact shapes); Diagnostics is the agreed low-risk surface (user deferred it from the option menu, i.e. wanted but not urgent). Extending the parsed model mirrors how `plan` already flows through.

- Read `Sources/TokenTrackerMenuBar/DiagnosticsReporter.swift` and `windows/TokenTracker.Windows/DiagnosticsReporter.cs` first (NOT yet read by any session — the handoff maps the menu around them, not their internals).
- Extend the Codex parse path: `CodexUsageParser.parse` (Swift, `CodexWindowMapper.swift`) and `UsageParser.ParseCodexUsage` (C#) to read top-level `rate_limit_reset_credits.available_count` (Int), `credits.balance` (String), `spend_control.reached` (Bool) from the same `object`/JsonElement they already receive.
- Carry the values on `ProviderUsage` as three new optionals (default nil) — same pattern as the existing `plan`/`model` optionals; nil for Claude and for legacy payloads. Verify cache round-trip: old `usage-cache.json` without the fields must still decode (Swift optional Codable + System.Text.Json tolerate absent keys — add a test proving it).
- Render in Diagnostics only when non-nil, as language-neutral lines (e.g. `Codex reset credits: 2`, `Codex credit balance: 0`, `Spend limit reached: yes`) — decide L10n per existing Diagnostics conventions AFTER reading the reporters (if every existing line is localized, add the 3 keys to ALL FOUR dictionaries — macOS enum+en+ko, Windows enum+English+Korean; Windows has no per-key fallback, so partial addition breaks).
- `CodexLogReader` (local-log fallback): leave untouched — log lines don't carry these fields; nil is correct.
- Tests both platforms: parser extracts the three fields from the live-shape fixture (copy from handoff Evidence); absent fields → nil; old-cache decode; diagnostics text includes/omits lines correctly.

**Files:** `Sources/TokenTrackerCore/CodexWindowMapper.swift`, `Models.swift` (ProviderUsage), `Sources/TokenTrackerMenuBar/DiagnosticsReporter.swift`; `windows/…Core/UsageParser.cs`, `Models.cs`, `windows/TokenTracker.Windows/DiagnosticsReporter.cs`; both test files; possibly `Localization.swift`/`Localizer.cs` (all four dictionaries or none).
**Validates with:** `swift build && swift run TokenTrackerSmokeTests`; scratchpad dotnet: Core tests + WinForms compile check; live check — Copy Diagnostics from the running app shows `reset credits: 2` (current live value).
**Rollback:** revert the commit; the fields are additive optionals, so no data migration either way.

### Phase 2: Forecast regression smoothing (least-squares slope)

**Goal:** Replace the endpoint slope in `UsageForecaster.forecast` with an ordinary least-squares slope over the post-reset segment, damping single-sample noise in ETAs on both platforms.

**Why this approach:** Carried from the grandparent's feature plan; the endpoint method's weakness is now user-visible on the young Codex 7d lane (handoff: 0.71%/h from 11h of data). OLS over the already-trimmed segment is the minimal change that uses every sample; the segment-trim + guards already handle resets/staleness.

- In `forecast` (Swift `UsageForecast.swift` ~lines 60-89; C# mirror): after the existing segment trim and span/age guards, compute OLS slope of remaining% vs time-in-seconds over `segment` (x = t − first.t to keep numbers small; slope in %/sec).
- Declining check becomes `slope < 0` (replaces `drop > 0` as the no-forecast condition — keep returning nil for flat/rising). `burnPerHour = -slope * 3600`.
- `secondsToEmpty = Double(last.r) / burnPerHour * 3600` — anchor on the LAST OBSERVED remaining (not the fitted intercept) so the ETA never contradicts the newest sample.
- Keep `minimumSpan`/`maximumSampleAge`/2-point minimums untouched (Anti-Goals). With exactly 2 points OLS ≡ endpoint slope — no behavior cliff.
- Existing pinned tests survive unchanged (linear evenly spaced fixtures — see Key Findings). Add: an uneven fixture where endpoint and OLS differ (e.g. points at −3600s:60, −3000s:58, 0s:40 — endpoint burn 20%/h vs OLS ≈ 19.3%/h; pin the OLS-derived secondsToEmpty on both platforms with the same integers) and a flat-then-drop fixture proving noise damping.
- Mirror exactly in C# (`double` math, same variable names where idiomatic); run both suites; watch for Int truncation differences at the `(int)` conversions in test pins — pick fixture numbers that land away from .5 boundaries.

**Files:** `Sources/TokenTrackerCore/UsageForecast.swift`, `windows/TokenTracker.Windows.Core/UsageForecast.cs`, both test files.
**Validates with:** both test suites green with existing pins UNCHANGED (this is the proof of backward compatibility) + new uneven-fixture pins; sanity: rerun the handoff's python replication against live history and compare OLS vs endpoint burn for Codex 7d (expect same order of magnitude, smoother).
**Rollback:** revert the commit — pure-function change, no persisted format touched.

### Phase 3: Sparkline Option B (bitmap) — decide, then implement

**Goal:** Decide whether to replace the Unicode sparkline with the bitmap rendering ("Option B") from the grandparent's feature plan, and implement it if the user confirms.

**Why this approach:** Deferred twice; the design lives in `plans/FEATURE_PLAN_usage-insights-and-controls_2026-07-06.md` (NOT in this chain's handoffs — read it first). It is user-visible polish with real platform-specific rendering work, so it is decision-gated: present cost/benefit before coding.

- Read the FEATURE_PLAN's Option B section; extract its concrete design (dimensions, drawing approach) — do not re-design from scratch.
- Summarize to the user (Korean): what Option B adds over Unicode (smooth resolution vs 8 block levels, color, consistent width), the estimated size of the change (macOS NSImage on the menu item + Windows owner-draw/Image on ToolStripMenuItem — two new renderers), and a recommendation.
- If approved: keep `SparklineSeries.build` as the shared data source (it is rendering-agnostic — handoff Code Analysis); add bitmap renderers per platform; keep `SparklineText` for any text-only surface (CSV/diagnostics) rather than deleting it.
- If declined: record the decision in the next handoff and drop the item from the backlog permanently (third deferral = not wanted).

**Files:** read-only until decided; then `Sources/TokenTrackerMenuBar/` (new renderer + StatusMenuBuilder attachment), `windows/TokenTracker.Windows/TrayAppContext.cs` (HistoryMenu), shared Core untouched except possibly a series-of-Int→image helper location.
**Validates with:** visual check in the running app (macOS), WinForms compile check (Windows rendering is runtime-unverifiable locally — flag in PR); existing sparkline series tests keep passing.
**Rollback:** revert; Unicode path remains intact by design.

## Dependencies & Order

- **Pre-flight (before any phase):** run the handoff Quick Start verification block — gates green, installed app 1.1.2 (4), AND the 5h-window probe. If the 5h window has returned, just verify both lanes populate (no code change) and note it in the next handoff.
- Phase 1 and Phase 2 are **independent** — parallelizable via worktree agents (they touch disjoint source files; both append to the two test files, so merge those serially or partition test sections).
- Phase 3 depends on nothing technically but is **user-gated** — do the read+summarize step anytime; implementation only after approval.
- Ship each phase as its own branch + PR (protected `main`); one combined PR only if the user asks.

## Risks & Mitigations

- **Phase 1 model change breaks cache decode** (likely LOW — optionals): prove with an old-shape decode test before touching the reporters; if either platform's serializer balks, fall back to carrying the signals on the snapshot/diagnostics side instead of `ProviderUsage`.
- **Phase 1 L10n trap** (MEDIUM if Diagnostics lines turn out localized): the four-dictionary rule is all-or-nothing on Windows (no per-key fallback — handoff/parent evidence). Budget for 3 keys × 4 dictionaries.
- **Phase 2 changes alert timing**: `willEmptyBeforeReset` may flip near boundaries with the smoother slope — the 7d Codex alert is live-armed right now (ETA < reset). Mention in the PR; not a bug.
- **Phase 2 cross-platform float divergence** (LOW): pick integer-friendly fixtures; pin the same expected ints on both platforms.
- **Phase 3 Windows rendering is locally unverifiable** (KNOWN, standing): compile check only; flag for the eventual Windows runtime smoke (still never done — carried risk).
- **OpenAI shape churn** (standing): parser tolerates absent fields everywhere; Phase 1 must keep that property (all three new reads are optional-safe).

## Success Criteria

- **Minimum viable:** Phase 1 shipped — Copy Diagnostics on macOS shows the three Codex signals (live: reset credits 2, balance "0", spend reached false), Windows compiles with mirrored lines, all tests green, old cache still decodes.
- **Full:** Phases 1+2 shipped as separate merged PRs with CI green first-run (the chain's streak: #13, #15 both did); existing forecast pins unchanged post-OLS; Phase 3 decision recorded (implemented, or dropped after third deferral).
- Forecast sanity: Codex 7d OLS burn within ±30% of the endpoint value on the same live history snapshot (both ~0.7%/h region), and stable across two consecutive menu opens.
- No regression: `Codex: 5h --, 7d NN%` menu line, `(7d)` forecast marker, and sparkline labels all still render as shipped in v1.1.2.

## Quick Start

```bash
# Restore full context
cat "plans/handoffs/HANDOFF_usage-insights_codex-7d-fallback_2026-07-23.md"

# Key source files for Phase 1
sed -n '1,80p' Sources/TokenTrackerMenuBar/DiagnosticsReporter.swift
sed -n '1,80p' windows/TokenTracker.Windows/DiagnosticsReporter.cs
sed -n '59,95p' Sources/TokenTrackerCore/CodexWindowMapper.swift    # CodexUsageParser.parse
grep -n "ParseCodexUsage" -A 30 windows/TokenTracker.Windows.Core/UsageParser.cs
grep -n "struct ProviderUsage" -A 25 Sources/TokenTrackerCore/Models.swift

# Baseline data to reference
# Live API field shapes + forecast numbers: handoff "Evidence & Data" section
# App data: ~/Library/Application Support/Token Tracker/{usage-cache.json,usage-history.json}

# Verify starting state (expect green + 1.1.2/4; full block incl. 5h-window probe is in the handoff Quick Start)
swift build && swift run TokenTrackerSmokeTests
/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" -c "Print :CFBundleVersion" "/Applications/Token Tracker.app/Contents/Info.plist"

# First concrete action (Phase 1)
# Add the three optional fields to ProviderUsage (Models.swift + Models.cs), then read
# rate_limit_reset_credits.available_count / credits.balance / spend_control.reached in
# CodexUsageParser.parse + UsageParser.ParseCodexUsage, with a live-shape fixture test.
```
