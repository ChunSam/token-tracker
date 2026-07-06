namespace TokenTracker.Windows.Core;

/// Pure helpers for the user-initiated "pause updates" state. A paused poll
/// skips the network fetch entirely, reducing the app's own contribution to the
/// shared per-account rate limit. The pause instant is persisted, so a restart
/// during a pause stays paused. Mirrors the Swift <c>PauseController</c>.
public static class PauseController
{
    /// A pause farther out than this is treated as "until I resume" (no
    /// countdown shown) rather than a timed pause.
    public static readonly TimeSpan IndefiniteThreshold = TimeSpan.FromDays(365);

    public static bool IsPaused(DateTimeOffset? pausedUntil, DateTimeOffset? now = null)
    {
        if (pausedUntil is null)
        {
            return false;
        }

        return pausedUntil.Value > (now ?? DateTimeOffset.Now);
    }

    public static TimeSpan Remaining(DateTimeOffset? pausedUntil, DateTimeOffset? now = null)
    {
        var current = now ?? DateTimeOffset.Now;
        if (pausedUntil is null || pausedUntil.Value <= current)
        {
            return TimeSpan.Zero;
        }

        return pausedUntil.Value - current;
    }

    public static bool IsIndefinite(DateTimeOffset? pausedUntil, DateTimeOffset? now = null)
    {
        if (pausedUntil is null)
        {
            return false;
        }

        return pausedUntil.Value - (now ?? DateTimeOffset.Now) > IndefiniteThreshold;
    }
}
