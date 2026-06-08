using System.Text.Json;
using System.Text.Json.Serialization;

namespace TokenTracker.Windows.Core;

public sealed class CacheStore
{
    private static readonly JsonSerializerOptions Options = new()
    {
        WriteIndented = true,
        Converters = { new JsonStringEnumConverter() }
    };

    public string Path { get; }

    public CacheStore(string? path = null)
    {
        Path = path ?? AppPaths.SnapshotCachePath;
    }

    public UsageSnapshot? Load(TimeSpan maxAge)
    {
        try
        {
            if (!File.Exists(Path))
            {
                return null;
            }

            var snapshot = JsonSerializer.Deserialize<UsageSnapshot>(File.ReadAllText(Path), Options);
            if (snapshot is null || DateTimeOffset.Now - snapshot.UpdatedAt > maxAge)
            {
                return null;
            }

            return snapshot;
        }
        catch
        {
            return null;
        }
    }

    public void Save(UsageSnapshot snapshot)
    {
        try
        {
            var directory = System.IO.Path.GetDirectoryName(Path);
            if (!string.IsNullOrWhiteSpace(directory))
            {
                Directory.CreateDirectory(directory);
            }

            var tempPath = Path + ".tmp";
            File.WriteAllText(tempPath, JsonSerializer.Serialize(snapshot, Options));
            File.Move(tempPath, Path, overwrite: true);
        }
        catch
        {
        }
    }
}

public static class UsageSnapshotCachePolicy
{
    public static UsageSnapshot Apply(
        UsageSnapshot current,
        UsageSnapshot? stale,
        bool claudeEnabled = true,
        bool codexEnabled = true,
        DateTimeOffset? updatedAt = null)
    {
        if (stale is null)
        {
            return current;
        }

        var now = updatedAt ?? DateTimeOffset.Now;
        var claude = current.Claude;
        var codex = current.Codex;

        if (claudeEnabled && !claude.IsAvailable && stale.Claude.IsAvailable)
        {
            claude = MarkStale(stale.Claude, claude.Error, now);
        }

        if (codexEnabled && !codex.IsAvailable && stale.Codex.IsAvailable)
        {
            codex = MarkStale(stale.Codex, codex.Error, now);
        }

        return new UsageSnapshot(claude, codex, current.UpdatedAt);
    }

    private static ProviderUsage MarkStale(ProviderUsage usage, string? error, DateTimeOffset updatedAt) =>
        usage with
        {
            Source = UsageSource.StaleCache,
            Error = error,
            UpdatedAt = updatedAt
        };
}
