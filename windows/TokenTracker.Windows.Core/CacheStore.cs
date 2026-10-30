using System.Text.Json;
using System.Text.Json.Serialization;

namespace TokenTracker.Windows.Core;

public sealed class CacheStore
{
    // Older caches overwrote measurement timestamps, so their age is unknowable.
    private sealed record Record(int Version, UsageSnapshot Snapshot);

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

            var record = JsonSerializer.Deserialize<Record>(File.ReadAllText(Path), Options);
            if (record is not { Version: 1, Snapshot: not null }
                || DateTimeOffset.Now - record.Snapshot.UpdatedAt > maxAge)
            {
                return null;
            }

            return record.Snapshot;
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
            File.WriteAllText(tempPath, JsonSerializer.Serialize(new Record(1, snapshot), Options));
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
        DateTimeOffset? updatedAt = null,
        TimeSpan? maxAge = null)
    {
        if (stale is null)
        {
            return current;
        }

        var now = updatedAt ?? DateTimeOffset.Now;
        var tolerance = maxAge ?? TimeSpan.FromHours(12);
        var claude = current.Claude;
        var codex = current.Codex;

        if (claudeEnabled && !claude.IsAvailable && CanReuse(stale.Claude, now, tolerance))
        {
            claude = MarkStale(stale.Claude, claude.Error);
        }

        if (codexEnabled && !codex.IsAvailable && CanReuse(stale.Codex, now, tolerance))
        {
            codex = MarkStale(stale.Codex, codex.Error);
        }

        return new UsageSnapshot(claude, codex, current.UpdatedAt);
    }

    private static bool CanReuse(ProviderUsage usage, DateTimeOffset now, TimeSpan maxAge)
    {
        var age = now - usage.UpdatedAt;
        return usage.IsAvailable && usage.Source != UsageSource.Unavailable
            && age >= TimeSpan.Zero && age <= maxAge;
    }

    private static ProviderUsage MarkStale(ProviderUsage usage, string? error) =>
        usage with
        {
            Source = UsageSource.StaleCache,
            Error = error
        };
}
