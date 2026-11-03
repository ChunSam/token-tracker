import Foundation

// What the Admin API cost puts on screen: the card or submenu, the menu bar, the
// tray. Every surface goes through `AdminCostText.view`, which is `nil` unless
// the provider's API cost is switched on and has a key, so a user who never set
// this up sees nothing of it. Mirrors windows/TokenTracker.Windows.Core/CostDisplay.cs.

/// One provider's API cost, worded for a card or a submenu.
public struct AdminCostView: Equatable, Sendable {
    public enum Status: String, Sendable {
        case ok
        /// Switched on with a key, waiting for the first answer.
        case loading
        /// An earlier reading, standing in for a fetch that failed.
        case cached
        case keyRejected
        case rateLimited
        case failed
    }

    public let status: Status
    public let statusTitle: String
    public let monthLabel: String
    /// `$42.18`, or `Not tallied yet` while the month has nothing in it yet.
    public let monthValue: String
    /// Whole percent of the monthly budget spent, for a bar. `nil` without a budget.
    public let budgetPercent: Int?
    /// `42% of $100 budget`.
    public let budgetText: String?
    /// `Today $3.07 · Opus 5.5 71% · Sonnet 5.5 27%`.
    public let detail: String?
    /// `as of 14:20`: how far Anthropic's data reaches. `nil` for OpenAI.
    public let asOf: String?
    /// What went wrong, in English, for a tooltip.
    public let failureMessage: String?

    /// The budget alert thresholds colour the amount: orange from 80%, red at 100%.
    public var isBudgetWarning: Bool {
        (budgetPercent ?? 0) >= CostBudget.thresholds[0]
    }
}

public enum AdminCostText {
    /// `nil` unless the provider's API cost is switched on and has a key.
    public static func view(state: CostState, budget: Int, now: Date, timeZone: TimeZone, localizer: Localizer) -> AdminCostView? {
        guard CostVisibility.shows(subscriptionExtra: false, apiCostEnabled: state.enabled, hasAdminKey: state.keySuffix != nil) else {
            return nil
        }
        let cost = state.cost
        let status = status(state)

        var monthValue = "--"
        if let cost {
            monthValue = cost.monthToDate.map(CostFormatter.text) ?? localizer.text(.costNotYetTallied)
        }

        var budgetPercent: Int?
        var budgetText: String?
        if budget > 0, let month = cost?.monthToDate {
            let percent = CostBudget.percent(spent: month.value, budget: Decimal(budget)) ?? 0
            budgetPercent = percent
            budgetText = localizer.text(.costBudget)
                .replacingOccurrences(of: "{limit}", with: CostFormatter.compact(CostAmount(value: Decimal(budget))))
                .replacingOccurrences(of: "{percent}", with: String(percent))
        }

        var parts: [String] = []
        if let cost, let month = cost.monthToDate {
            parts.append("\(localizer.text(.costToday)) \(cost.today.map(CostFormatter.text) ?? localizer.text(.costNotYetTallied))")
            if month.value > 0 {
                for item in cost.topItems.prefix(2) {
                    let share = CostBudget.percent(spent: item.amount.value, budget: month.value) ?? 0
                    parts.append("\(CostItemName.display(item.name)) \(share)%")
                }
            }
        }

        var asOf: String?
        if let refreshed = cost?.dataRefreshedAt {
            asOf = localizer.text(.costAsOf)
                .replacingOccurrences(of: "{time}", with: timeText(refreshed, now: now, timeZone: timeZone, localizer: localizer))
        }

        return AdminCostView(
            status: status,
            statusTitle: title(status, localizer: localizer),
            monthLabel: localizer.text(.costThisMonth),
            monthValue: monthValue,
            budgetPercent: budgetPercent,
            budgetText: budgetText,
            detail: parts.isEmpty ? nil : parts.joined(separator: " · "),
            asOf: asOf,
            failureMessage: state.failure?.message
        )
    }

    /// A rejected key outranks a cached reading: it will not mend itself, and the
    /// reading behind it only gets older.
    static func status(_ state: CostState) -> AdminCostView.Status {
        if state.failure?.kind == .keyRejected { return .keyRejected }
        if state.isCached { return .cached }
        switch state.failure?.kind {
        case .rateLimited: return .rateLimited
        case .failed, .keyRejected: return .failed
        case nil: return state.cost == nil ? .loading : .ok
        }
    }

    private static func title(_ status: AdminCostView.Status, localizer: Localizer) -> String {
        switch status {
        case .ok: localizer.text(.statusOK)
        case .loading: localizer.text(.costLoading)
        case .cached: localizer.text(.statusUsingCachedData)
        case .keyRejected: localizer.text(.costAdminKeyRejected)
        case .rateLimited: localizer.text(.statusRateLimited)
        case .failed: localizer.text(.costFetchFailed)
        }
    }

    /// `14:20` today in the device's zone, `Nov 2 22:10` or `11월 2일 22:10` on another
    /// day. Twenty-four-hour on both ports, so the two read the same.
    static func timeText(_ date: Date, now: Date, timeZone: TimeZone, localizer: Localizer) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.month, .day, .hour, .minute], from: date)
        let time = String(format: "%02d:%02d", parts.hour ?? 0, parts.minute ?? 0)
        if calendar.isDate(date, inSameDayAs: now) {
            return time
        }
        let month = parts.month ?? 1
        let day = parts.day ?? 1
        switch localizer.language {
        case .korean:
            return "\(month)월 \(day)일 \(time)"
        case .system, .english:
            return "\(monthNames[max(0, min(11, month - 1))]) \(day) \(time)"
        }
    }

    private static let monthNames = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
}

public enum CostItemName {
    /// `claude-opus-5-5` is `Opus 5.5`, `claude-sonnet-4-5-20250929` is `Sonnet 4.5`.
    /// Anything else stays as the provider named it.
    public static func display(_ name: String) -> String {
        let prefix = "claude-"
        guard name.hasPrefix(prefix) else { return name }
        let parts = name.dropFirst(prefix.count).split(separator: "-").map(String.init)
        guard let family = parts.first(where: { $0.first?.isLetter == true }) else { return name }
        // A date stamp is eight digits; a version is one or two.
        let version = parts.filter { !$0.isEmpty && $0.count < 8 && $0.allSatisfy(\.isNumber) }
        let title = family.prefix(1).uppercased() + family.dropFirst()
        return version.isEmpty ? title : title + " " + version.joined(separator: ".")
    }

    /// OpenAI splits a model into line items such as `gpt-6, input` and
    /// `gpt-6, output`; they add up under the model.
    public static func lineItemGroup(_ name: String) -> String {
        name.components(separatedBy: ", ").first ?? name
    }
}

/// The money a provider tracked by API cost alone puts in the menu bar.
public struct MenuBarCost: Equatable, Sendable {
    /// `$42`, `$3.07`, `$1.2K`, or `--` before the first reading.
    public let text: String
    /// From 80% of the monthly budget.
    public let isWarning: Bool

    public init(text: String, isWarning: Bool) {
        self.text = text
        self.isWarning = isWarning
    }
}

public enum CostMenuBar {
    /// One entry per provider whose subscription limits are off and whose API cost
    /// is on with a key. A provider showing its limits keeps its percentage.
    public static func entries(
        subscriptionShown: [Provider: Bool],
        states: [Provider: CostState],
        budgets: [Provider: Int]
    ) -> [Provider: MenuBarCost] {
        var entries: [Provider: MenuBarCost] = [:]
        for provider in Provider.allCases {
            let state = states[provider] ?? CostState()
            let apiCostShown = CostVisibility.shows(subscriptionExtra: false, apiCostEnabled: state.enabled, hasAdminKey: state.keySuffix != nil)
            guard CostVisibility.menuBarShowsCost(subscriptionLimitsShown: subscriptionShown[provider] ?? true, apiCostShown: apiCostShown) else {
                continue
            }
            let month = state.cost?.monthToDate
            let budget = budgets[provider] ?? 0
            let percent = month.flatMap { CostBudget.percent(spent: $0.value, budget: Decimal(budget)) } ?? 0
            entries[provider] = MenuBarCost(
                text: month.map(CostFormatter.compact) ?? "--",
                isWarning: percent >= CostBudget.thresholds[0]
            )
        }
        return entries
    }

    /// The Windows tray icon draws a percentage. With every subscription limit off
    /// and only money left to show, it draws `$` instead.
    public static func trayShowsDollar(subscriptionShown: [Provider: Bool], entries: [Provider: MenuBarCost]) -> Bool {
        !entries.isEmpty && !Provider.allCases.contains { subscriptionShown[$0] ?? true }
    }
}
