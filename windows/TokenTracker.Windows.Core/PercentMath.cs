namespace TokenTracker.Windows.Core;

public static class PercentMath
{
    public static int ClampPercent(double value) =>
        Math.Min(100, Math.Max(0, (int)Math.Round(value, MidpointRounding.AwayFromZero)));

    public static int? RemainingPercent(double? usedPercent) =>
        usedPercent is null ? null : ClampPercent(100.0 - usedPercent.Value);
}
