namespace TokenTracker.Windows.Core;

public sealed record CodexRateWindow(
    double? UsedPercent,
    DateTimeOffset? ResetAt,
    double? WindowSeconds);

public sealed record CodexMappedWindows(
    CodexRateWindow? FiveHour,
    CodexRateWindow? SevenDay);

/// Assigns the Codex API's rate-limit windows to the 5h/7d display lanes by
/// their advertised length instead of their position: since 2026-07 the API can
/// report the weekly window as <c>primary_window</c> (the 5h window was
/// removed), so positional mapping would show weekly usage in the 5h lane.
/// Mirrors the Swift <c>CodexWindowMapper</c> in
/// <c>Sources/TokenTrackerCore/CodexWindowMapper.swift</c>.
public static class CodexWindowMapper
{
    /// Windows shorter than a day belong to the short-term (5h) lane; a day or
    /// longer is the weekly lane.
    private const double LaneBoundarySeconds = 24 * 60 * 60;

    public static CodexMappedWindows Map(CodexRateWindow? primary, CodexRateWindow? secondary)
    {
        CodexRateWindow? fiveHour = null;
        CodexRateWindow? sevenDay = null;
        Assign(primary, positionalIsFiveHour: true, ref fiveHour, ref sevenDay);
        Assign(secondary, positionalIsFiveHour: false, ref fiveHour, ref sevenDay);
        return new CodexMappedWindows(fiveHour, sevenDay);
    }

    private static void Assign(
        CodexRateWindow? window,
        bool positionalIsFiveHour,
        ref CodexRateWindow? fiveHour,
        ref CodexRateWindow? sevenDay)
    {
        if (window is null)
        {
            return;
        }

        var isFiveHour = window.WindowSeconds is double seconds
            ? seconds < LaneBoundarySeconds
            : positionalIsFiveHour;
        if (isFiveHour)
        {
            fiveHour ??= window;
        }
        else
        {
            sevenDay ??= window;
        }
    }
}
