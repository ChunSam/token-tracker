import Foundation

// Money spent on Claude and Codex beyond what the subscription windows show. See
// docs/cost-display-design.md. Mirrors windows/TokenTracker.Windows.Core/Cost.cs.

/// An amount of money. `Decimal`, never `Double`: Anthropic reports cents as
/// decimal strings, and adding up a month of hourly buckets in binary floating
/// point drifts by whole cents.
public struct CostAmount: Codable, Equatable, Sendable {
    public let value: Decimal
    /// Upper-case ISO 4217 code. Both providers bill in USD.
    public let currency: String

    public init(value: Decimal, currency: String = "USD") {
        self.value = value
        self.currency = currency.uppercased()
    }
}

/// One slice of the month's spend, such as a model.
public struct CostLineItem: Codable, Equatable, Sendable {
    public let name: String
    public let amount: CostAmount

    public init(name: String, amount: CostAmount) {
        self.name = name
        self.amount = amount
    }

    /// The largest items, after adding up those that share a name across pages.
    public static func top(_ items: [CostLineItem], limit: Int = 3) -> [CostLineItem] {
        // Spelled out step by step: as one map/filter/sorted chain this timed out
        // the type checker on CI's compiler.
        var totals: [String: Decimal] = [:]
        var currencies: [String: String] = [:]
        for item in items {
            totals[item.name, default: Decimal(0)] += item.amount.value
            currencies[item.name] = item.amount.currency
        }
        var merged: [CostLineItem] = []
        for (name, value) in totals where value > 0 {
            merged.append(CostLineItem(name: name, amount: CostAmount(value: value, currency: currencies[name] ?? "USD")))
        }
        merged.sort { (lhs: CostLineItem, rhs: CostLineItem) -> Bool in
            if lhs.amount.value != rhs.amount.value {
                return lhs.amount.value > rhs.amount.value
            }
            return lhs.name < rhs.name
        }
        return Array(merged.prefix(limit))
    }
}

/// How far a provider's cost data reaches.
public enum CostFreshness: Equatable, Sendable {
    /// Cost appears within minutes, with no cut-off to report (OpenAI).
    case live
    /// Complete up to this instant; usage after it is missing or partial
    /// (Anthropic's `data_refreshed_at`).
    case refreshedAt(Date)
    /// Nothing is tallied yet for the requested range.
    case notTallied
}

/// One time bucket of cost, as the provider cut it.
public struct CostBucket: Equatable, Sendable {
    public let start: Date
    public let end: Date
    public let amount: CostAmount

    public init(start: Date, end: Date, amount: CostAmount) {
        self.start = start
        self.end = end
        self.amount = amount
    }
}

/// One page of a cost response.
public struct CostPage: Equatable, Sendable {
    public let buckets: [CostBucket]
    public let items: [CostLineItem]
    public let nextPage: String?
    public let freshness: CostFreshness
}

/// This month's spend for one provider, in the device's time zone.
public struct CostReport: Equatable, Sendable {
    /// From local midnight on the 1st. `nil` while nothing is tallied.
    public let monthToDate: CostAmount?
    /// From local midnight today. `nil` while today is not tallied yet, or when
    /// the provider's day buckets do not start at local midnight, so today cannot
    /// be told apart from yesterday.
    public let today: CostAmount?
    public let freshness: CostFreshness
}

/// "Today" and "this month" in the device's time zone. Never a fixed zone: the
/// user is wherever their Mac or PC says they are. Calendar arithmetic, not
/// "midnight + 24h", so days of 23 or 25 hours around a DST change come out right.
public enum CostPeriod {
    public static func dayStart(now: Date, timeZone: TimeZone) -> Date {
        calendar(timeZone).startOfDay(for: now)
    }

    public static func monthStart(now: Date, timeZone: TimeZone) -> Date {
        calendar(timeZone).dateInterval(of: .month, for: now)?.start ?? dayStart(now: now, timeZone: timeZone)
    }

    /// What one fetch asks for: the 1st at local midnight up to now. A month is at
    /// most 31 days, within the Analytics API's limit for one request.
    public static func requestRange(now: Date, timeZone: TimeZone) -> DateInterval {
        DateInterval(start: monthStart(now: now, timeZone: timeZone), end: max(now, monthStart(now: now, timeZone: timeZone)))
    }

    /// `2026-11`, for keys that last one local month.
    public static func monthKey(now: Date, timeZone: TimeZone) -> String {
        let parts = calendar(timeZone).dateComponents([.year, .month], from: now)
        return String(format: "%04d-%02d", parts.year ?? 0, parts.month ?? 0)
    }

    private static func calendar(_ timeZone: TimeZone) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }
}

public enum CostAggregator {
    /// A bucket that starts this much before local midnight still counts toward the
    /// new day. Anthropic rounds hourly buckets down to the hour, so a zone half or
    /// three quarters of an hour off UTC gets its day boundary up to 45 minutes
    /// early; a day bucket that starts at UTC midnight is hours off and does not.
    public static let boundaryTolerance: TimeInterval = 3600

    /// Adds up the buckets that overlap this month and today, in `timeZone`.
    public static func report(buckets: [CostBucket], freshness: CostFreshness, now: Date, timeZone: TimeZone) -> CostReport {
        if case .notTallied = freshness {
            return CostReport(monthToDate: nil, today: nil, freshness: freshness)
        }
        let monthStart = CostPeriod.monthStart(now: now, timeZone: timeZone)
        let dayStart = CostPeriod.dayStart(now: now, timeZone: timeZone)
        let currency = buckets.first?.amount.currency ?? "USD"

        var monthTotal = Decimal(0)
        var todayTotal = Decimal(0)
        var straddles = false
        for bucket in buckets {
            if overlaps(bucket, from: monthStart, to: now) {
                monthTotal += bucket.amount.value
            }
            if overlaps(bucket, from: dayStart, to: now) {
                todayTotal += bucket.amount.value
                if dayStart.timeIntervalSince(bucket.start) > boundaryTolerance {
                    straddles = true
                }
            }
        }
        // A watermark from before the 1st covers none of this month: not tallied,
        // rather than a month of nothing.
        var monthToDate: CostAmount? = CostAmount(value: monthTotal, currency: currency)
        if case .refreshedAt(let refreshed) = freshness, refreshed <= monthStart {
            monthToDate = nil
        }

        var today: CostAmount?
        let tallied: Bool
        if case .refreshedAt(let refreshed) = freshness {
            tallied = refreshed > dayStart
        } else {
            tallied = true
        }
        if tallied, !straddles {
            today = CostAmount(value: todayTotal, currency: currency)
        }
        return CostReport(monthToDate: monthToDate, today: today, freshness: freshness)
    }

    private static func overlaps(_ bucket: CostBucket, from start: Date, to end: Date) -> Bool {
        bucket.end > start && bucket.start < end
    }
}

/// `GET /v1/organizations/analytics/cost` (Analytics API, beta). Amounts are cents
/// as decimal strings with six places: `"41280.000000"` is $412.80.
///
/// Two requests feed a report: hourly buckets for the totals, and one grouped by
/// `model` without buckets for the split. The second returns one row per model
/// spanning the whole range, so take its `items` and not its `buckets`.
public enum AnthropicCostParser {
    public static func page(_ json: [String: Any]) -> CostPage? {
        guard let rows = json["data"] as? [[String: Any]] else { return nil }
        var buckets: [CostBucket] = []
        var items: [CostLineItem] = []
        for row in rows {
            guard
                let cost = row["cost"] as? [String: Any],
                let cents = decimal(cost["amount"])
            else { continue }
            let amount = CostAmount(value: cents / 100, currency: (cost["currency"] as? String) ?? "USD")
            if let start = isoDate(row["starting_at"] as? String), let end = isoDate(row["ending_at"] as? String) {
                buckets.append(CostBucket(start: start, end: end, amount: amount))
            }
            if let group = row["group"] as? [String: Any], let model = group["model"] as? String, !model.isEmpty {
                items.append(CostLineItem(name: model, amount: amount))
            }
        }
        let freshness: CostFreshness
        if let refreshed = isoDate(json["data_refreshed_at"] as? String) {
            freshness = .refreshedAt(refreshed)
        } else {
            freshness = .notTallied
        }
        let hasMore = (json["has_more"] as? Bool) ?? false
        return CostPage(
            buckets: buckets,
            items: items,
            nextPage: hasMore ? json["next_page"] as? String : nil,
            freshness: freshness
        )
    }
}

/// `GET /v1/organization/costs`. Amounts are dollars as numbers. The published
/// schema names the bucket's list `result` while its example response says
/// `results`, so both are read.
public enum OpenAICostParser {
    public static func page(_ json: [String: Any]) -> CostPage? {
        guard let rows = json["data"] as? [[String: Any]] else { return nil }
        var buckets: [CostBucket] = []
        var items: [CostLineItem] = []
        for row in rows {
            guard let start = timestampDate(row["start_time"]), let end = timestampDate(row["end_time"]) else { continue }
            let results = (row["results"] as? [[String: Any]]) ?? (row["result"] as? [[String: Any]]) ?? []
            var total: Decimal = 0
            var currency = "USD"
            for result in results {
                guard let money = result["amount"] as? [String: Any], let value = decimal(money["value"]) else { continue }
                currency = (money["currency"] as? String)?.uppercased() ?? currency
                total += value
                if let item = result["line_item"] as? String, !item.isEmpty {
                    items.append(CostLineItem(name: item, amount: CostAmount(value: value, currency: currency)))
                }
            }
            buckets.append(CostBucket(start: start, end: end, amount: CostAmount(value: total, currency: currency)))
        }
        let hasMore = (json["has_more"] as? Bool) ?? false
        return CostPage(
            buckets: buckets,
            items: items,
            nextPage: hasMore ? json["next_page"] as? String : nil,
            freshness: .live
        )
    }
}

/// Claude extra usage: what the account has spent past its plan limits.
public struct ClaudeExtraUsage: Codable, Equatable, Sendable {
    public let used: CostAmount
    public let limit: CostAmount?
    /// The provider's own word for how close the limit is, such as `normal`.
    public let severity: String?

    public init(used: CostAmount, limit: CostAmount?, severity: String?) {
        self.used = used
        self.limit = limit
        self.severity = severity
    }
}

/// Money the subscription usage responses already carry. Each reading is `nil`
/// unless the account actually pays this way, which is what keeps money off the
/// screen of a subscription-only user. A missing or unexpected field reads as off.
public enum SubscriptionCostParser {
    /// From `GET /api/oauth/usage`. Extra usage counts as on when either `spend` or
    /// `extra_usage` says so; the amount comes from `spend.used`, the one field
    /// that states its own unit.
    public static func claudeExtraUsage(_ json: [String: Any]) -> ClaudeExtraUsage? {
        let spend = json["spend"] as? [String: Any]
        let extra = json["extra_usage"] as? [String: Any]
        let enabled = (spend?["enabled"] as? Bool) == true || (extra?["is_enabled"] as? Bool) == true
        guard enabled, let used = minorUnits(spend?["used"]) else { return nil }
        return ClaudeExtraUsage(used: used, limit: minorUnits(spend?["limit"]), severity: spend?["severity"] as? String)
    }

    /// From `GET /backend-api/wham/usage`: the credit balance, in credits rather than
    /// dollars. `nil` for an account without credits.
    public static func codexCredits(_ json: [String: Any]) -> Decimal? {
        guard
            let credits = json["credits"] as? [String: Any],
            (credits["has_credits"] as? Bool) == true
        else { return nil }
        return decimal(credits["balance"])
    }

    /// From the same response: `true` once an account that holds credits has hit
    /// its overage limit. An account without credits reads as `nil` whatever the
    /// flag says, so a subscription-only user is never told about credits.
    public static func codexCreditLimitReached(_ json: [String: Any]) -> Bool? {
        guard
            let credits = json["credits"] as? [String: Any],
            (credits["has_credits"] as? Bool) == true,
            (credits["overage_limit_reached"] as? Bool) == true
        else { return nil }
        return true
    }

    /// `{ "amount_minor": 186, "currency": "USD", "exponent": 2 }` is $1.86.
    private static func minorUnits(_ value: Any?) -> CostAmount? {
        guard
            let money = value as? [String: Any],
            let minor = decimal(money["amount_minor"]),
            let exponent = money["exponent"] as? Int, (0...6).contains(exponent)
        else { return nil }
        var divisor: Decimal = 1
        for _ in 0..<exponent { divisor *= 10 }
        return CostAmount(value: minor / divisor, currency: (money["currency"] as? String) ?? "USD")
    }
}

/// One line of money on a provider's card or submenu, from what its subscription
/// usage response carried.
public struct SubscriptionCostLine: Equatable, Sendable {
    public let label: String
    /// `$1.86 / $5.00`, `$1.86` without a limit, or a credit balance such as `18.40`.
    public let value: String
    /// Whole percent of the extra usage limit spent, for a bar. `nil` without a limit.
    public let percent: Int?
}

public enum SubscriptionCostText {
    /// `nil` unless the account pays past its plan, so a subscription-only card
    /// stays exactly as it was.
    public static func line(for usage: ProviderUsage, localizer: Localizer) -> SubscriptionCostLine? {
        if let extra = usage.extraUsage {
            var value = CostFormatter.text(extra.used)
            var percent: Int?
            if let limit = extra.limit, limit.currency == extra.used.currency {
                value += " / " + CostFormatter.text(limit)
                percent = CostBudget.percent(spent: extra.used.value, budget: limit.value)
            }
            return SubscriptionCostLine(label: localizer.text(.costExtraUsage), value: value, percent: percent)
        }
        if let balance = usage.creditBalance {
            return SubscriptionCostLine(label: localizer.text(.costCreditBalance), value: CostFormatter.credits(balance), percent: nil)
        }
        return nil
    }
}

/// Whether a provider gets any money on screen: popup, menu bar, tray or alert.
/// Every one of them asks this, so a subscription-only user with extra usage off
/// sees no trace of the feature.
public enum CostVisibility {
    public static func shows(subscriptionExtra: Bool, apiCostEnabled: Bool, hasAdminKey: Bool) -> Bool {
        subscriptionExtra || (apiCostEnabled && hasAdminKey)
    }

    /// The menu bar keeps showing percentages while subscription limits are shown;
    /// only a provider tracked by API cost alone puts its month's spend there.
    public static func menuBarShowsCost(subscriptionLimitsShown: Bool, apiCostShown: Bool) -> Bool {
        !subscriptionLimitsShown && apiCostShown
    }
}

public enum CostFormatter {
    /// `$12.34`, `$1.2K`, `$3.4M`, `<$0.01`; other currencies as `12.34 EUR`.
    /// Rounds half away from zero, the same on both ports.
    public static func text(_ amount: CostAmount) -> String {
        let value = amount.value
        let magnitude = value < 0 ? -value : value
        let sign = value < 0 ? "-" : ""
        let number: String
        if magnitude >= 1_000_000 {
            number = fixed(magnitude / 1_000_000, places: 1) + "M"
        } else if magnitude >= 1000 {
            number = fixed(magnitude / 1000, places: 1) + "K"
        } else if magnitude > 0, magnitude < Decimal(string: "0.01")! {
            return amount.currency == "USD" ? "<$0.01" : "<0.01 \(amount.currency)"
        } else {
            number = fixed(magnitude, places: 2)
        }
        return amount.currency == "USD" ? "\(sign)$\(number)" : "\(sign)\(number) \(amount.currency)"
    }

    /// The menu bar's short form: whole dollars from $10 (`$42`), cents below that
    /// so a small spend does not read as `$0` (`$3.07`), and `$1.2K` from a thousand.
    public static func compact(_ amount: CostAmount) -> String {
        let magnitude = amount.value < 0 ? -amount.value : amount.value
        guard magnitude >= 10, magnitude < 1000 else { return text(amount) }
        let sign = amount.value < 0 ? "-" : ""
        let number = fixed(magnitude, places: 0)
        return amount.currency == "USD" ? "\(sign)$\(number)" : "\(sign)\(number) \(amount.currency)"
    }

    /// A credit balance, which is not money: `18.40`.
    public static func credits(_ value: Decimal) -> String {
        fixed(value, places: 2)
    }

    static func fixed(_ value: Decimal, places: Int) -> String {
        var input = value
        var rounded = Decimal()
        NSDecimalRound(&rounded, &input, places, .plain)
        let text = NSDecimalNumber(decimal: rounded).stringValue
        let parts = text.split(separator: ".", omittingEmptySubsequences: false)
        let whole = parts.first.map(String.init) ?? "0"
        let fraction = parts.count > 1 ? String(parts[1]) : ""
        guard places > 0 else { return whole }
        return whole + "." + fraction.padding(toLength: places, withPad: "0", startingAt: 0)
    }
}

/// A monthly budget, in the provider's currency. Zero is off.
public enum CostBudget {
    public static let thresholds = [80, 100]

    /// Whole percent of the budget spent, rounded down. `nil` with no budget.
    public static func percent(spent: Decimal, budget: Decimal) -> Int? {
        guard budget > 0 else { return nil }
        var ratio = spent * 100 / budget
        var floored = Decimal()
        NSDecimalRound(&floored, &ratio, 0, .down)
        return NSDecimalNumber(decimal: floored).intValue
    }

    /// The thresholds this month's spend has reached.
    public static func reachedThresholds(spent: Decimal, budget: Decimal) -> [Int] {
        guard let percent = percent(spent: spent, budget: budget) else { return [] }
        return thresholds.filter { percent >= $0 }
    }

    /// One alert per threshold per local month: `claude-cost-80-2026-11`.
    public static func alertID(provider: Provider, threshold: Int, now: Date, timeZone: TimeZone) -> String {
        "\(provider.rawValue)-cost-\(threshold)-\(CostPeriod.monthKey(now: now, timeZone: timeZone))"
    }
}

/// When to ask an Admin API again. Anthropic's Analytics data moves every few
/// hours, and its 60 requests a minute are shared by everything the organization
/// runs against the API, so ten minutes loses nothing.
public enum CostFetchPolicy {
    public static let interval: TimeInterval = 600
    public static let retryInterval: TimeInterval = 300

    public static func nextFetch(after attemptAt: Date, succeeded: Bool) -> Date {
        attemptAt.addingTimeInterval(succeeded ? interval : retryInterval)
    }

    /// No fetch yet is due at once.
    public static func isDue(nextFetchAt: Date?, now: Date) -> Bool {
        guard let nextFetchAt else { return true }
        return now >= nextFetchAt
    }
}

/// A JSON number or numeric string as an exact `Decimal`. Numbers go through their
/// shortest text form, so `0.06` stays 0.06 rather than its binary neighbour.
private func decimal(_ value: Any?) -> Decimal? {
    switch value {
    case let text as String:
        return Decimal(string: text.trimmingCharacters(in: .whitespaces), locale: Locale(identifier: "en_US_POSIX"))
    case let number as NSNumber:
        if CFGetTypeID(number) == CFBooleanGetTypeID() { return nil }
        return Decimal(string: number.stringValue, locale: Locale(identifier: "en_US_POSIX"))
    default:
        return nil
    }
}
