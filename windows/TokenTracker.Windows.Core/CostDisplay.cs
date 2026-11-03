using System.Globalization;

namespace TokenTracker.Windows.Core;

// What the Admin API cost puts on screen: the submenu, the tooltip, the tray icon.
// Every surface goes through AdminCostText.View, which is null unless the
// provider's API cost is switched on and has a key, so a user who never set this
// up sees nothing of it. Mirrors Sources/TokenTrackerCore/CostDisplay.swift.

public enum AdminCostStatus
{
    Ok,

    /// Switched on with a key, waiting for the first answer.
    Loading,

    /// An earlier reading, standing in for a fetch that failed.
    Cached,
    KeyRejected,
    RateLimited,
    Failed
}

/// One provider's API cost, worded for a submenu.
/// <param name="MonthValue"><c>$42.18</c>, or <c>not tallied yet</c> while the month has nothing in it yet.</param>
/// <param name="BudgetPercent">Whole percent of the monthly budget spent. Null without a budget.</param>
/// <param name="BudgetText"><c>42% of $100 budget</c>.</param>
/// <param name="Detail"><c>Today $3.07 · Opus 5.5 71% · Sonnet 5.5 27%</c>.</param>
/// <param name="AsOf"><c>as of 14:20</c>: how far Anthropic's data reaches. Null for OpenAI.</param>
/// <param name="FailureMessage">What went wrong, in English, for a tooltip.</param>
public sealed record AdminCostView(
    AdminCostStatus Status,
    string StatusTitle,
    string MonthLabel,
    string MonthValue,
    int? BudgetPercent,
    string? BudgetText,
    string? Detail,
    string? AsOf,
    string? FailureMessage)
{
    /// The budget alert thresholds colour the amount: orange from 80%, red at 100%.
    public bool IsBudgetWarning => (BudgetPercent ?? 0) >= CostBudget.Thresholds[0];
}

public static class AdminCostText
{
    private static readonly string[] MonthNames =
        { "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec" };

    /// Null unless the provider's API cost is switched on and has a key.
    public static AdminCostView? View(CostState state, int budget, DateTimeOffset now, TimeZoneInfo timeZone, Localizer localizer)
    {
        if (!CostVisibility.Shows(subscriptionExtra: false, apiCostEnabled: state.Enabled, hasAdminKey: state.KeySuffix is not null))
        {
            return null;
        }

        var cost = state.Cost;
        var status = Status(state);

        var monthValue = "--";
        if (cost is not null)
        {
            monthValue = cost.MonthToDate is { } monthToDate
                ? CostFormatter.Text(monthToDate)
                : localizer.Text(L10nKey.CostNotYetTallied);
        }

        int? budgetPercent = null;
        string? budgetText = null;
        if (budget > 0 && cost?.MonthToDate is { } spent)
        {
            var percent = CostBudget.Percent(spent.Value, budget) ?? 0;
            budgetPercent = percent;
            budgetText = localizer.Text(L10nKey.CostBudget)
                .Replace("{limit}", CostFormatter.Compact(new CostAmount(budget)), StringComparison.Ordinal)
                .Replace("{percent}", percent.ToString(CultureInfo.InvariantCulture), StringComparison.Ordinal);
        }

        var parts = new List<string>();
        if (cost?.MonthToDate is { } month)
        {
            var today = cost.Today is { } todays ? CostFormatter.Text(todays) : localizer.Text(L10nKey.CostNotYetTallied);
            parts.Add(localizer.Text(L10nKey.CostToday) + " " + today);
            if (month.Value > 0)
            {
                foreach (var item in cost.TopItems.Take(2))
                {
                    var share = CostBudget.Percent(item.Amount.Value, month.Value) ?? 0;
                    parts.Add(CostItemName.Display(item.Name) + " " + share.ToString(CultureInfo.InvariantCulture) + "%");
                }
            }
        }

        string? asOf = null;
        if (cost?.DataRefreshedAt is { } refreshed)
        {
            asOf = localizer.Text(L10nKey.CostAsOf)
                .Replace("{time}", TimeText(refreshed, now, timeZone, localizer), StringComparison.Ordinal);
        }

        return new AdminCostView(
            status,
            Title(status, localizer),
            localizer.Text(L10nKey.CostThisMonth),
            monthValue,
            budgetPercent,
            budgetText,
            parts.Count == 0 ? null : string.Join(" · ", parts),
            asOf,
            state.Failure?.Message);
    }

    /// A rejected key outranks a cached reading: it will not mend itself, and the
    /// reading behind it only gets older.
    internal static AdminCostStatus Status(CostState state)
    {
        if (state.Failure?.Kind == CostFetchFailureKind.KeyRejected)
        {
            return AdminCostStatus.KeyRejected;
        }

        if (state.IsCached)
        {
            return AdminCostStatus.Cached;
        }

        return state.Failure?.Kind switch
        {
            CostFetchFailureKind.RateLimited => AdminCostStatus.RateLimited,
            CostFetchFailureKind.Failed => AdminCostStatus.Failed,
            _ => state.Cost is null ? AdminCostStatus.Loading : AdminCostStatus.Ok
        };
    }

    private static string Title(AdminCostStatus status, Localizer localizer) => status switch
    {
        AdminCostStatus.Ok => localizer.Text(L10nKey.StatusOk),
        AdminCostStatus.Loading => localizer.Text(L10nKey.CostLoading),
        AdminCostStatus.Cached => localizer.Text(L10nKey.StatusUsingCachedData),
        AdminCostStatus.KeyRejected => localizer.Text(L10nKey.CostAdminKeyRejected),
        AdminCostStatus.RateLimited => localizer.Text(L10nKey.StatusRateLimited),
        _ => localizer.Text(L10nKey.CostFetchFailed)
    };

    /// <c>14:20</c> today in the device's zone, <c>Nov 2 22:10</c> or <c>11월 2일 22:10</c>
    /// on another day. Twenty-four-hour on both ports, so the two read the same.
    internal static string TimeText(DateTimeOffset date, DateTimeOffset now, TimeZoneInfo timeZone, Localizer localizer)
    {
        var local = TimeZoneInfo.ConvertTime(date, timeZone);
        var localNow = TimeZoneInfo.ConvertTime(now, timeZone);
        var time = local.ToString("HH:mm", CultureInfo.InvariantCulture);
        if (local.Date == localNow.Date)
        {
            return time;
        }

        var day = local.Day.ToString(CultureInfo.InvariantCulture);
        if (localizer.Language == AppLanguage.Korean)
        {
            return local.Month.ToString(CultureInfo.InvariantCulture) + "월 " + day + "일 " + time;
        }

        return MonthNames[local.Month - 1] + " " + day + " " + time;
    }
}

public static class CostItemName
{
    /// <c>claude-opus-5-5</c> is <c>Opus 5.5</c>, <c>claude-sonnet-4-5-20250929</c> is
    /// <c>Sonnet 4.5</c>. Anything else stays as the provider named it.
    public static string Display(string name)
    {
        const string prefix = "claude-";
        if (!name.StartsWith(prefix, StringComparison.Ordinal))
        {
            return name;
        }

        var parts = name[prefix.Length..].Split('-', StringSplitOptions.RemoveEmptyEntries);
        var family = parts.FirstOrDefault(part => char.IsLetter(part[0]));
        if (family is null)
        {
            return name;
        }

        // A date stamp is eight digits; a version is one or two.
        var version = parts.Where(part => part.Length < 8 && part.All(char.IsDigit)).ToList();
        var title = char.ToUpperInvariant(family[0]) + family[1..];
        return version.Count == 0 ? title : title + " " + string.Join(".", version);
    }

    /// OpenAI splits a model into line items such as <c>gpt-6, input</c> and
    /// <c>gpt-6, output</c>; they add up under the model.
    public static string LineItemGroup(string name)
    {
        var comma = name.IndexOf(", ", StringComparison.Ordinal);
        return comma < 0 ? name : name[..comma];
    }
}

/// The money a provider tracked by API cost alone puts in the tray tooltip.
/// <param name="Text"><c>$42</c>, <c>$3.07</c>, <c>$1.2K</c>, or <c>--</c> before the first reading.</param>
/// <param name="IsWarning">From 80% of the monthly budget.</param>
public sealed record MenuBarCost(string Text, bool IsWarning);

public static class CostMenuBar
{
    private static readonly Provider[] Providers = { Provider.Claude, Provider.Codex };

    /// One entry per provider whose subscription limits are off and whose API cost
    /// is on with a key. A provider showing its limits keeps its percentage.
    public static IReadOnlyDictionary<Provider, MenuBarCost> Entries(
        IReadOnlyDictionary<Provider, bool> subscriptionShown,
        IReadOnlyDictionary<Provider, CostState> states,
        IReadOnlyDictionary<Provider, int> budgets)
    {
        var entries = new Dictionary<Provider, MenuBarCost>();
        foreach (var provider in Providers)
        {
            var state = states.TryGetValue(provider, out var found) ? found : new CostState();
            var apiCostShown = CostVisibility.Shows(subscriptionExtra: false, apiCostEnabled: state.Enabled, hasAdminKey: state.KeySuffix is not null);
            var limitsShown = !subscriptionShown.TryGetValue(provider, out var shown) || shown;
            if (!CostVisibility.MenuBarShowsCost(limitsShown, apiCostShown))
            {
                continue;
            }

            var month = state.Cost?.MonthToDate;
            var budget = budgets.TryGetValue(provider, out var value) ? value : 0;
            var percent = month is null ? 0 : CostBudget.Percent(month.Value, budget) ?? 0;
            entries[provider] = new MenuBarCost(
                month is null ? "--" : CostFormatter.Compact(month),
                percent >= CostBudget.Thresholds[0]);
        }

        return entries;
    }

    /// The tray icon draws a percentage. With every subscription limit off and only
    /// money left to show, it draws <c>$</c> instead.
    public static bool TrayShowsDollar(
        IReadOnlyDictionary<Provider, bool> subscriptionShown,
        IReadOnlyDictionary<Provider, MenuBarCost> entries) =>
        entries.Count > 0 &&
        !Providers.Any(provider => !subscriptionShown.TryGetValue(provider, out var shown) || shown);
}
