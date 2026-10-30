using System.Globalization;
using System.Text.Json;

namespace TokenTracker.Windows.Core;

/// <summary>
/// A Claude usage reading that came from Claude Code's own status line, relayed
/// through a local file by <c>scripts/claude-statusline-bridge.ps1</c>.
///
/// Token Tracker only <em>reads</em> the access token Claude Code stores; nothing
/// here refreshes it. Once that token lapses — which it does whenever the CLI has
/// not been run for a few hours — the API path has nothing usable to send and
/// Claude collection stops entirely until the user runs <c>/login</c> again. The
/// status line is the one documented input that reports the same two subscription
/// windows without this app touching a credential at all.
///
/// The hazard the format is built around: the status-line command re-runs on the
/// CLI's own schedule, so <em>being written again</em> is not evidence that the
/// account was measured again. The bridge therefore records two separate instants
/// — <c>measured_at</c>, which only moves when a window's numbers actually
/// change, and <c>written_at</c>, which moves on every run — and everything here
/// ages a reading by <c>measured_at</c>. A replayed payload keeps its original
/// age and expires on time.
/// </summary>
/// <param name="MeasuredAt">When the reported numbers last changed.</param>
/// <param name="WrittenAt">When the bridge last ran. Diagnostics only, never freshness.</param>
public sealed record ClaudeStatusLineRecord(
    DateTimeOffset MeasuredAt,
    DateTimeOffset WrittenAt,
    double? UsedPercent5h,
    DateTimeOffset? ResetAt5h,
    double? UsedPercent7d,
    DateTimeOffset? ResetAt7d)
{
    public TimeSpan Age(DateTimeOffset now) => now - MeasuredAt;
}

public static class ClaudeStatusLineBridge
{
    /// Bumped only for a breaking change to the file the bridge writes; a record
    /// carrying anything else is ignored rather than guessed at.
    public const int Version = 1;

    /// <summary>
    /// How long a status-line measurement may stand in as a <em>current</em>
    /// reading. Past it the reading is handed to the ordinary stale-cache path,
    /// which labels it as cached instead of presenting it as the account's
    /// current state.
    /// </summary>
    public static readonly TimeSpan FreshnessWindow = TimeSpan.FromMinutes(30);

    /// The bridge and the app can disagree slightly about the time. Allow that
    /// much before calling a timestamp impossible.
    public static readonly TimeSpan ClockSkew = TimeSpan.FromMinutes(5);

    /// <summary>
    /// Parse the bridge file. Returns null for anything unusable — a missing or
    /// unknown version, no readable window, or a measurement stamped in the
    /// future, which cannot be aged honestly.
    /// </summary>
    public static ClaudeStatusLineRecord? Parse(string json, DateTimeOffset? now = null)
    {
        var at = now ?? DateTimeOffset.Now;
        try
        {
            using var document = JsonDocument.Parse(json);
            var root = document.RootElement;
            if (root.ValueKind != JsonValueKind.Object)
            {
                return null;
            }

            var version = Number(root, "version");
            if (version is null || (int)version.Value != Version)
            {
                return null;
            }

            var measuredSeconds = Number(root, "measured_at");
            if (measuredSeconds is null)
            {
                return null;
            }

            var measuredAt = FromUnixSeconds(measuredSeconds.Value);
            if (measuredAt - at > ClockSkew)
            {
                return null;
            }

            var writtenSeconds = Number(root, "written_at");
            var writtenAt = writtenSeconds is null ? measuredAt : FromUnixSeconds(writtenSeconds.Value);

            root.TryGetProperty("rate_limits", out var limits);
            var fiveHour = Window(limits, "five_hour", at);
            var sevenDay = Window(limits, "seven_day", at);
            if (fiveHour is null && sevenDay is null)
            {
                return null;
            }

            return new ClaudeStatusLineRecord(
                measuredAt,
                writtenAt,
                fiveHour?.UsedPercent,
                fiveHour?.ResetAt,
                sevenDay?.UsedPercent,
                sevenDay?.ResetAt);
        }
        catch
        {
            return null;
        }
    }

    /// <summary>
    /// The reading to show, or null when there is nothing current to show. A
    /// stale record deliberately yields null rather than a reading: the caller's
    /// existing cache policy then carries the last good value with its own
    /// "using cached data" label, instead of this presenting an old measurement
    /// as the live one.
    ///
    /// <paramref name="apiError"/> is the reason the API path produced nothing,
    /// carried through so the menu can still say "sign in again" while showing
    /// these numbers.
    /// </summary>
    public static ProviderUsage? Usage(ClaudeStatusLineRecord? record, string? apiError, DateTimeOffset? now = null)
    {
        if (record is null)
        {
            return null;
        }

        var age = record.Age(now ?? DateTimeOffset.Now);
        if (age > FreshnessWindow || age < -ClockSkew)
        {
            return null;
        }

        return new ProviderUsage(
            Provider.Claude,
            PercentMath.RemainingPercent(record.UsedPercent5h),
            PercentMath.RemainingPercent(record.UsedPercent7d),
            record.ResetAt5h,
            record.ResetAt7d,
            UsageSource.StatusLine,
            apiError,
            null,
            null,
            // The measurement time, not now: a reading that is re-read on every
            // poll must keep aging, or the cache never expires.
            record.MeasuredAt);
    }

    private sealed record RateWindow(double UsedPercent, DateTimeOffset ResetAt);

    /// <summary>
    /// Claude Code drops a window once its <c>resets_at</c> has passed, so a
    /// window still in the file whose reset is behind us describes a window
    /// instance that no longer exists. Both fields are required: without
    /// <c>resets_at</c> there is no way to tell a live window from an expired one.
    /// </summary>
    private static RateWindow? Window(JsonElement limits, string name, DateTimeOffset now)
    {
        if (limits.ValueKind != JsonValueKind.Object
            || !limits.TryGetProperty(name, out var window)
            || window.ValueKind != JsonValueKind.Object)
        {
            return null;
        }

        var used = Number(window, "used_percentage");
        var resetSeconds = Number(window, "resets_at");
        if (used is null || resetSeconds is null)
        {
            return null;
        }

        var resetAt = FromUnixSeconds(resetSeconds.Value);
        if (resetAt <= now)
        {
            return null;
        }

        return new RateWindow(Math.Clamp(used.Value, 0, 100), resetAt);
    }

    private static DateTimeOffset FromUnixSeconds(double seconds) =>
        DateTimeOffset.FromUnixTimeMilliseconds((long)Math.Round(seconds * 1000));

    private static double? Number(JsonElement element, string name)
    {
        if (element.ValueKind != JsonValueKind.Object || !element.TryGetProperty(name, out var value))
        {
            return null;
        }

        double? parsed = value.ValueKind switch
        {
            JsonValueKind.Number when value.TryGetDouble(out var number) => number,
            JsonValueKind.String when double.TryParse(value.GetString(), NumberStyles.Float, CultureInfo.InvariantCulture, out var number) => number,
            _ => null
        };

        if (parsed is null || !double.IsFinite(parsed.Value))
        {
            return null;
        }

        return parsed;
    }
}

/// <summary>
/// Reads the bridge file. Separate from the parsing so the policy above stays a
/// pure function the smoke tests can drive without a filesystem.
/// </summary>
public sealed class ClaudeStatusLineStore
{
    public string Path { get; }

    public ClaudeStatusLineStore(string? path = null)
    {
        Path = path ?? AppPaths.ClaudeStatusLinePath;
    }

    public bool FileExists => File.Exists(Path);

    public ClaudeStatusLineRecord? Read(DateTimeOffset? now = null)
    {
        try
        {
            if (!File.Exists(Path))
            {
                return null;
            }

            return ClaudeStatusLineBridge.Parse(File.ReadAllText(Path), now);
        }
        catch
        {
            return null;
        }
    }
}
