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
expectEqual(DisplayFormatter.statusTitle(snapshot: snapshot, mode: .lowestRemaining), "AI 63%", "lowest display mode")
expectEqual(DisplayFormatter.formatPercent(nil), "--", "missing percent")

print("TokenTrackerSmokeTests passed")
