using System.Globalization;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace TokenTracker.Windows.Core;

public sealed record UsageHistoryEntry(DateTimeOffset RecordedAt, UsageSnapshot Snapshot);

public sealed class UsageHistoryStore
{
    private static readonly JsonSerializerOptions Options = new()
    {
        WriteIndented = true,
        Converters = { new JsonStringEnumConverter() }
    };

    public string Path { get; }

    public UsageHistoryStore(string? path = null)
    {
        Path = path ?? AppPaths.UsageHistoryPath;
    }

    public IReadOnlyList<UsageHistoryEntry> Load()
    {
        try
        {
            if (!File.Exists(Path))
            {
                return Array.Empty<UsageHistoryEntry>();
            }

            var entries = JsonSerializer.Deserialize<List<UsageHistoryEntry>>(File.ReadAllText(Path), Options);
            return entries?
                .OrderBy(entry => entry.RecordedAt)
                .ToArray() ?? Array.Empty<UsageHistoryEntry>();
        }
        catch
        {
            return Array.Empty<UsageHistoryEntry>();
        }
    }

    public void Append(UsageSnapshot snapshot, int retentionDays, DateTimeOffset? now = null)
    {
        var current = now ?? DateTimeOffset.Now;
        var entries = Load().ToList();
        var newEntry = new UsageHistoryEntry(current, snapshot);

        if (entries.Count > 0 && current - entries[^1].RecordedAt < TimeSpan.FromMinutes(1))
        {
            entries[^1] = newEntry;
        }
        else
        {
            entries.Add(newEntry);
        }

        var cutoff = current.AddDays(-Math.Max(1, retentionDays));
        Save(entries.Where(entry => entry.RecordedAt >= cutoff).ToArray());
    }

    public string CsvString() => UsageHistoryFormatter.CsvString(Load());

    private void Save(IReadOnlyList<UsageHistoryEntry> entries)
    {
        try
        {
            var directory = System.IO.Path.GetDirectoryName(Path);
            if (!string.IsNullOrWhiteSpace(directory))
            {
                Directory.CreateDirectory(directory);
            }

            var tempPath = Path + ".tmp";
            File.WriteAllText(tempPath, JsonSerializer.Serialize(entries, Options));
            File.Move(tempPath, Path, overwrite: true);
        }
        catch
        {
        }
    }
}

public static class UsageHistoryFormatter
{
    public static string TrendSummary(
        IReadOnlyList<UsageHistoryEntry> entries,
        UsageSnapshot current,
        TimeSpan? window = null,
        Localizer? localizer = null)
    {
        localizer ??= new Localizer(AppLanguage.English);
        var cutoff = current.UpdatedAt - (window ?? TimeSpan.FromDays(1));
        var baseline = entries.FirstOrDefault(entry => entry.RecordedAt >= cutoff);
        if (baseline is null)
        {
            return localizer.Text(L10nKey.NotEnoughHistory);
        }

        return string.Join(
            " ",
            localizer.Text(L10nKey.HistoryTrend),
            ProviderTrend(Provider.Claude, baseline.Snapshot, current),
            ProviderTrend(Provider.Codex, baseline.Snapshot, current));
    }

    public static string CsvString(IReadOnlyList<UsageHistoryEntry> entries)
    {
        var header = string.Join(
            ",",
            "recorded_at",
            "provider",
            "remaining_5h",
            "remaining_7d",
            "reset_5h",
            "reset_7d",
            "source",
            "plan",
            "error");

        var rows = entries.SelectMany(entry => new[] { entry.Snapshot.Claude, entry.Snapshot.Codex }
            .Select(usage => string.Join(
                ",",
                new[]
                {
                    IsoString(entry.RecordedAt),
                    usage.Provider.ToId(),
                    OptionalInt(usage.RemainingPercent5h),
                    OptionalInt(usage.RemainingPercent7d),
                    OptionalDate(usage.ResetAt5h),
                    OptionalDate(usage.ResetAt7d),
                    usage.Source.ToString(),
                    usage.Plan ?? "",
                    usage.Error ?? ""
                }
                .Select(CsvEscape))));

        return string.Join(Environment.NewLine, new[] { header }.Concat(rows)) + Environment.NewLine;
    }

    private static string ProviderTrend(Provider provider, UsageSnapshot baseline, UsageSnapshot current)
    {
        var baselineUsage = baseline.Usage(provider);
        var currentUsage = current.Usage(provider);
        var fiveHour = DeltaText(baselineUsage.RemainingPercent5h, currentUsage.RemainingPercent5h);
        var sevenDay = DeltaText(baselineUsage.RemainingPercent7d, currentUsage.RemainingPercent7d);
        return $"{baselineUsage.DisplayName} 5h {fiveHour} 7d {sevenDay}";
    }

    private static string DeltaText(int? previous, int? latest)
    {
        if (previous is null || latest is null)
        {
            return "--";
        }

        var delta = latest.Value - previous.Value;
        return delta > 0 ? $"+{delta}%" : $"{delta}%";
    }

    private static string OptionalInt(int? value) =>
        value?.ToString(CultureInfo.InvariantCulture) ?? "";

    private static string OptionalDate(DateTimeOffset? date) =>
        date is null ? "" : IsoString(date.Value);

    private static string IsoString(DateTimeOffset date) =>
        date.ToUniversalTime().ToString("O", CultureInfo.InvariantCulture);

    private static string CsvEscape(string value)
    {
        if (value.Contains(',', StringComparison.Ordinal) ||
            value.Contains('"', StringComparison.Ordinal) ||
            value.Contains('\n', StringComparison.Ordinal))
        {
            return $"\"{value.Replace("\"", "\"\"", StringComparison.Ordinal)}\"";
        }

        return value;
    }

}
