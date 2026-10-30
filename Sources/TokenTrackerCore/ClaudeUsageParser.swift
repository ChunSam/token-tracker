import CoreFoundation
import Foundation

package enum ClaudeUsageParser {
    package static func parse(_ raw: Any, fallbackPlan: String? = nil, updatedAt: Date = Date()) throws -> ProviderUsage {
        guard let object = raw as? [String: Any] else {
            throw UsageError.invalidResponse
        }

        let fiveHour = object["five_hour"] as? [String: Any]
        let sevenDay = object["seven_day"] as? [String: Any]
        let remaining5h = remaining(fiveHour?["utilization"])
        let remaining7d = remaining(sevenDay?["utilization"])
        guard remaining5h != nil || remaining7d != nil else {
            throw UsageError.invalidResponse
        }

        return ProviderUsage(
            provider: .claude,
            remainingPercent5h: remaining5h,
            remainingPercent7d: remaining7d,
            resetAt5h: isoDate(fiveHour?["resets_at"] as? String),
            resetAt7d: isoDate(sevenDay?["resets_at"] as? String),
            source: .api,
            error: nil,
            plan: plan(from: object) ?? fallbackPlan,
            model: nil,
            updatedAt: updatedAt
        )
    }

    static func plan(from object: [String: Any]) -> String? {
        for key in ["plan_type", "planType", "subscription_type", "subscriptionType", "tier", "rate_limit_tier", "rateLimitTier"] {
            if let text = object[key] as? String {
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { return trimmed }
            }
        }
        return nil
    }

    private static func remaining(_ value: Any?) -> Int? {
        let used: Double
        if let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() {
            used = number.doubleValue
        } else if let text = value as? String, let number = Double(text.trimmingCharacters(in: .whitespacesAndNewlines)) {
            used = number
        } else {
            return nil
        }
        guard used.isFinite else { return nil }
        // Clamp before converting to Int, including finite values outside Int's range.
        return remainingPercent(fromUsed: min(100, max(0, used)))
    }
}
