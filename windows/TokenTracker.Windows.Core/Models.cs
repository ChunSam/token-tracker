namespace TokenTracker.Windows.Core;

public enum Provider
{
    Claude,
    Codex
}

public enum UsageSource
{
    Api,
    StaleCache,
    Unavailable
}

public enum DisplayMode
{
    LowestRemaining,
    Both,
    CodexOnly,
    ClaudeOnly
}

public enum ProviderLabelStyle
{
    Abbreviation,
    Icon
}

public enum AppLanguage
{
    System,
    English,
    Korean
}

public sealed record ProviderUsage(
    Provider Provider,
    int? RemainingPercent5h,
    int? RemainingPercent7d,
    DateTimeOffset? ResetAt5h,
    DateTimeOffset? ResetAt7d,
    UsageSource Source,
    string? Error,
    string? Plan,
    string? Model,
    DateTimeOffset UpdatedAt)
{
    public bool IsAvailable => RemainingPercent5h is not null || RemainingPercent7d is not null;

    public string DisplayName => Provider == Provider.Claude ? "Claude" : "Codex";

    public static ProviderUsage Unavailable(Provider provider, string error) =>
        new(provider, null, null, null, null, UsageSource.Unavailable, error, null, null, DateTimeOffset.Now);
}

public sealed record UsageSnapshot(
    ProviderUsage Claude,
    ProviderUsage Codex,
    DateTimeOffset UpdatedAt);
