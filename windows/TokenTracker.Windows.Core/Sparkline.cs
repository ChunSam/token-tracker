using System.Text;

namespace TokenTracker.Windows.Core;

/// Reduces stored history into a compact remaining-% series for one
/// provider/window, downsampled to a menu-friendly width. Pure — no network.
/// Mirrors the Swift <c>SparklineSeries</c>.
public static class SparklineSeries
{
    public static IReadOnlyList<int> Build(
        IReadOnlyList<UsageHistoryEntry> entries,
        Provider provider,
        ForecastWindow window,
        int maxPoints = 20)
    {
        var values = entries
            .OrderBy(entry => entry.RecordedAt)
            .Select(entry => Remaining(entry.Snapshot.Usage(provider), window))
            .Where(value => value is not null)
            .Select(value => value!.Value)
            .ToList();

        if (maxPoints <= 0 || values.Count <= maxPoints)
        {
            return values;
        }

        var result = new List<int>(maxPoints);
        for (var bucket = 0; bucket < maxPoints; bucket++)
        {
            var start = bucket * values.Count / maxPoints;
            var end = Math.Max(start + 1, (bucket + 1) * values.Count / maxPoints);
            result.Add((int)values.GetRange(start, end - start).Average());
        }

        return result;
    }

    private static int? Remaining(ProviderUsage usage, ForecastWindow window) =>
        window == ForecastWindow.FiveHour ? usage.RemainingPercent5h : usage.RemainingPercent7d;
}

/// Renders a 0–100 series as a Unicode block sparkline (absolute scale, so the
/// level and slope are both visible). Shared across platforms — no drawing code.
public static class SparklineText
{
    private static readonly string[] Blocks = { "▁", "▂", "▃", "▄", "▅", "▆", "▇", "█" };

    public static string Render(IReadOnlyList<int> series)
    {
        if (series.Count < 2)
        {
            return string.Empty;
        }

        var builder = new StringBuilder(series.Count);
        foreach (var value in series)
        {
            var clamped = Math.Clamp(value, 0, 100);
            var index = Math.Min(Blocks.Length - 1, clamped * Blocks.Length / 100);
            builder.Append(Blocks[index]);
        }

        return builder.ToString();
    }
}
