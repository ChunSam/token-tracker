namespace TokenTracker.Windows.Core;

/// How a window's spending compares with spreading it evenly up to the reset.
///
/// Half the window gone with 70% of it used is spending faster than the even
/// line. That takes one measurement and the reset time to say, where
/// <see cref="UsageForecaster"/> needs a run of stored history before it can
/// project anything. Mirrors <c>Sources/TokenTrackerCore/UsagePace.swift</c>.
public enum UsagePace
{
    /// Spending faster than the even line: at this rate the window runs out early.
    Ahead,
    OnTrack,

    /// Spending slower than the even line: there is room to spare before the reset.
    Behind
}

/// <param name="ExpectedRemainingPercent">
/// Where the remaining bar would stand had the window been used evenly up to the
/// measurement.
/// </param>
public sealed record UsagePaceReading(UsagePace Pace, int ExpectedRemainingPercent);

public static class UsagePaceEvaluator
{
    /// Percentage points either side of the even line that still count as on
    /// track, so a few points of drift do not flip the label from poll to poll.
    public const int Tolerance = 10;

    /// Pace for one of a provider's windows, judged at the moment it was measured.
    ///
    /// A cached reading gets none: its percentage belongs to a moment the window
    /// has since moved on from, the same reason it gets no countdown.
    public static UsagePaceReading? Reading(ProviderUsage usage, ForecastWindow window)
    {
        if (usage.Source != UsageSource.Api && usage.Source != UsageSource.StatusLine)
        {
            return null;
        }

        return window == ForecastWindow.FiveHour
            ? Reading(usage.RemainingPercent5h, usage.ResetAt5h, window, usage.UpdatedAt)
            : Reading(usage.RemainingPercent7d, usage.ResetAt7d, window, usage.UpdatedAt);
    }

    public static UsagePaceReading? Reading(
        int? remainingPercent,
        DateTimeOffset? resetAt,
        ForecastWindow window,
        DateTimeOffset measuredAt)
    {
        if (remainingPercent is not { } remaining || resetAt is not { } reset)
        {
            return null;
        }

        var timeLeft = reset - measuredAt;
        // Past its reset, or further off than the window is long: there is no
        // point in this window to compare against.
        if (timeLeft <= TimeSpan.Zero || timeLeft > window.Duration())
        {
            return null;
        }

        var expected = 100.0 * timeLeft.TotalSeconds / window.Duration().TotalSeconds;
        var gap = remaining - expected;
        var pace = UsagePace.OnTrack;
        if (gap < -Tolerance)
        {
            pace = UsagePace.Ahead;
        }
        else if (gap > Tolerance)
        {
            pace = UsagePace.Behind;
        }

        return new UsagePaceReading(pace, PercentMath.ClampPercent(expected));
    }
}

public static class UsagePaceText
{
    public static string Label(UsagePace pace, Localizer localizer) => pace switch
    {
        UsagePace.Ahead => localizer.Text(L10nKey.PaceAhead),
        UsagePace.Behind => localizer.Text(L10nKey.PaceBehind),
        _ => localizer.Text(L10nKey.PaceOnTrack)
    };

    /// `Pace: 5h ahead · 7d on track`, or null when neither window has a pace.
    public static string? MenuLine(ProviderUsage usage, Localizer localizer)
    {
        var parts = new List<string>();
        foreach (var window in new[] { ForecastWindow.FiveHour, ForecastWindow.SevenDay })
        {
            var reading = UsagePaceEvaluator.Reading(usage, window);
            if (reading is not null)
            {
                parts.Add(window.ShortLabel() + " " + Label(reading.Pace, localizer));
            }
        }

        if (parts.Count == 0)
        {
            return null;
        }

        return localizer.Text(L10nKey.Pace) + ": " + string.Join(" · ", parts);
    }
}
