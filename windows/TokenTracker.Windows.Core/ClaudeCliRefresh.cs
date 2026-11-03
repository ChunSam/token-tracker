using System.Collections;
using System.ComponentModel;
using System.Diagnostics;

namespace TokenTracker.Windows.Core;

public enum ClaudeCliRefreshOutcome
{
    /// The credential store was rewritten while the CLI ran.
    Refreshed,

    /// The CLI ran and left the store alone: its refresh token has lapsed as well,
    /// which only `/login` fixes, or it stopped on a screen of its own.
    Unchanged,

    /// No `claude.exe` in any of the places it installs to.
    CliNotFound,
    LaunchFailed
}

/// One try at getting Claude Code to renew its own stored token.
public sealed record ClaudeCliRefreshAttempt(DateTimeOffset AttemptedAt, ClaudeCliRefreshOutcome Outcome);

/// Renewing an expired Claude token without the user opening a terminal.
///
/// The access token lives ~8h and only Claude Code may renew it. Its refresh token
/// is single-use, so spending it here would sign the CLI out — the bug CodexBar
/// shipped and then backed out — and Anthropic's terms bar third-party apps from
/// holding Claude credentials of their own. What remains is running the unmodified
/// CLI, which renews the stored token while it starts: measured on macOS with
/// 2.1.314 at ~0.7s after launch, before its first screen, with no model request.
/// The launch runs in a folder Claude Code has never been told to trust, so it
/// stops at the trust prompt and never reaches hooks, plugins or a session.
///
/// Mirrors <c>Sources/TokenTrackerCore/ClaudeCLIRefresh.swift</c>.
public static class ClaudeCliRefresh
{
    /// How long the CLI gets to rewrite the store. Startup renewal took under a
    /// second when measured; the rest is room for a slow network.
    public static readonly TimeSpan Timeout = TimeSpan.FromSeconds(15);

    /// After a renewal, the earliest next try. A fresh token lives for hours, so
    /// another lapse this soon means something else is wrong, and it is not worth
    /// a launch on every poll.
    public static readonly TimeSpan RetryAfterRefresh = TimeSpan.FromMinutes(5);

    /// After a try that changed nothing or found no CLI. The refresh token itself
    /// may have lapsed, which only `/login` fixes, so try rarely rather than on
    /// every poll.
    public static readonly TimeSpan RetryAfterFailure = TimeSpan.FromMinutes(30);

    public static DateTimeOffset NextAttempt(ClaudeCliRefreshAttempt attempt) =>
        attempt.AttemptedAt + (attempt.Outcome == ClaudeCliRefreshOutcome.Refreshed ? RetryAfterRefresh : RetryAfterFailure);

    /// No try yet is due at once.
    public static bool IsDue(ClaudeCliRefreshAttempt? lastAttempt, DateTimeOffset now) =>
        lastAttempt is null || now >= NextAttempt(lastAttempt);

    /// Belt and braces for a launch that should only start up: no user hooks
    /// (SessionStart and the rest would otherwise run), no MCP servers, no Remote
    /// Control. The untrusted folder already keeps all of them from running.
    public static IReadOnlyList<string> Arguments { get; } = new[]
    {
        "--strict-mcp-config",
        "--settings", "{\"remoteControlAtStartup\":false,\"disableAllHooks\":true}"
    };

    /// The app's own environment, minus anything that would point the CLI at other
    /// credentials or another config directory — the app only reads the default
    /// store, so that is the one to renew. The binary's directory goes first on
    /// PATH. Names compare without case, as Windows does.
    public static IReadOnlyDictionary<string, string> LaunchEnvironment(
        IReadOnlyDictionary<string, string> baseEnvironment,
        string binaryDirectory)
    {
        var environment = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        foreach (var (key, value) in baseEnvironment)
        {
            if (!key.StartsWith("ANTHROPIC_", StringComparison.OrdinalIgnoreCase) &&
                !key.StartsWith("CLAUDE", StringComparison.OrdinalIgnoreCase))
            {
                environment[key] = value;
            }
        }

        environment["PATH"] = environment.TryGetValue("PATH", out var path) && path.Length > 0
            ? binaryDirectory + Path.PathSeparator + path
            : binaryDirectory;
        // Renewing a token is no reason to replace the user's installation.
        environment["DISABLE_AUTOUPDATER"] = "1";
        if (!environment.ContainsKey("TERM"))
        {
            environment["TERM"] = "xterm-256color";
        }

        return environment;
    }

    /// Where `claude.exe` installs, in the order to try: the native installer's
    /// location, then PATH. An npm install is a `.cmd` shim, which is left out —
    /// it would put cmd.exe between this app and the process it has to stop.
    public static IReadOnlyList<string> CandidatePaths(string home, string? path)
    {
        var paths = new List<string> { System.IO.Path.Combine(home, ".local", "bin", "claude.exe") };
        foreach (var directory in (path ?? "").Split(Path.PathSeparator, StringSplitOptions.RemoveEmptyEntries))
        {
            var trimmed = directory.Trim().Trim('"');
            if (trimmed.Length > 0)
            {
                paths.Add(System.IO.Path.Combine(trimmed, "claude.exe"));
            }
        }

        return paths.Distinct(StringComparer.OrdinalIgnoreCase).ToList();
    }

    /// The first installed `claude.exe`, or null.
    public static string? Locate(string? homeDirectory = null) =>
        CandidatePaths(homeDirectory ?? AppPaths.HomeDirectory, System.Environment.GetEnvironmentVariable("PATH"))
            .FirstOrDefault(File.Exists);
}

/// Runs the CLI when a try is due and reports whether the store moved. Locked so
/// two overlapping refreshes cannot start two CLIs.
public sealed class ClaudeCliRefresher
{
    private readonly object gate = new();
    private readonly string? homeDirectory;
    private readonly string workingDirectory;
    private ClaudeCliRefreshAttempt? lastAttempt;
    private bool inFlight;

    public ClaudeCliRefresher(string? homeDirectory = null, string? workingDirectory = null)
    {
        this.homeDirectory = homeDirectory;
        this.workingDirectory = workingDirectory ?? AppPaths.ClaudeCliRefreshDirectory;
    }

    public ClaudeCliRefreshAttempt? LastAttempt
    {
        get
        {
            lock (gate)
            {
                return lastAttempt;
            }
        }
    }

    /// True when the credential store was rewritten, so it is worth reading again.
    public async Task<bool> RefreshIfDueAsync(DateTimeOffset now, CancellationToken cancellationToken = default)
    {
        lock (gate)
        {
            if (inFlight || !ClaudeCliRefresh.IsDue(lastAttempt, now))
            {
                return false;
            }

            inFlight = true;
        }

        var outcome = ClaudeCliRefreshOutcome.LaunchFailed;
        try
        {
            outcome = await AttemptAsync(cancellationToken);
        }
        finally
        {
            lock (gate)
            {
                lastAttempt = new ClaudeCliRefreshAttempt(now, outcome);
                inFlight = false;
            }
        }

        return outcome == ClaudeCliRefreshOutcome.Refreshed;
    }

    private async Task<ClaudeCliRefreshOutcome> AttemptAsync(CancellationToken cancellationToken)
    {
        var binary = ClaudeCliRefresh.Locate(homeDirectory);
        if (binary is null)
        {
            return ClaudeCliRefreshOutcome.CliNotFound;
        }

        var credentialsPath = AppPaths.ClaudeCredentialsPath(homeDirectory);
        var before = LastWrite(credentialsPath);
        Process? process;
        try
        {
            Directory.CreateDirectory(workingDirectory);
            // No window, no redirection: the CLI gets a console of its own that
            // nobody sees, which is what it needs to take its interactive path.
            var startInfo = new ProcessStartInfo(binary)
            {
                UseShellExecute = false,
                CreateNoWindow = true,
                WorkingDirectory = workingDirectory
            };
            foreach (var argument in ClaudeCliRefresh.Arguments)
            {
                startInfo.ArgumentList.Add(argument);
            }

            var environment = ClaudeCliRefresh.LaunchEnvironment(CurrentEnvironment(), Path.GetDirectoryName(binary) ?? "");
            startInfo.Environment.Clear();
            foreach (var (key, value) in environment)
            {
                startInfo.Environment[key] = value;
            }

            process = Process.Start(startInfo);
        }
        catch (Exception ex) when (ex is Win32Exception or InvalidOperationException or IOException or UnauthorizedAccessException)
        {
            return ClaudeCliRefreshOutcome.LaunchFailed;
        }

        if (process is null)
        {
            return ClaudeCliRefreshOutcome.LaunchFailed;
        }

        using (process)
        {
            var refreshed = false;
            try
            {
                var deadline = DateTimeOffset.UtcNow + ClaudeCliRefresh.Timeout;
                while (DateTimeOffset.UtcNow < deadline)
                {
                    if (IsRenewed(credentialsPath, before))
                    {
                        refreshed = true;
                        break;
                    }

                    if (process.HasExited)
                    {
                        break;
                    }

                    await Task.Delay(100, cancellationToken);
                }

                refreshed = refreshed || IsRenewed(credentialsPath, before);
                if (refreshed && !process.HasExited)
                {
                    // Let a write that is still settling finish before the process goes.
                    await Task.Delay(1000, cancellationToken);
                }
            }
            finally
            {
                Stop(process);
            }

            return refreshed ? ClaudeCliRefreshOutcome.Refreshed : ClaudeCliRefreshOutcome.Unchanged;
        }
    }

    /// The file moved and now holds a token that has not lapsed. A file caught
    /// mid-write fails to read and counts as not yet renewed.
    private bool IsRenewed(string credentialsPath, DateTime? before)
    {
        var after = LastWrite(credentialsPath);
        if (after is null || after == before)
        {
            return false;
        }

        try
        {
            var credential = new CredentialReader().ReadClaudeCredential(homeDirectory);
            return !CredentialExpiry.IsExpired(credential.ExpiresAt);
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException or System.Text.Json.JsonException or KeyNotFoundException or InvalidOperationException)
        {
            return false;
        }
    }

    private static DateTime? LastWrite(string path) =>
        File.Exists(path) ? File.GetLastWriteTimeUtc(path) : null;

    private static void Stop(Process process)
    {
        try
        {
            if (!process.HasExited)
            {
                process.Kill(entireProcessTree: true);
                process.WaitForExit(2000);
            }
        }
        catch (Exception ex) when (ex is InvalidOperationException or Win32Exception or NotSupportedException)
        {
            // Already gone, or not ours to stop; nothing is left to clean up.
        }
    }

    private static IReadOnlyDictionary<string, string> CurrentEnvironment()
    {
        var environment = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        foreach (DictionaryEntry entry in System.Environment.GetEnvironmentVariables())
        {
            if (entry.Key is string key && entry.Value is string value)
            {
                environment[key] = value;
            }
        }

        return environment;
    }
}
