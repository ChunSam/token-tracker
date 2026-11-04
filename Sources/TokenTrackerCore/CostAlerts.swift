import Foundation

// Money alerts: a monthly budget reached, Claude extra usage leaving `normal`, Codex
// reaching its credit overage limit. Each goes out once per local month, remembered
// across relaunches, and only to an account that pays this way: the same rule that
// keeps money off screen. Mirrors windows/TokenTracker.Windows.Core/CostAlerts.cs.

public struct CostAlertResult: Equatable, Sendable {
    /// To send now.
    public let alerts: [UsageAlertCandidate]
    /// What has gone out this local month, the alerts above included. Store it and
    /// pass it back next time; months gone by are already dropped.
    public let delivered: Set<String>
}

public enum CostAlertEvaluator {
    /// Each alert's id ends in its local month, which is all it takes to forget the
    /// months that are over and to say each thing again in a new one.
    public static func evaluate(
        snapshot: UsageSnapshot?,
        costs: [Provider: CostState],
        budgets: [Provider: Int],
        delivered: Set<String>,
        notificationsEnabled: Bool,
        now: Date,
        timeZone: TimeZone,
        localizer: Localizer
    ) -> CostAlertResult {
        let month = CostPeriod.monthKey(now: now, timeZone: timeZone)
        var sent = delivered.filter { $0.hasSuffix("-" + month) }
        // Off sends nothing and records nothing, so switching notifications on
        // later in the month still says what is true by then.
        guard notificationsEnabled else {
            return CostAlertResult(alerts: [], delivered: sent)
        }

        var alerts: [UsageAlertCandidate] = []
        for provider in Provider.allCases {
            if let alert = budgetAlert(
                provider,
                state: costs[provider] ?? CostState(),
                budget: budgets[provider] ?? 0,
                sent: &sent,
                now: now,
                timeZone: timeZone,
                localizer: localizer
            ) {
                alerts.append(alert)
            }
        }
        if let snapshot {
            if let alert = extraUsageAlert(snapshot.claude, month: month, sent: &sent, localizer: localizer) {
                alerts.append(alert)
            }
            if let alert = creditLimitAlert(snapshot.codex, month: month, sent: &sent, localizer: localizer) {
                alerts.append(alert)
            }
        }
        return CostAlertResult(alerts: alerts, delivered: sent)
    }

    /// The highest threshold reached, once. A month that jumps past both in one
    /// fetch says 100% and counts 80% as said, rather than sending two at once.
    private static func budgetAlert(
        _ provider: Provider,
        state: CostState,
        budget: Int,
        sent: inout Set<String>,
        now: Date,
        timeZone: TimeZone,
        localizer: Localizer
    ) -> UsageAlertCandidate? {
        guard
            budget > 0,
            CostVisibility.shows(subscriptionExtra: false, apiCostEnabled: state.enabled, hasAdminKey: state.keySuffix != nil),
            let month = state.cost?.monthToDate
        else { return nil }
        let reached = CostBudget.reachedThresholds(spent: month.value, budget: Decimal(budget))
        let ids = reached.map { CostBudget.alertID(provider: provider, threshold: $0, now: now, timeZone: timeZone) }
        guard let highestID = ids.last, !sent.contains(highestID) else { return nil }
        sent.formUnion(ids)
        let percent = CostBudget.percent(spent: month.value, budget: Decimal(budget)) ?? 0
        return UsageAlertCandidate(
            id: highestID,
            title: localizer.text(.costBudgetAlertTitle),
            body: localizer.text(.costBudgetAlertBody)
                .replacingOccurrences(of: "{organization}", with: AdminKeyText.organization(provider))
                .replacingOccurrences(of: "{amount}", with: CostFormatter.text(month))
                .replacingOccurrences(of: "{budget}", with: CostFormatter.compact(CostAmount(value: Decimal(budget))))
                .replacingOccurrences(of: "{percent}", with: String(percent))
        )
    }

    /// Claude's own word for how close extra usage is to its limit, once it is no
    /// longer `normal`. The word goes in the id, so a step further up is news too.
    private static func extraUsageAlert(
        _ usage: ProviderUsage,
        month: String,
        sent: inout Set<String>,
        localizer: Localizer
    ) -> UsageAlertCandidate? {
        guard let severity = usage.extraUsage?.severity?.lowercased(), severity != "normal" else { return nil }
        let level = severity.filter { $0.isLetter || $0 == "_" }
        let id = "claude-extra-\(level)-\(month)"
        guard !level.isEmpty, !sent.contains(id), let line = SubscriptionCostText.line(for: usage, localizer: localizer) else {
            return nil
        }
        sent.insert(id)
        return UsageAlertCandidate(
            id: id,
            title: localizer.text(.extraUsageAlertTitle),
            body: localizer.text(.extraUsageAlertBody).replacingOccurrences(of: "{value}", with: line.value)
        )
    }

    private static func creditLimitAlert(
        _ usage: ProviderUsage,
        month: String,
        sent: inout Set<String>,
        localizer: Localizer
    ) -> UsageAlertCandidate? {
        let id = "codex-credits-limit-\(month)"
        guard usage.creditLimitReached == true, !sent.contains(id) else { return nil }
        sent.insert(id)
        return UsageAlertCandidate(
            id: id,
            title: localizer.text(.creditLimitAlertTitle),
            body: localizer.text(.creditLimitAlertBody)
        )
    }
}
