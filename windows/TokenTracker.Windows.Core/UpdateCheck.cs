using System.Globalization;
using System.Text.Json;

namespace TokenTracker.Windows.Core;

/// Whether a newer release is out. The app has no signed auto-update path and is
/// installed by hand from GitHub Releases, so the most it can do is say a new
/// version exists and link to the page that has it. Mirrors
/// <c>Sources/TokenTrackerCore/UpdateCheck.swift</c>.
public static class UpdateCheck
{
    public static readonly Uri LatestReleaseApi = new("https://api.github.com/repos/ChunSam/token-tracker/releases/latest");
    public static readonly Uri ReleasesPage = new("https://github.com/ChunSam/token-tracker/releases/latest");

    /// Once a day is plenty for releases cut by hand, and far inside GitHub's 60
    /// unauthenticated requests an hour.
    public static readonly TimeSpan Interval = TimeSpan.FromHours(24);

    /// After a failed check — offline at launch, say — try again within the hour
    /// rather than waiting out the day.
    public static readonly TimeSpan RetryInterval = TimeSpan.FromHours(1);

    /// The version a `releases/latest` response names, without its leading `v`.
    /// Drafts, prereleases and tags that are not plain dotted numbers are null, so
    /// a `-beta` tag never reads as newer than the build it would replace.
    public static string? LatestVersion(string json)
    {
        try
        {
            using var document = JsonDocument.Parse(json);
            var root = document.RootElement;
            if (root.ValueKind != JsonValueKind.Object || IsTrue(root, "draft") || IsTrue(root, "prerelease"))
            {
                return null;
            }

            if (!root.TryGetProperty("tag_name", out var tag) || tag.ValueKind != JsonValueKind.String)
            {
                return null;
            }

            var value = tag.GetString();
            if (value is null || Components(value) is null)
            {
                return null;
            }

            return Normalized(value);
        }
        catch (JsonException)
        {
            return null;
        }
    }

    /// Compared number by number, so 1.1.10 is newer than 1.1.9. A version either
    /// side cannot read is never newer: an unknown build should not nag.
    public static bool IsNewer(string candidate, string current)
    {
        var next = Components(candidate);
        var installed = Components(current);
        if (next is null || installed is null)
        {
            return false;
        }

        for (var index = 0; index < Math.Max(next.Count, installed.Count); index++)
        {
            var lhs = index < next.Count ? next[index] : 0;
            var rhs = index < installed.Count ? installed[index] : 0;
            if (lhs != rhs)
            {
                return lhs > rhs;
            }
        }

        return false;
    }

    public static DateTimeOffset NextCheck(DateTimeOffset attemptAt, bool succeeded) =>
        attemptAt + (succeeded ? Interval : RetryInterval);

    /// Null means no check has been tried yet, which is due at once.
    public static bool IsDue(DateTimeOffset? nextCheckAt, DateTimeOffset now) =>
        nextCheckAt is not { } next || now >= next;

    /// `1.1.16` for the running assembly's version, the form release tags use.
    public static string? CurrentVersion(Version? version)
    {
        if (version is null || version.Build < 0)
        {
            return null;
        }

        return string.Join(
            ".",
            version.Major.ToString(CultureInfo.InvariantCulture),
            version.Minor.ToString(CultureInfo.InvariantCulture),
            version.Build.ToString(CultureInfo.InvariantCulture));
    }

    /// The latest release's version, or null for any failure. A missed check is
    /// retried later and is never worth an error on screen.
    public static async Task<string?> FetchLatestVersionAsync(HttpClient client, CancellationToken cancellationToken = default)
    {
        try
        {
            using var request = new HttpRequestMessage(HttpMethod.Get, LatestReleaseApi);
            request.Headers.Accept.ParseAdd("application/vnd.github+json");
            request.Headers.UserAgent.ParseAdd("TokenTracker");
            using var response = await client.SendAsync(request, cancellationToken);
            if (!response.IsSuccessStatusCode)
            {
                return null;
            }

            return LatestVersion(await response.Content.ReadAsStringAsync(cancellationToken));
        }
        catch (Exception ex) when (ex is HttpRequestException or TaskCanceledException or InvalidOperationException)
        {
            return null;
        }
    }

    private static bool IsTrue(JsonElement root, string name) =>
        root.TryGetProperty(name, out var value) && value.ValueKind == JsonValueKind.True;

    private static string Normalized(string version)
    {
        var trimmed = version.Trim();
        return trimmed.StartsWith('v') || trimmed.StartsWith('V') ? trimmed[1..] : trimmed;
    }

    private static IReadOnlyList<int>? Components(string version)
    {
        var parts = Normalized(version).Split('.');
        if (parts.Length is < 1 or > 4)
        {
            return null;
        }

        var numbers = new List<int>();
        foreach (var part in parts)
        {
            if (part.Length == 0 ||
                !part.All(char.IsAsciiDigit) ||
                !int.TryParse(part, NumberStyles.None, CultureInfo.InvariantCulture, out var number))
            {
                return null;
            }

            numbers.Add(number);
        }

        return numbers;
    }
}
