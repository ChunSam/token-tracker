namespace TokenTracker.Windows.Core;

/// <summary>
/// Computes the Claude 429 cooldown. On repeated rate limiting the cooldown grows
/// exponentially (capped) with additive jitter, so a client that keeps getting 429
/// backs off further each time instead of retrying the shared per-account limit at a
/// fixed interval. The escalation is a floor: an explicit server Retry-After longer
/// than the computed value is always honored, and jitter is additive so the result
/// never dips below that instruction.
/// </summary>
public static class RateLimitBackoff
{
    /// <summary>Never wait less than this, even for a tiny or absent Retry-After.</summary>
    public static readonly TimeSpan MinimumCooldown = TimeSpan.FromSeconds(120);

    /// <summary>Ceiling for the exponential growth (a longer explicit Retry-After may exceed it).</summary>
    public static readonly TimeSpan MaximumCooldown = TimeSpan.FromSeconds(1800);

    /// <summary>Upper bound of the additive jitter, as a fraction of the base cooldown.</summary>
    public const double JitterFraction = 0.2;

    /// <param name="retryAfter">The server's Retry-After hint (or the headerless default).</param>
    /// <param name="failureCount">Consecutive 429s already observed (0 for the first).</param>
    /// <param name="jitter">Fraction added on top; clamped to <c>0..JitterFraction</c>.</param>
    /// <returns>The cooldown, always at least <c>max(MinimumCooldown, retryAfter)</c>.</returns>
    public static TimeSpan Cooldown(TimeSpan retryAfter, int failureCount, double jitter)
    {
        var baseCooldown = retryAfter > MinimumCooldown ? retryAfter : MinimumCooldown;
        var boundedExponent = Math.Clamp(failureCount, 0, 20);
        var grown = baseCooldown * Math.Pow(2, boundedExponent);
        var cappedGrowth = grown < MaximumCooldown ? grown : MaximumCooldown;
        // Cap the exponential growth, but never dip below an explicit longer wait.
        var escalated = cappedGrowth > baseCooldown ? cappedGrowth : baseCooldown;
        var clampedJitter = Math.Clamp(jitter, 0.0, JitterFraction);
        return escalated + escalated * clampedJitter;
    }
}
