using System.Globalization;

namespace TokenTracker.Windows.Core;

// Money alerts: a monthly budget reached, Claude extra usage leaving `normal`, Codex
// reaching its credit overage limit. Each goes out once per local month, remembered
// across relaunches, and only to an account that pays this way: the same rule that
// keeps money off screen. Mirrors Sources/TokenTrackerCore/CostAlerts.swift.

/// <param name="Alerts">To send now.</param>
/// <param name="Delivered">What has gone out this local month, the alerts above
/// included. Store it and pass it back next time; months gone by are already dropped.</param>
public sealed record CostAlertResult(IReadOnlyList<UsageAlertCandidate> Alerts, IReadOnlySet<string> Delivered);

public static class CostAlertEvaluator
{
    private static readonly Provider[] Providers = { Provider.Claude, Provider.Codex };

    /// Each alert's id ends in its local month, which is all it takes to forget the
    /// months that are over and to say each thing again in a new one.
    public static CostAlertResult Evaluate(
        UsageSnapshot? snapshot,
        IReadOnlyDictionary<Provider, CostState> costs,
        IReadOnlyDictionary<Provider, int> budgets,
        IEnumerable<string> delivered,
        bool notificationsEnabled,
        DateTimeOffset now,
        TimeZoneInfo timeZone,
        Localizer localizer)
    {
        var month = CostPeriod.MonthKey(now, timeZone);
        var sent = delivered
            .Where(id => id.EndsWith("-" + month, StringComparison.Ordinal))
            .ToHashSet(StringComparer.Ordinal);
        // Off sends nothing and records nothing, so switching notifications on
        // later in the month still says what is true by then.
        if (!notificationsEnabled)
        {
            return new CostAlertResult(Array.Empty<UsageAlertCandidate>(), sent);
        }

        var alerts = new List<UsageAlertCandidate>();
        foreach (var provider in Providers)
        {
            var state = costs.TryGetValue(provider, out var found) ? found : new CostState();
            var budget = budgets.TryGetValue(provider, out var value) ? value : 0;
            if (BudgetAlert(provider, state, budget, sent, now, timeZone, localizer) is { } alert)
            {
                alerts.Add(alert);
            }
        }

        if (snapshot is not null)
        {
            if (ExtraUsageAlert(snapshot.Claude, month, sent, localizer) is { } extra)
            {
                alerts.Add(extra);
            }

            if (CreditLimitAlert(snapshot.Codex, month, sent, localizer) is { } credits)
            {
                alerts.Add(credits);
            }
        }

        return new CostAlertResult(alerts, sent);
    }

    /// The highest threshold reached, once. A month that jumps past both in one
    /// fetch says 100% and counts 80% as said, rather than sending two at once.
    private static UsageAlertCandidate? BudgetAlert(
        Provider provider,
        CostState state,
        int budget,
        HashSet<string> sent,
        DateTimeOffset now,
        TimeZoneInfo timeZone,
        Localizer localizer)
    {
        if (budget <= 0 ||
            !CostVisibility.Shows(subscriptionExtra: false, apiCostEnabled: state.Enabled, hasAdminKey: state.KeySuffix is not null) ||
            state.Cost?.MonthToDate is not { } month)
        {
            return null;
        }

        var ids = CostBudget.ReachedThresholds(month.Value, budget)
            .Select(threshold => CostBudget.AlertId(provider, threshold, now, timeZone))
            .ToList();
        if (ids.Count == 0 || sent.Contains(ids[^1]))
        {
            return null;
        }

        sent.UnionWith(ids);
        var percent = CostBudget.Percent(month.Value, budget) ?? 0;
        return new UsageAlertCandidate(
            ids[^1],
            localizer.Text(L10nKey.CostBudgetAlertTitle),
            localizer.Text(L10nKey.CostBudgetAlertBody)
                .Replace("{organization}", AdminKeyText.Organization(provider), StringComparison.Ordinal)
                .Replace("{amount}", CostFormatter.Text(month), StringComparison.Ordinal)
                .Replace("{budget}", CostFormatter.Compact(new CostAmount(budget)), StringComparison.Ordinal)
                .Replace("{percent}", percent.ToString(CultureInfo.InvariantCulture), StringComparison.Ordinal));
    }

    /// Claude's own word for how close extra usage is to its limit, once it is no
    /// longer <c>normal</c>. The word goes in the id, so a step further up is news too.
    private static UsageAlertCandidate? ExtraUsageAlert(
        ProviderUsage usage,
        string month,
        HashSet<string> sent,
        Localizer localizer)
    {
        if (usage.ExtraUsage?.Severity?.ToLowerInvariant() is not { } severity || severity == "normal")
        {
            return null;
        }

        var level = new string(severity.Where(character => char.IsLetter(character) || character == '_').ToArray());
        var id = "claude-extra-" + level + "-" + month;
        if (level.Length == 0 || sent.Contains(id) || SubscriptionCostText.Line(usage, localizer) is not { } line)
        {
            return null;
        }

        sent.Add(id);
        return new UsageAlertCandidate(
            id,
            localizer.Text(L10nKey.ExtraUsageAlertTitle),
            localizer.Text(L10nKey.ExtraUsageAlertBody).Replace("{value}", line.Value, StringComparison.Ordinal));
    }

    private static UsageAlertCandidate? CreditLimitAlert(
        ProviderUsage usage,
        string month,
        HashSet<string> sent,
        Localizer localizer)
    {
        var id = "codex-credits-limit-" + month;
        if (usage.CreditLimitReached != true || sent.Contains(id))
        {
            return null;
        }

        sent.Add(id);
        return new UsageAlertCandidate(
            id,
            localizer.Text(L10nKey.CreditLimitAlertTitle),
            localizer.Text(L10nKey.CreditLimitAlertBody));
    }
}
