using System.Text.Json;

namespace TokenTracker.Windows.Core;

/// <summary>
/// Both providers store a short-lived OAuth access token that only their own CLI
/// refreshes; Token Tracker just reads it. Sending an already-expired token to the
/// usage endpoint returns something opaque and, for Anthropic, actively harmful:
/// <c>/api/oauth/usage</c> answers 429 for repeated expired-token requests, which
/// the rate-limit backoff then treats as a real quota cooldown and keeps blocking
/// refreshes long after the user has signed in again. Checking the expiry locally
/// lets the app report "sign in again" instead of an unactionable HTTP code.
/// </summary>
public static class CredentialExpiry
{
    /// <summary>Treat a token as expired slightly early so one that lapses between
    /// the check and the response is still reported as expired, not as an HTTP error.</summary>
    public static readonly TimeSpan Skew = TimeSpan.FromSeconds(60);

    public static bool IsExpired(DateTimeOffset? expiresAt, DateTimeOffset? now = null)
    {
        if (expiresAt is not { } expiry)
        {
            return false;
        }

        return expiry - (now ?? DateTimeOffset.Now) <= Skew;
    }

    /// <summary>Reads the <c>exp</c> claim out of a JWT without verifying the
    /// signature. The provider remains the authority on whether a token is good;
    /// this only avoids spending a request on one already known to be stale.</summary>
    public static DateTimeOffset? JwtExpiry(string? token)
    {
        if (string.IsNullOrWhiteSpace(token))
        {
            return null;
        }

        var parts = token.Split('.');
        if (parts.Length < 2)
        {
            return null;
        }

        try
        {
            using var document = JsonDocument.Parse(Base64UrlDecode(parts[1]));
            if (!document.RootElement.TryGetProperty("exp", out var exp) || exp.ValueKind != JsonValueKind.Number)
            {
                return null;
            }

            // `exp` is conventionally an integer but is only required to be numeric.
            return exp.TryGetInt64(out var seconds)
                ? DateTimeOffset.FromUnixTimeSeconds(seconds)
                : DateTimeOffset.FromUnixTimeSeconds((long)exp.GetDouble());
        }
        catch
        {
            return null;
        }
    }

    /// <summary>Milliseconds-since-epoch is how Claude Code records <c>expiresAt</c>.</summary>
    public static DateTimeOffset? EpochMilliseconds(JsonElement element, string propertyName)
    {
        if (!element.TryGetProperty(propertyName, out var value) ||
            value.ValueKind != JsonValueKind.Number ||
            !value.TryGetInt64(out var milliseconds))
        {
            return null;
        }

        return DateTimeOffset.FromUnixTimeMilliseconds(milliseconds);
    }

    private static byte[] Base64UrlDecode(string value)
    {
        var text = value.Replace('-', '+').Replace('_', '/');
        return Convert.FromBase64String(text.PadRight(text.Length + (4 - text.Length % 4) % 4, '='));
    }
}

/// <summary>
/// Stable, non-reversible fingerprint of the credentials a cooldown was recorded
/// against, so "the user signed in again" can be told apart from "same token, keep
/// waiting". Not a security boundary — it only has to change when the token does.
/// </summary>
public static class TokenFingerprint
{
    public static string Of(params string[] tokens)
    {
        var ordered = tokens.OrderBy(token => token, StringComparer.Ordinal);
        var hash = 0xcbf29ce484222325UL;
        foreach (var b in System.Text.Encoding.UTF8.GetBytes(string.Join('\0', ordered)))
        {
            hash ^= b;
            hash *= 0x100000001b3UL;
        }

        return hash.ToString("x");
    }
}
