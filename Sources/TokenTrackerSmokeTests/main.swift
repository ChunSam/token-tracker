import Foundation
import TokenTrackerCore

func expectEqual<T: Equatable>(_ actual: T, _ expected: T, _ message: String) {
    if actual != expected {
        fputs("FAIL: \(message). expected \(expected), got \(actual)\n", stderr)
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

expectEqual(UsageError.httpStatus(code: 401, service: "Claude API").localizedDescription, "HTTP 401 from Claude API", "HTTP status error names Claude API")
expectEqual(UsageError.timedOut(service: "Claude API").localizedDescription, "Timed out contacting Claude API", "timeout error names Claude API")
expectEqual(UsageError.network(message: "offline", service: "Claude API").localizedDescription, "Network error from Claude API: offline", "network error names Claude API")

print("TokenTrackerSmokeTests passed")
