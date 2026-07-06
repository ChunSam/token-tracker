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
expectEqual(DisplayFormatter.displaysSevenDayPercent(healthySevenDaySnapshot.claude), false, "healthy seven day value is not highlighted")
expectEqual(DisplayFormatter.displaysSevenDayPercent(exhaustedSevenDaySnapshot.claude), true, "exhausted seven day value is highlighted")

let sevenDayThresholdUsage = ProviderUsage(provider: .claude, remainingPercent5h: 100, remainingPercent7d: 10, resetAt5h: nil, resetAt7d: nil, source: .api, error: nil, plan: nil, model: nil, updatedAt: now)
let missingSevenDayUsage = ProviderUsage(provider: .claude, remainingPercent5h: 73, remainingPercent7d: nil, resetAt5h: nil, resetAt7d: nil, source: .api, error: nil, plan: nil, model: nil, updatedAt: now)
let missingFiveHourUsage = ProviderUsage(provider: .claude, remainingPercent5h: nil, remainingPercent7d: 42, resetAt5h: nil, resetAt7d: nil, source: .api, error: nil, plan: nil, model: nil, updatedAt: now)
let staleClaudeUsage = ProviderUsage(provider: .claude, remainingPercent5h: 64, remainingPercent7d: 82, resetAt5h: nil, resetAt7d: nil, source: .staleCache, error: "HTTP 429 from Claude API", plan: nil, model: nil, updatedAt: now)

expectEqual(DisplayFormatter.displayPercent(sevenDayThresholdUsage), 10, "7d value is shown at 10 percent threshold")
expectEqual(DisplayFormatter.displaysSevenDayPercent(sevenDayThresholdUsage), true, "7d threshold value is highlighted")
expectEqual(DisplayFormatter.displayPercent(missingSevenDayUsage), 73, "5h value is shown when 7d is missing")
expectEqual(DisplayFormatter.displaysSevenDayPercent(missingSevenDayUsage), false, "missing 7d is not highlighted")
expectEqual(DisplayFormatter.displayPercent(missingFiveHourUsage), 42, "7d value is shown when 5h is missing")
expectEqual(DisplayFormatter.displaysSevenDayPercent(missingFiveHourUsage), true, "7d fallback is highlighted when 5h is missing")
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
expectEqual(trend, "24h trend: Claude 5h +23% Codex 5h +1%", "history trend summarizes provider deltas")
let csv = UsageHistoryFormatter.csvString(for: [UsageHistoryEntry(recordedAt: now, snapshot: snapshot)])
expect(csv.contains("recorded_at,provider,remaining_5h"), "history csv includes header")
expect(csv.contains("claude,63,80"), "history csv includes claude row")

let rateLimitStoreURL = FileManager.default.temporaryDirectory
    .appendingPathComponent("tt-rate-limit-\(UUID().uuidString).json")
let rateLimitStore = ClaudeRateLimitStore(url: rateLimitStoreURL)
defer { try? FileManager.default.removeItem(at: rateLimitStoreURL) }

expect(rateLimitStore.load() == nil, "rate limit store starts empty")
let futureRetry = Date().addingTimeInterval(300)
rateLimitStore.save(.init(retryAllowedAt: futureRetry, failureCount: 3))
if let persisted = rateLimitStore.load() {
    expect(abs(persisted.retryAllowedAt.timeIntervalSince(futureRetry)) < 1, "future cooldown survives a reload")
    expectEqual(persisted.failureCount, 3, "failure count survives a reload for exponential backoff")
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

print("TokenTrackerSmokeTests passed")
