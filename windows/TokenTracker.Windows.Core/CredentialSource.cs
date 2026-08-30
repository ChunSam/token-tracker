namespace TokenTracker.Windows.Core;

public enum ClaudeCredentialStore
{
    Keychain,
    CredentialsFile,
    None
}

/// <summary>
/// Where the Claude access token actually came from, and when it was last written.
///
/// Diagnostics used to report only whether the credentials file exists, which says
/// nothing about the question that matters when usage stops loading: is anything
/// still refreshing this token? The access token lives ~8h and only the Claude Code
/// CLI writes the store, so a modification date hours or days old is the signal that
/// the store has been abandoned.
///
/// Reads attributes only — never the secret. Windows has no keychain, so the file is
/// always the live store here; the keychain seam exists so the precedence rule and
/// its tests stay identical to the macOS port.
/// </summary>
public sealed record ClaudeCredentialSource(ClaudeCredentialStore Kind, DateTimeOffset? LastWrittenAt)
{
    public static ClaudeCredentialSource Detect(string credentialsFilePath, DateTimeOffset? keychainModifiedAt = null)
    {
        if (keychainModifiedAt is { } modified)
        {
            return new ClaudeCredentialSource(ClaudeCredentialStore.Keychain, modified);
        }

        if (File.Exists(credentialsFilePath))
        {
            return new ClaudeCredentialSource(
                ClaudeCredentialStore.CredentialsFile,
                new DateTimeOffset(File.GetLastWriteTimeUtc(credentialsFilePath), TimeSpan.Zero));
        }

        return new ClaudeCredentialSource(ClaudeCredentialStore.None, null);
    }

    /// <summary>
    /// How stale the store is, which is what tells a lapsed token apart from a merely
    /// unlucky one: past roughly the 8h access-token life, nothing is refreshing it.
    /// </summary>
    public TimeSpan? Age(DateTimeOffset now) =>
        LastWrittenAt is { } written ? now - written : null;
}

/// <summary>
/// The line the menu was missing when Claude usage stops loading: nothing has written
/// the credential store for longer than a token lives, so the fix is not to wait but
/// to run the CLI once.
///
/// The plain "sign in again" recovery is complete advice for a token that merely
/// lapsed. It is not the whole story for a store that has been abandoned — a user who
/// signs in through the desktop app has signed in, and the store still will not move.
/// Saying how long it has been unwritten is what tells the two apart.
/// </summary>
public static class CredentialStoreAdvice
{
    /// <summary>
    /// A Claude access token lives ~8h. Past that, an expired token is not bad luck:
    /// whatever used to refresh the store has stopped.
    /// </summary>
    public static readonly TimeSpan StaleAfter = TimeSpan.FromHours(8);

    /// <summary>
    /// Null unless this is Claude, the failure is a lapsed token, and the store is old
    /// enough that nothing can still be refreshing it.
    /// </summary>
    public static string? StaleLine(
        Provider provider,
        UsageIssue issue,
        ClaudeCredentialSource source,
        DateTimeOffset now,
        Localizer? localizer = null)
    {
        if (provider != Provider.Claude || string.IsNullOrWhiteSpace(issue.TechnicalDetail))
        {
            return null;
        }

        // Read past the visible kind to the error underneath it: once the last good
        // reading is being carried across a lapsed token the status reads "using cached
        // data", and the expiry survives only in the error it carries.
        if (UsageIssueFormatter.Kind(issue.TechnicalDetail) != UsageIssueKind.ExpiredCredentials)
        {
            return null;
        }

        if (source.Age(now) is not { } age || age < StaleAfter)
        {
            return null;
        }

        localizer ??= new Localizer(AppLanguage.English);
        return localizer
            .Text(L10nKey.CredentialStale)
            .Replace("{age}", UsageForecaster.DurationText(age.TotalSeconds), StringComparison.Ordinal);
    }
}
