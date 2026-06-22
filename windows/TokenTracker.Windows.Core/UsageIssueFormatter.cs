namespace TokenTracker.Windows.Core;

public enum UsageIssueKind
{
    Ok,
    Disabled,
    RateLimited,
    MissingCredentials,
    InvalidResponse,
    TimedOut,
    Network,
    HttpStatus,
    UsingCachedData,
    Unavailable
}

public sealed record UsageIssue(
    UsageIssueKind Kind,
    string Title,
    string Detail,
    string? Recovery,
    string? TechnicalDetail);

public static class UsageIssueFormatter
{
    public static UsageIssue Issue(ProviderUsage usage, Localizer? localizer = null)
    {
        localizer ??= new Localizer(AppLanguage.English);
        if (usage.Source == UsageSource.StaleCache)
        {
            var technicalDetail = usage.Error;
            return new UsageIssue(
                UsageIssueKind.UsingCachedData,
                localizer.Text(L10nKey.StatusUsingCachedData),
                localizer.Text(L10nKey.StatusUsingCachedDataDetail),
                Recovery(technicalDetail, localizer) ?? localizer.Text(L10nKey.RecoveryTryAgainLater),
                technicalDetail);
        }

        if (string.IsNullOrWhiteSpace(usage.Error))
        {
            return usage.IsAvailable
                ? new UsageIssue(
                    UsageIssueKind.Ok,
                    localizer.Text(L10nKey.StatusOk),
                    localizer.Text(L10nKey.StatusOkDetail),
                    null,
                    null)
                : new UsageIssue(
                    UsageIssueKind.Unavailable,
                    localizer.Text(L10nKey.StatusUnavailable),
                    localizer.Text(L10nKey.StatusUnavailableDetail),
                    localizer.Text(L10nKey.RecoveryRefreshLater),
                    null);
        }

        var kind = Kind(usage.Error);
        return new UsageIssue(
            kind,
            Title(kind, localizer),
            Detail(kind, localizer),
            Recovery(usage.Error, localizer),
            usage.Error);
    }

    public static UsageIssueKind Kind(string error)
    {
        var normalized = error.Trim();
        var lower = normalized.ToLowerInvariant();
        if (lower == "disabled")
        {
            return UsageIssueKind.Disabled;
        }

        if (lower.Contains("http 429", StringComparison.Ordinal) ||
            lower.Contains("too many requests", StringComparison.Ordinal))
        {
            return UsageIssueKind.RateLimited;
        }

        if (lower.Contains("missing credentials", StringComparison.Ordinal))
        {
            return UsageIssueKind.MissingCredentials;
        }

        if (lower.Contains("invalid response", StringComparison.Ordinal))
        {
            return UsageIssueKind.InvalidResponse;
        }

        if (lower.Contains("timed out", StringComparison.Ordinal))
        {
            return UsageIssueKind.TimedOut;
        }

        if (lower.Contains("network error", StringComparison.Ordinal))
        {
            return UsageIssueKind.Network;
        }

        if (lower.StartsWith("http ", StringComparison.Ordinal))
        {
            return UsageIssueKind.HttpStatus;
        }

        return UsageIssueKind.Unavailable;
    }

    private static string Title(UsageIssueKind kind, Localizer localizer) => kind switch
    {
        UsageIssueKind.Ok => localizer.Text(L10nKey.StatusOk),
        UsageIssueKind.Disabled => localizer.Text(L10nKey.StatusDisabledProvider),
        UsageIssueKind.RateLimited => localizer.Text(L10nKey.StatusRateLimited),
        UsageIssueKind.MissingCredentials => localizer.Text(L10nKey.StatusMissingCredentials),
        UsageIssueKind.InvalidResponse => localizer.Text(L10nKey.StatusInvalidResponse),
        UsageIssueKind.TimedOut => localizer.Text(L10nKey.StatusTimedOut),
        UsageIssueKind.Network => localizer.Text(L10nKey.StatusNetworkIssue),
        UsageIssueKind.HttpStatus => localizer.Text(L10nKey.StatusHttpError),
        UsageIssueKind.UsingCachedData => localizer.Text(L10nKey.StatusUsingCachedData),
        UsageIssueKind.Unavailable => localizer.Text(L10nKey.StatusUnavailable),
        _ => localizer.Text(L10nKey.StatusUnavailable)
    };

    private static string Detail(UsageIssueKind kind, Localizer localizer) => kind switch
    {
        UsageIssueKind.Ok => localizer.Text(L10nKey.StatusOkDetail),
        UsageIssueKind.Disabled => localizer.Text(L10nKey.StatusDisabledProviderDetail),
        UsageIssueKind.RateLimited => localizer.Text(L10nKey.StatusRateLimitedDetail),
        UsageIssueKind.MissingCredentials => localizer.Text(L10nKey.StatusMissingCredentialsDetail),
        UsageIssueKind.InvalidResponse => localizer.Text(L10nKey.StatusInvalidResponseDetail),
        UsageIssueKind.TimedOut => localizer.Text(L10nKey.StatusTimedOutDetail),
        UsageIssueKind.Network => localizer.Text(L10nKey.StatusNetworkIssueDetail),
        UsageIssueKind.HttpStatus => localizer.Text(L10nKey.StatusHttpErrorDetail),
        UsageIssueKind.UsingCachedData => localizer.Text(L10nKey.StatusUsingCachedDataDetail),
        UsageIssueKind.Unavailable => localizer.Text(L10nKey.StatusUnavailableDetail),
        _ => localizer.Text(L10nKey.StatusUnavailableDetail)
    };

    private static string? Recovery(string? error, Localizer localizer)
    {
        if (string.IsNullOrWhiteSpace(error))
        {
            return null;
        }

        return Kind(error) switch
        {
            UsageIssueKind.Disabled => localizer.Text(L10nKey.RecoveryEnableProvider),
            UsageIssueKind.RateLimited => localizer.Text(L10nKey.RecoveryWaitForCooldown),
            UsageIssueKind.MissingCredentials => localizer.Text(L10nKey.RecoveryCheckCredentials),
            UsageIssueKind.InvalidResponse => localizer.Text(L10nKey.RecoveryUpdateOrTryLater),
            UsageIssueKind.TimedOut or UsageIssueKind.Network => localizer.Text(L10nKey.RecoveryCheckNetwork),
            UsageIssueKind.HttpStatus or UsageIssueKind.Unavailable => localizer.Text(L10nKey.RecoveryRefreshLater),
            UsageIssueKind.Ok or UsageIssueKind.UsingCachedData => null,
            _ => null
        };
    }
}
