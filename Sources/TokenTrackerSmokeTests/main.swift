import Foundation
import TokenTrackerCore

func expectEqual<T: Equatable>(_ actual: T, _ expected: T, _ message: String) {
    if actual != expected {
        fputs("FAIL: \(message). expected \(expected), got \(actual)\n", stderr)
        exit(1)
    }
}

func expect(_ condition: Bool, _ message: String) {
    if !condition {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

expectEqual(remainingPercent(fromUsed: 0), 100, "0 used leaves 100 remaining")
expectEqual(remainingPercent(fromUsed: 25.4), 75, "25.4 used rounds to 75 remaining")
expectEqual(remainingPercent(fromUsed: 100), 0, "100 used leaves 0 remaining")
expectEqual(remainingPercent(fromUsed: 120), 0, "remaining is clamped at 0")

let now = Date()
let snapshot = UsageSnapshot(
    claude: ProviderUsage(provider: .claude, remainingPercent5h: 63, remainingPercent7d: 80, resetAt5h: nil, resetAt7d: nil, source: .api, error: nil, plan: nil, model: nil, updatedAt: now),
    codex: ProviderUsage(provider: .codex, remainingPercent5h: 91, remainingPercent7d: 99, resetAt5h: nil, resetAt7d: nil, source: .api, error: nil, plan: "plus", model: nil, updatedAt: now),
    updatedAt: now
)

expectEqual(DisplayFormatter.statusTitle(snapshot: snapshot, mode: .both), "Cdx 91% · Cl 63%", "both display mode")
expectEqual(DisplayFormatter.statusTitle(snapshot: snapshot, mode: .codexOnly), "Cdx 91%", "codex display mode")
expectEqual(DisplayFormatter.statusTitle(snapshot: snapshot, mode: .claudeOnly), "Cl 63%", "claude display mode")
expectEqual(DisplayFormatter.statusTitle(snapshot: snapshot, mode: .lowestRemaining), "AI 63%", "lowest display mode")
expectEqual(DisplayFormatter.statusTitle(snapshot: snapshot, mode: .both, labelStyle: .icon), "Codex 91% · Claude 63%", "icon display fallback text")
expectEqual(DisplayFormatter.formatPercent(nil), "--", "missing percent")

// Menu bar reset countdown. The time shown has to belong to the same window the
// percentage came from, or the two read as unrelated numbers side by side.
let countdownNow = Date()
func countdownUsage(_ provider: Provider, five: Int?, seven: Int?, reset5h: TimeInterval?, reset7d: TimeInterval?) -> ProviderUsage {
    ProviderUsage(
        provider: provider,
        remainingPercent5h: five,
        remainingPercent7d: seven,
        resetAt5h: reset5h.map { countdownNow.addingTimeInterval($0) },
        resetAt7d: reset7d.map { countdownNow.addingTimeInterval($0) },
        source: .api,
        error: nil,
        plan: nil,
        model: nil,
        updatedAt: countdownNow
    )
}

expectEqual(DisplayFormatter.formatResetCompact(countdownNow.addingTimeInterval(2550)), "42m", "under an hour shows minutes only")
expectEqual(DisplayFormatter.formatResetCompact(countdownNow.addingTimeInterval(8010)), "2h13m", "hours and minutes drop the inner space")
expectEqual(DisplayFormatter.formatResetCompact(countdownNow.addingTimeInterval(273_900)), "3d4h", "over a day shows days and hours")
expectEqual(DisplayFormatter.formatResetCompact(countdownNow.addingTimeInterval(-60)), "now", "a passed reset reads as now")
expect(DisplayFormatter.formatResetCompact(nil) == nil, "no reset instant yields no countdown at all")

let fiveHourLead = countdownUsage(.claude, five: 63, seven: 80, reset5h: 8010, reset7d: 273_900)
expectEqual(DisplayFormatter.displayWindow(fiveHourLead), .fiveHour, "a healthy 7d leaves the 5h window on display")
expectEqual(DisplayFormatter.displayResetAt(fiveHourLead), fiveHourLead.resetAt5h, "the countdown follows the displayed window")

let sevenDayLead = countdownUsage(.claude, five: 100, seven: 8, reset5h: 8010, reset7d: 273_900)
expectEqual(DisplayFormatter.displayWindow(sevenDayLead), .sevenDay, "a low 7d takes over the display")
expectEqual(DisplayFormatter.displayResetAt(sevenDayLead), sevenDayLead.resetAt7d, "taking over the percent takes over the countdown too")

let sevenDayOnly = countdownUsage(.codex, five: nil, seven: 100, reset5h: nil, reset7d: 273_900)
expectEqual(DisplayFormatter.displayWindow(sevenDayOnly), .sevenDay, "an absent 5h lane falls back to 7d")
expectEqual(DisplayFormatter.displayResetAt(sevenDayOnly), sevenDayOnly.resetAt7d, "the fallback window supplies the countdown")

let noWindows = countdownUsage(.claude, five: nil, seven: nil, reset5h: 8010, reset7d: 273_900)
expect(DisplayFormatter.displayWindow(noWindows) == nil, "an unavailable provider displays no window")
expect(DisplayFormatter.displayResetAt(noWindows) == nil, "an unavailable provider shows no countdown despite having reset instants")

let countdownSnapshot = UsageSnapshot(claude: fiveHourLead, codex: sevenDayOnly, updatedAt: countdownNow)
expectEqual(
    DisplayFormatter.statusTitle(snapshot: countdownSnapshot, mode: .both, showResetCountdown: true),
    "Cdx 100% 3d4h · Cl 63% 2h13m",
    "both mode appends each provider's own countdown"
)
expectEqual(
    DisplayFormatter.statusTitle(snapshot: countdownSnapshot, mode: .both),
    "Cdx 100% · Cl 63%",
    "the countdown stays off unless asked for"
)
expectEqual(
    DisplayFormatter.statusTitle(snapshot: countdownSnapshot, mode: .claudeOnly, showResetCountdown: true),
    "Cl 63% 2h13m",
    "single provider mode appends its countdown"
)
expectEqual(
    DisplayFormatter.statusTitle(snapshot: countdownSnapshot, mode: .lowestRemaining, showResetCountdown: true),
    "AI 63% 2h13m",
    "lowest mode pairs the winning percent with that provider's reset"
)
expectEqual(DisplayFormatter.lowestUsage(countdownSnapshot)?.provider, .claude, "the lower percent owns the countdown")

// A provider with no reset instant contributes a percent but no time, rather than
// a dangling "--" in the menu bar.
let noResetSnapshot = UsageSnapshot(
    claude: countdownUsage(.claude, five: 63, seven: 80, reset5h: nil, reset7d: nil),
    codex: sevenDayOnly,
    updatedAt: countdownNow
)
expectEqual(
    DisplayFormatter.statusTitle(snapshot: noResetSnapshot, mode: .both, showResetCountdown: true),
    "Cdx 100% 3d4h · Cl 63%",
    "a provider without a reset instant simply omits its countdown"
)
expectEqual(
    DisplayFormatter.statusTitle(snapshot: nil, mode: .both, showResetCountdown: true),
    "AI --",
    "no snapshot still renders the placeholder"
)

let exhaustedSevenDaySnapshot = UsageSnapshot(
    claude: ProviderUsage(provider: .claude, remainingPercent5h: 100, remainingPercent7d: 0, resetAt5h: nil, resetAt7d: nil, source: .api, error: nil, plan: nil, model: nil, updatedAt: now),
    codex: ProviderUsage(provider: .codex, remainingPercent5h: 100, remainingPercent7d: 42, resetAt5h: nil, resetAt7d: nil, source: .api, error: nil, plan: "plus", model: nil, updatedAt: now),
    updatedAt: now
)

expectEqual(DisplayFormatter.statusTitle(snapshot: exhaustedSevenDaySnapshot, mode: .both), "Cdx 100% · Cl 0%", "display only switches to seven day inside warning threshold")
expectEqual(DisplayFormatter.statusTitle(snapshot: exhaustedSevenDaySnapshot, mode: .codexOnly), "Cdx 100%", "codex display uses five hour when seven day is above warning threshold")
expectEqual(DisplayFormatter.statusTitle(snapshot: exhaustedSevenDaySnapshot, mode: .lowestRemaining), "AI 0%", "lowest display includes exhausted seven day window")

let healthySevenDaySnapshot = UsageSnapshot(
    claude: ProviderUsage(provider: .claude, remainingPercent5h: 100, remainingPercent7d: 90, resetAt5h: nil, resetAt7d: nil, source: .api, error: nil, plan: nil, model: nil, updatedAt: now),
    codex: ProviderUsage(provider: .codex, remainingPercent5h: 98, remainingPercent7d: 100, resetAt5h: nil, resetAt7d: nil, source: .api, error: nil, plan: "plus", model: nil, updatedAt: now),
    updatedAt: now
)

expectEqual(DisplayFormatter.statusTitle(snapshot: healthySevenDaySnapshot, mode: .both), "Cdx 98% · Cl 100%", "healthy seven day value does not override five hour display")
expectEqual(DisplayFormatter.isSevenDayWarning(healthySevenDaySnapshot.claude), false, "healthy seven day value is not highlighted")
expectEqual(DisplayFormatter.isSevenDayWarning(exhaustedSevenDaySnapshot.claude), true, "exhausted seven day value is highlighted")

let sevenDayThresholdUsage = ProviderUsage(provider: .claude, remainingPercent5h: 100, remainingPercent7d: 10, resetAt5h: nil, resetAt7d: nil, source: .api, error: nil, plan: nil, model: nil, updatedAt: now)
let missingSevenDayUsage = ProviderUsage(provider: .claude, remainingPercent5h: 73, remainingPercent7d: nil, resetAt5h: nil, resetAt7d: nil, source: .api, error: nil, plan: nil, model: nil, updatedAt: now)
let missingFiveHourUsage = ProviderUsage(provider: .claude, remainingPercent5h: nil, remainingPercent7d: 42, resetAt5h: nil, resetAt7d: nil, source: .api, error: nil, plan: nil, model: nil, updatedAt: now)
let staleClaudeUsage = ProviderUsage(provider: .claude, remainingPercent5h: 64, remainingPercent7d: 82, resetAt5h: nil, resetAt7d: nil, source: .staleCache, error: "HTTP 429 from Claude API", plan: nil, model: nil, updatedAt: now)

expectEqual(DisplayFormatter.displayPercent(sevenDayThresholdUsage), 10, "7d value is shown at 10 percent threshold")
expectEqual(DisplayFormatter.isSevenDayWarning(sevenDayThresholdUsage), true, "7d threshold value is highlighted")
expectEqual(DisplayFormatter.displayPercent(missingSevenDayUsage), 73, "5h value is shown when 7d is missing")
expectEqual(DisplayFormatter.isSevenDayWarning(missingSevenDayUsage), false, "missing 7d is not highlighted")
expectEqual(DisplayFormatter.displayPercent(missingFiveHourUsage), 42, "7d value is shown when 5h is missing")
expectEqual(DisplayFormatter.isSevenDayWarning(missingFiveHourUsage), false, "healthy 7d fallback is not highlighted when 5h is missing")

let missingBothWindowsUsage = ProviderUsage(provider: .codex, remainingPercent5h: nil, remainingPercent7d: nil, resetAt5h: nil, resetAt7d: nil, source: .api, error: nil, plan: nil, model: nil, updatedAt: now)
expectEqual(DisplayFormatter.preferredForecastWindow(missingSevenDayUsage), .fiveHour, "5h window is preferred when it reports")
expectEqual(DisplayFormatter.preferredForecastWindow(missingFiveHourUsage), .sevenDay, "forecast surfaces fall back to 7d when 5h is missing")
expectEqual(DisplayFormatter.preferredForecastWindow(missingBothWindowsUsage), .fiveHour, "default window is 5h when neither reports")
expectEqual(DisplayFormatter.displayPercent(staleClaudeUsage), 64, "stale cache still displays cached percent")
expectEqual(staleClaudeUsage.source, .staleCache, "stale cache source is preserved")
expectEqual(staleClaudeUsage.error, "HTTP 429 from Claude API", "stale cache keeps the fetch failure reason")

let staleSnapshot = UsageSnapshot(
    claude: ProviderUsage(provider: .claude, remainingPercent5h: 63, remainingPercent7d: 80, resetAt5h: nil, resetAt7d: nil, source: .api, error: nil, plan: nil, model: nil, updatedAt: now),
    codex: ProviderUsage(provider: .codex, remainingPercent5h: 91, remainingPercent7d: 99, resetAt5h: nil, resetAt7d: nil, source: .api, error: nil, plan: nil, model: nil, updatedAt: now),
    updatedAt: now
)
let freshFailureSnapshot = UsageSnapshot(
    claude: ProviderUsage.unavailable(.claude, error: "HTTP 429 from Claude API"),
    codex: ProviderUsage.unavailable(.codex, error: "Disabled"),
    updatedAt: now
)
let enabledStaleSnapshot = UsageSnapshotCachePolicy.apply(
    current: freshFailureSnapshot,
    stale: staleSnapshot,
    claudeEnabled: true,
    codexEnabled: false,
    updatedAt: now
)
expectEqual(enabledStaleSnapshot.claude.source, .staleCache, "Enabled Claude can use stale cache")
expectEqual(enabledStaleSnapshot.codex.source, .unavailable, "Disabled Codex does not use stale cache")
expectEqual(enabledStaleSnapshot.codex.error, "Disabled", "Disabled Codex keeps disabled reason")

expectEqual(UsageError.httpStatus(code: 401, service: "Claude API", retryAfter: nil).localizedDescription, "HTTP 401 from Claude API", "HTTP status error names Claude API")
expectEqual(UsageError.httpStatus(code: 429, service: "Claude API", retryAfter: 300).localizedDescription, "HTTP 429 from Claude API; retrying after 5m", "HTTP 429 error includes retry delay")
expectEqual(UsageError.timedOut(service: "Claude API").localizedDescription, "Timed out contacting Claude API", "timeout error names Claude API")
expectEqual(UsageError.network(message: "offline", service: "Claude API").localizedDescription, "Network error from Claude API: offline", "network error names Claude API")

expectEqual(UsageIssueFormatter.kind(forError: "Disabled"), .disabled, "disabled error is classified")
expectEqual(UsageIssueFormatter.kind(forError: "HTTP 429 from Claude API; retrying after 5m"), .rateLimited, "429 error is classified as rate limited")
expectEqual(UsageIssueFormatter.kind(forError: "Missing credentials"), .missingCredentials, "missing credentials is classified")
expectEqual(UsageIssueFormatter.kind(forError: "Credentials expired for Codex API"), .expiredCredentials, "an expired token is classified")
expectEqual(UsageIssueFormatter.kind(forError: "HTTP 401 from Claude API"), .expiredCredentials, "401 is reported as an expired sign-in, not a bare HTTP error")
expectEqual(UsageIssueFormatter.kind(forError: "HTTP 403 from Codex API"), .expiredCredentials, "403 is reported as an expired sign-in")
expectEqual(UsageIssueFormatter.kind(forError: "HTTP 500 from Claude API"), .httpStatus, "other HTTP codes stay generic HTTP errors")
let expiredCodexIssue = UsageIssueFormatter.issue(for: .unavailable(.codex, error: "Credentials expired for Codex API"))
expect(expiredCodexIssue.recovery?.contains("codex login") == true, "Codex recovery names the Codex sign-in command")
expect(expiredCodexIssue.recovery?.contains("/login") == false, "Codex recovery does not make the user read past Claude's command")
let expiredClaudeIssue = UsageIssueFormatter.issue(for: .unavailable(.claude, error: "HTTP 401 from Claude API"))
expect(expiredClaudeIssue.recovery?.contains("/login") == true, "Claude recovery names the Claude sign-in command")
expect(expiredClaudeIssue.recovery?.contains("codex login") == false, "Claude recovery does not mention Codex")
expectEqual(UsageIssueFormatter.kind(forError: "Timed out contacting Claude API"), .timedOut, "timeout is classified")
expectEqual(UsageIssueFormatter.kind(forError: "Network error from Claude API: offline"), .network, "network error is classified")

let cachedIssue = UsageIssueFormatter.issue(for: staleClaudeUsage)
expectEqual(cachedIssue.kind, .usingCachedData, "stale cache issue is classified")
expectEqual(cachedIssue.technicalDetail, "HTTP 429 from Claude API", "stale cache keeps technical detail")

let alertSnapshot = UsageSnapshot(
    claude: ProviderUsage(provider: .claude, remainingPercent5h: 19, remainingPercent7d: 9, resetAt5h: now.addingTimeInterval(300), resetAt7d: now.addingTimeInterval(7200), source: .api, error: nil, plan: nil, model: nil, updatedAt: now),
    codex: ProviderUsage(provider: .codex, remainingPercent5h: 80, remainingPercent7d: 90, resetAt5h: nil, resetAt7d: nil, source: .api, error: nil, plan: nil, model: nil, updatedAt: now),
    updatedAt: now
)
let alertCandidates = UsageAlertEvaluator.candidates(
    snapshot: alertSnapshot,
    settings: UsageAlertSettings(notificationsEnabled: true, fiveHourThreshold: 20, sevenDayThreshold: 10, resetWarningMinutes: 10),
    now: now
)
expectEqual(alertCandidates.map(\.id), ["claude-5h-low", "claude-7d-low", "claude-5h-reset-\(Int(now.addingTimeInterval(300).timeIntervalSince1970))"], "alert evaluator emits low usage and reset alerts")
let disabledAlertCandidates = UsageAlertEvaluator.candidates(
    snapshot: alertSnapshot,
    settings: UsageAlertSettings(notificationsEnabled: false, fiveHourThreshold: 20, sevenDayThreshold: 10, resetWarningMinutes: 10),
    now: now
)
expectEqual(disabledAlertCandidates.count, 0, "disabled notifications emit no alerts")

let earlierSnapshot = UsageSnapshot(
    claude: ProviderUsage(provider: .claude, remainingPercent5h: 40, remainingPercent7d: 70, resetAt5h: nil, resetAt7d: nil, source: .api, error: nil, plan: nil, model: nil, updatedAt: now.addingTimeInterval(-3600)),
    codex: ProviderUsage(provider: .codex, remainingPercent5h: 90, remainingPercent7d: 99, resetAt5h: nil, resetAt7d: nil, source: .api, error: nil, plan: nil, model: nil, updatedAt: now.addingTimeInterval(-3600)),
    updatedAt: now.addingTimeInterval(-3600)
)
let trend = UsageHistoryFormatter.trendSummary(
    entries: [UsageHistoryEntry(recordedAt: now.addingTimeInterval(-3600), snapshot: earlierSnapshot)],
    current: snapshot,
    window: 24 * 60 * 60
)
expectEqual(trend, "24h trend: Claude 5h +23% 7d +10% Codex 5h +1% 7d 0%", "history trend summarizes 5h and 7d provider deltas")

let missingSevenDayBaseline = UsageSnapshot(
    claude: ProviderUsage(provider: .claude, remainingPercent5h: 40, remainingPercent7d: nil, resetAt5h: nil, resetAt7d: nil, source: .api, error: nil, plan: nil, model: nil, updatedAt: now.addingTimeInterval(-3600)),
    codex: earlierSnapshot.codex,
    updatedAt: now.addingTimeInterval(-3600)
)
let missingSevenDayTrend = UsageHistoryFormatter.trendSummary(
    entries: [UsageHistoryEntry(recordedAt: now.addingTimeInterval(-3600), snapshot: missingSevenDayBaseline)],
    current: snapshot,
    window: 24 * 60 * 60
)
expectEqual(missingSevenDayTrend, "24h trend: Claude 5h +23% 7d -- Codex 5h +1% 7d 0%", "history trend shows -- when a 7d value is missing")
let csv = UsageHistoryFormatter.csvString(for: [UsageHistoryEntry(recordedAt: now, snapshot: snapshot)])
expect(csv.contains("recorded_at,provider,remaining_5h"), "history csv includes header")
expect(csv.contains("claude,63,80"), "history csv includes claude row")

expect(AppPathsProbe.claudeRateLimitPath != AppPathsProbe.codexRateLimitPath, "each provider holds its own cooldown file")

let rateLimitStoreURL = FileManager.default.temporaryDirectory
    .appendingPathComponent("tt-rate-limit-\(UUID().uuidString).json")
let rateLimitStore = RateLimitStore(url: rateLimitStoreURL)
defer { try? FileManager.default.removeItem(at: rateLimitStoreURL) }

expect(rateLimitStore.load() == nil, "rate limit store starts empty")
let futureRetry = Date().addingTimeInterval(300)
rateLimitStore.save(.init(retryAllowedAt: futureRetry, failureCount: 3, fingerprint: "abc123"))
if let persisted = rateLimitStore.load() {
    expect(abs(persisted.retryAllowedAt.timeIntervalSince(futureRetry)) < 1, "future cooldown survives a reload")
    expectEqual(persisted.failureCount, 3, "failure count survives a reload for exponential backoff")
    expectEqual(persisted.fingerprint, "abc123", "credential fingerprint survives a reload")
} else {
    expect(false, "future cooldown survives a reload")
}
rateLimitStore.save(.init(retryAllowedAt: Date().addingTimeInterval(-1), failureCount: 3))
expect(rateLimitStore.load() == nil, "expired cooldown reads as empty")
rateLimitStore.save(.init(retryAllowedAt: futureRetry, failureCount: 1))
rateLimitStore.clear()
expect(rateLimitStore.load() == nil, "cleared cooldown reads as empty")

// Backward compatibility: a legacy record with only a retry instant (written
// before the failure count was persisted) loads with a zero failure count.
let legacyISO = ISO8601DateFormatter().string(from: futureRetry)
try? Data("{\"retryAllowedAt\":\"\(legacyISO)\"}".utf8).write(to: rateLimitStoreURL)
if let legacyState = rateLimitStore.load() {
    expectEqual(legacyState.failureCount, 0, "a legacy record without a failure count loads as zero")
    expect(legacyState.fingerprint == nil, "a legacy record without a fingerprint loads as nil")
} else {
    expect(false, "a legacy record still loads")
}

expectEqual(RateLimitBackoff.cooldown(retryAfter: 300, failureCount: 0, jitter: 0), 300, "first headerless 429 waits the 300s default")
expectEqual(RateLimitBackoff.cooldown(retryAfter: 0, failureCount: 0, jitter: 0), 120, "absent Retry-After falls back to the 120s minimum")
expectEqual(RateLimitBackoff.cooldown(retryAfter: 300, failureCount: 2, jitter: 0), 1200, "repeated 429 escalates exponentially")
expectEqual(RateLimitBackoff.cooldown(retryAfter: 300, failureCount: 5, jitter: 0), 1800, "escalation is capped at 30m")
expectEqual(RateLimitBackoff.cooldown(retryAfter: 3600, failureCount: 0, jitter: 0), 3600, "an explicit longer Retry-After is honored above the cap")
let jitteredCooldown = RateLimitBackoff.cooldown(retryAfter: 300, failureCount: 0, jitter: RateLimitBackoff.jitterFraction)
expect(jitteredCooldown > 300 && jitteredCooldown <= 360, "jitter adds up to 20 percent on top of the base cooldown")

let arbiterNow = Date()
expect(!InstanceArbiter.shouldYield(current: .init(pid: 100, launchDate: arbiterNow), others: []), "a lone instance keeps running")
expect(InstanceArbiter.shouldYield(current: .init(pid: 100, launchDate: arbiterNow), others: [.init(pid: 50, launchDate: arbiterNow.addingTimeInterval(-1))]), "an earlier instance owns the slot")
expect(!InstanceArbiter.shouldYield(current: .init(pid: 100, launchDate: arbiterNow), others: [.init(pid: 200, launchDate: arbiterNow.addingTimeInterval(1))]), "a later instance yields to us")
expect(InstanceArbiter.shouldYield(current: .init(pid: 100, launchDate: arbiterNow), others: [.init(pid: 50, launchDate: arbiterNow)]), "simultaneous launch: the lower pid owns the slot")
expect(!InstanceArbiter.shouldYield(current: .init(pid: 50, launchDate: arbiterNow), others: [.init(pid: 100, launchDate: arbiterNow)]), "simultaneous launch: we survive as the lower pid")

let settingsSuiteName = "tt-settings-\(UUID().uuidString)"
if let migrationDefaults = UserDefaults(suiteName: settingsSuiteName) {
    defer { migrationDefaults.removeSuite(named: settingsSuiteName) }
    migrationDefaults.set(30.0, forKey: "refreshInterval")
    expectEqual(Settings(defaults: migrationDefaults).refreshInterval, 60, "legacy sub-60 refresh interval migrates to the 60s floor")
    migrationDefaults.set(300.0, forKey: "refreshInterval")
    expectEqual(Settings(defaults: migrationDefaults).refreshInterval, 300, "valid refresh interval is left unchanged")
} else {
    expect(false, "settings migration suite is available")
}

// MARK: Usage forecast
func forecastEntry(_ secondsAgo: TimeInterval, claude5h: Int?, claude7d: Int? = 100) -> UsageHistoryEntry {
    let at = now.addingTimeInterval(-secondsAgo)
    let claudeUsage = ProviderUsage(provider: .claude, remainingPercent5h: claude5h, remainingPercent7d: claude7d, resetAt5h: nil, resetAt7d: nil, source: .api, error: nil, plan: nil, model: nil, updatedAt: at)
    let codexUsage = ProviderUsage(provider: .codex, remainingPercent5h: 100, remainingPercent7d: 100, resetAt5h: nil, resetAt7d: nil, source: .api, error: nil, plan: nil, model: nil, updatedAt: at)
    return UsageHistoryEntry(recordedAt: at, snapshot: UsageSnapshot(claude: claudeUsage, codex: codexUsage, updatedAt: at))
}

let steadyEntries = [forecastEntry(3600, claude5h: 60), forecastEntry(1800, claude5h: 50), forecastEntry(0, claude5h: 40)]
let steadyForecast = UsageForecaster.forecast(entries: steadyEntries, provider: .claude, window: .fiveHour, resetAt: now.addingTimeInterval(10800), now: now)
expect(steadyForecast != nil, "forecast is produced for a steady decline")
expectEqual(Int(steadyForecast?.burnPerHour ?? 0), 20, "burn rate is 20%/h")
expectEqual(Int(steadyForecast?.secondsToEmpty ?? 0), 7200, "5h window empties in 2h at the observed rate")
expectEqual(steadyForecast?.willEmptyBeforeReset, true, "empties before a 3h reset")

let earlyResetForecast = UsageForecaster.forecast(entries: steadyEntries, provider: .claude, window: .fiveHour, resetAt: now.addingTimeInterval(3600), now: now)
expectEqual(earlyResetForecast?.willEmptyBeforeReset, false, "does not empty before an earlier reset")

let resetEntries = [forecastEntry(3600, claude5h: 30), forecastEntry(1800, claude5h: 80), forecastEntry(900, claude5h: 70), forecastEntry(0, claude5h: 60)]
let resetForecast = UsageForecaster.forecast(entries: resetEntries, provider: .claude, window: .fiveHour, resetAt: nil, now: now)
expectEqual(Int(resetForecast?.secondsToEmpty ?? 0), 5400, "forecast uses only the post-reset segment")
expectEqual(Int(resetForecast?.burnPerHour ?? 0), 40, "post-reset burn rate is 40%/h")

expect(UsageForecaster.forecast(entries: [forecastEntry(3600, claude5h: 40), forecastEntry(0, claude5h: 50)], provider: .claude, window: .fiveHour, resetAt: nil, now: now) == nil, "no forecast while replenishing")
expect(UsageForecaster.forecast(entries: [forecastEntry(300, claude5h: 60), forecastEntry(0, claude5h: 50)], provider: .claude, window: .fiveHour, resetAt: nil, now: now) == nil, "no forecast under the minimum span")
expect(UsageForecaster.forecast(entries: [forecastEntry(10800, claude5h: 60), forecastEntry(7200, claude5h: 40)], provider: .claude, window: .fiveHour, resetAt: nil, now: now) == nil, "no forecast when the newest sample is stale")

expectEqual(UsageForecaster.durationText(7800), "2h 10m", "duration formats hours and minutes")
expectEqual(UsageForecaster.durationText(2700), "45m", "duration formats minutes")
expectEqual(UsageForecaster.durationText(30), "<1m", "sub-minute duration collapses to <1m")
expectEqual(UsageForecaster.durationText(86400), "1d 0h", "one-day duration switches to days")
expectEqual(UsageForecaster.durationText(273000), "3d 3h", "duration formats days and hours")

let forecastLocalizer = Localizer(language: .english)
expectEqual(
    UsageForecastText.menuLine(forecast: steadyForecast, window: .fiveHour, localizer: forecastLocalizer),
    "Projected depletion: ~2h 0m · empties before reset",
    "5h forecast menu line format is unchanged"
)
expectEqual(
    UsageForecastText.menuLine(forecast: steadyForecast, window: .sevenDay, localizer: forecastLocalizer),
    "Projected depletion: ~2h 0m (7d) · empties before reset",
    "7d fallback forecast line carries the window marker"
)
expect(UsageForecastText.menuLine(forecast: nil, window: .sevenDay, localizer: forecastLocalizer) == nil, "no forecast menu line without a forecast")

let forecastAlertInput = ForecastAlertInput(provider: .claude, window: .fiveHour, forecast: steadyForecast!, resetAt: now.addingTimeInterval(10800))
expectEqual(
    UsageForecastAlert.candidates(inputs: [forecastAlertInput], enabled: true).map(\.id),
    ["claude-5h-empty-before-reset-\(Int(now.addingTimeInterval(10800).timeIntervalSince1970))"],
    "forecast alert fires when depletion precedes reset"
)
expectEqual(UsageForecastAlert.candidates(inputs: [forecastAlertInput], enabled: false).count, 0, "forecast alert suppressed when disabled")
let safeForecastInput = ForecastAlertInput(provider: .claude, window: .fiveHour, forecast: earlyResetForecast!, resetAt: now.addingTimeInterval(3600))
expectEqual(UsageForecastAlert.candidates(inputs: [safeForecastInput], enabled: true).count, 0, "no forecast alert when the reset comes first")

// MARK: Sparkline
expectEqual(SparklineText.render([0, 25, 50, 75, 100]), "▁▃▅▇█", "sparkline maps values across the eight blocks")
expectEqual(SparklineText.render([42]), "", "a single point renders nothing")
expectEqual(SparklineText.render([]), "", "an empty series renders nothing")
let sparkEntries = [forecastEntry(3600, claude5h: 100), forecastEntry(1800, claude5h: 50), forecastEntry(0, claude5h: 0)]
expectEqual(SparklineSeries.build(entries: sparkEntries, provider: .claude, window: .fiveHour), [100, 50, 0], "sparkline series extracts remaining values in time order")
expectEqual(SparklineText.render(SparklineSeries.build(entries: sparkEntries, provider: .claude, window: .fiveHour)), "█▅▁", "end-to-end sparkline render")
let manySparkEntries = (0..<40).map { forecastEntry(TimeInterval(40 - $0) * 60, claude5h: 100) }
expectEqual(SparklineSeries.build(entries: manySparkEntries, provider: .claude, window: .fiveHour, maxPoints: 20).count, 20, "sparkline series is downsampled to maxPoints")

// MARK: Pause controller
let pauseNow = Date()
expect(PauseController.isPaused(until: pauseNow.addingTimeInterval(3600), now: pauseNow), "paused while the resume instant is in the future")
expect(!PauseController.isPaused(until: pauseNow.addingTimeInterval(-10), now: pauseNow), "not paused once the resume instant has passed")
expect(!PauseController.isPaused(until: nil, now: pauseNow), "not paused when unset")
expectEqual(Int(PauseController.remaining(until: pauseNow.addingTimeInterval(1800), now: pauseNow)), 1800, "remaining reports seconds until resume")
expectEqual(Int(PauseController.remaining(until: nil, now: pauseNow)), 0, "remaining is zero when not paused")
expect(PauseController.isIndefinite(until: .distantFuture, now: pauseNow), "a distant-future pause is indefinite")
expect(!PauseController.isIndefinite(until: pauseNow.addingTimeInterval(3600), now: pauseNow), "a timed pause is not indefinite")

// MARK: Codex window mapping
let weeklyOnlyObject: [String: Any] = [
    "plan_type": "plus",
    "rate_limit": [
        "primary_window": [
            "used_percent": 4.0,
            "limit_window_seconds": 604_800.0,
            "reset_at": 1_785_331_564.0
        ]
    ]
]
let weeklyOnlyUsage = CodexUsageParser.parse(object: weeklyOnlyObject, updatedAt: now)
expect(weeklyOnlyUsage != nil, "a weekly-only payload parses")
expectEqual(weeklyOnlyUsage?.remainingPercent5h, nil, "a weekly primary window leaves the 5h lane empty")
expectEqual(weeklyOnlyUsage?.remainingPercent7d, 96, "a weekly primary window fills the 7d lane")
expectEqual(weeklyOnlyUsage?.resetAt5h, nil, "no 5h reset when the 5h window is absent")
expectEqual(weeklyOnlyUsage?.resetAt7d, Date(timeIntervalSince1970: 1_785_331_564), "the weekly reset lands in the 7d lane")
expectEqual(weeklyOnlyUsage?.plan, "plus", "the plan is preserved")

let legacyObject: [String: Any] = [
    "plan_type": "prolite",
    "rate_limit": [
        "primary_window": ["used_percent": 24.2, "reset_at": 1_770_000_000.0],
        "secondary_window": ["used_percent": 98.0, "reset_at": 1_770_500_000.0]
    ]
]
let legacyUsage = CodexUsageParser.parse(object: legacyObject, updatedAt: now)
expectEqual(legacyUsage?.remainingPercent5h, 76, "windows without a length keep positional lanes (primary → 5h)")
expectEqual(legacyUsage?.remainingPercent7d, 2, "windows without a length keep positional lanes (secondary → 7d)")

let swappedWindows = CodexWindowMapper.map(
    primary: CodexRateWindow(usedPercent: 20, resetAt: nil, windowSeconds: 604_800),
    secondary: CodexRateWindow(usedPercent: 10, resetAt: nil, windowSeconds: 18_000)
)
expectEqual(swappedWindows.fiveHour?.usedPercent, 10, "an 18000s window maps to the 5h lane regardless of position")
expectEqual(swappedWindows.sevenDay?.usedPercent, 20, "a 604800s window maps to the 7d lane regardless of position")

let collidingWindows = CodexWindowMapper.map(
    primary: CodexRateWindow(usedPercent: 20, resetAt: nil, windowSeconds: 604_800),
    secondary: CodexRateWindow(usedPercent: 30, resetAt: nil, windowSeconds: 604_800)
)
expectEqual(collidingWindows.sevenDay?.usedPercent, 20, "the first window wins a lane collision")
expect(collidingWindows.fiveHour == nil, "a colliding window is dropped rather than mislabeled")

expect(CodexUsageParser.parse(object: [:]) == nil, "a payload without rate_limit does not parse")

// Credential expiry: the app reads tokens the provider CLIs refresh, so it has to
// recognize a lapsed one locally instead of spending a request to be told 401.
expect(CredentialExpiry.isExpired(nil) == false, "an unknown expiry is not treated as expired")
expect(CredentialExpiry.isExpired(Date().addingTimeInterval(3600)) == false, "a token valid for an hour is usable")
expect(CredentialExpiry.isExpired(Date().addingTimeInterval(-1)) == true, "a lapsed token is expired")
expect(
    CredentialExpiry.isExpired(Date().addingTimeInterval(CredentialExpiry.skew / 2)) == true,
    "a token inside the skew window is expired early rather than lapsing mid-request"
)

// {"alg":"none"} . {"exp":1770000000}
let sampleJWT = "eyJhbGciOiJub25lIn0.eyJleHAiOjE3NzAwMDAwMDB9.sig"
expectEqual(
    CredentialExpiry.jwtExpiry(sampleJWT),
    Date(timeIntervalSince1970: 1_770_000_000),
    "the exp claim is read out of a JWT access token"
)
expect(CredentialExpiry.jwtExpiry("not-a-jwt") == nil, "a non-JWT token has no readable expiry")
expectEqual(
    CredentialExpiry.epochMillisecondsDate(1_770_000_000_000),
    Date(timeIntervalSince1970: 1_770_000_000),
    "Claude Code's millisecond expiresAt is read as a date"
)
expect(CredentialExpiry.epochMillisecondsDate(nil) == nil, "an absent expiresAt has no date")

expectEqual(TokenFingerprint.of(["a"]), TokenFingerprint.of(["a"]), "the same token fingerprints the same")
expect(TokenFingerprint.of(["a"]) != TokenFingerprint.of(["b"]), "signing in again changes the fingerprint")
expectEqual(TokenFingerprint.of(["a", "b"]), TokenFingerprint.of(["b", "a"]), "candidate order does not change the fingerprint")

print("TokenTrackerSmokeTests passed")
