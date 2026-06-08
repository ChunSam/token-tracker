using System.Net;
using System.Net.Http.Headers;

namespace TokenTracker.Windows.Core;

public sealed class UsageClient
{
    private static readonly Uri CodexUsageUrl = new("https://chatgpt.com/backend-api/wham/usage");
    private static readonly Uri ClaudeUsageUrl = new("https://api.anthropic.com/api/oauth/usage");
    private static readonly TimeSpan DefaultClaudeRateLimitCooldown = TimeSpan.FromMinutes(5);

    private readonly HttpClient http;
    private readonly CredentialReader credentialReader;
    private readonly ClaudeRateLimitState claudeRateLimitState = new();
    private readonly string? homeDirectory;

    public UsageClient(HttpClient? http = null, CredentialReader? credentialReader = null, string? homeDirectory = null)
    {
        this.http = http ?? new HttpClient { Timeout = TimeSpan.FromSeconds(5) };
        this.credentialReader = credentialReader ?? new CredentialReader();
        this.homeDirectory = homeDirectory;
    }

    public async Task<UsageSnapshot> RefreshAsync(CancellationToken cancellationToken = default)
    {
        var claudeTask = FetchClaudeAsync(cancellationToken);
        var codexTask = FetchCodexAsync(cancellationToken);
        await Task.WhenAll(claudeTask, codexTask);

        return new UsageSnapshot(claudeTask.Result, codexTask.Result, DateTimeOffset.Now);
    }

    public async Task<ProviderUsage> FetchCodexAsync(CancellationToken cancellationToken = default)
    {
        try
        {
            var auth = credentialReader.ReadCodexAuth(homeDirectory);
            using var request = new HttpRequestMessage(HttpMethod.Get, CodexUsageUrl);
            request.Headers.Accept.Add(new MediaTypeWithQualityHeaderValue("application/json"));
            request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", auth.AccessToken);
            request.Headers.TryAddWithoutValidation("ChatGPT-Account-Id", auth.AccountId);
            request.Headers.UserAgent.ParseAdd("TokenTrackerWindows/1.0");

            var json = await SendForJsonAsync(request, "Codex API", cancellationToken);
            return UsageParser.ParseCodexUsage(json);
        }
        catch (TaskCanceledException) when (!cancellationToken.IsCancellationRequested)
        {
            return ProviderUsage.Unavailable(Provider.Codex, "Timed out contacting Codex API");
        }
        catch (Exception ex) when (ex is not OperationCanceledException)
        {
            return ProviderUsage.Unavailable(Provider.Codex, ex.Message);
        }
    }

    public async Task<ProviderUsage> FetchClaudeAsync(CancellationToken cancellationToken = default)
    {
        if (claudeRateLimitState.CurrentError("Claude API") is { } rateLimitError)
        {
            return ProviderUsage.Unavailable(Provider.Claude, rateLimitError.Message);
        }

        try
        {
            var credential = credentialReader.ReadClaudeCredential(homeDirectory);
            using var request = new HttpRequestMessage(HttpMethod.Get, ClaudeUsageUrl);
            request.Headers.Accept.Add(new MediaTypeWithQualityHeaderValue("application/json"));
            request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", credential.AccessToken);
            request.Headers.TryAddWithoutValidation("anthropic-beta", "oauth-2025-04-20");
            request.Headers.UserAgent.ParseAdd("TokenTrackerWindows/1.0");

            var json = await SendForJsonAsync(request, "Claude API", cancellationToken);
            var usage = UsageParser.ParseClaudeUsage(json, fallbackPlan: credential.Plan);
            claudeRateLimitState.Clear();
            return usage;
        }
        catch (UsageHttpException ex) when (ex.StatusCode == HttpStatusCode.TooManyRequests)
        {
            claudeRateLimitState.BackOff(ex.RetryAfter ?? DefaultClaudeRateLimitCooldown);
            return ProviderUsage.Unavailable(
                Provider.Claude,
                claudeRateLimitState.CurrentError("Claude API")?.Message ?? ex.Message);
        }
        catch (TaskCanceledException) when (!cancellationToken.IsCancellationRequested)
        {
            return ProviderUsage.Unavailable(Provider.Claude, "Timed out contacting Claude API");
        }
        catch (Exception ex) when (ex is not OperationCanceledException)
        {
            return ProviderUsage.Unavailable(Provider.Claude, ex.Message);
        }
    }

    private async Task<string> SendForJsonAsync(HttpRequestMessage request, string serviceName, CancellationToken cancellationToken)
    {
        using var response = await http.SendAsync(request, cancellationToken);
        if (!response.IsSuccessStatusCode)
        {
            throw new UsageHttpException(response.StatusCode, serviceName, RetryAfter(response));
        }

        return await response.Content.ReadAsStringAsync(cancellationToken);
    }

    private static TimeSpan? RetryAfter(HttpResponseMessage response)
    {
        var retryAfter = response.Headers.RetryAfter;
        if (retryAfter?.Delta is { } delta)
        {
            return MaxZero(delta);
        }

        if (retryAfter?.Date is { } date)
        {
            return MaxZero(date - DateTimeOffset.Now);
        }

        return null;
    }

    private static TimeSpan MaxZero(TimeSpan value) =>
        value < TimeSpan.Zero ? TimeSpan.Zero : value;
}

public sealed class UsageHttpException : Exception
{
    public HttpStatusCode StatusCode { get; }
    public string ServiceName { get; }
    public TimeSpan? RetryAfter { get; }

    public UsageHttpException(HttpStatusCode statusCode, string serviceName, TimeSpan? retryAfter = null)
        : base(FormatMessage(statusCode, serviceName, retryAfter))
    {
        StatusCode = statusCode;
        ServiceName = serviceName;
        RetryAfter = retryAfter;
    }

    private static string FormatMessage(HttpStatusCode statusCode, string serviceName, TimeSpan? retryAfter)
    {
        var prefix = $"HTTP {(int)statusCode} from {serviceName}";
        return statusCode == HttpStatusCode.TooManyRequests && retryAfter is not null
            ? $"{prefix}; retrying after {FormatRetryAfter(retryAfter.Value)}"
            : prefix;
    }

    private static string FormatRetryAfter(TimeSpan retryAfter)
    {
        var seconds = Math.Max(0, (int)Math.Ceiling(retryAfter.TotalSeconds));
        if (seconds < 60)
        {
            return $"{seconds}s";
        }

        var minutes = (int)Math.Ceiling(seconds / 60.0);
        if (minutes < 60)
        {
            return $"{minutes}m";
        }

        var hours = minutes / 60;
        var remainingMinutes = minutes % 60;
        return remainingMinutes == 0 ? $"{hours}h" : $"{hours}h {remainingMinutes}m";
    }
}

internal sealed class ClaudeRateLimitState
{
    private static readonly TimeSpan MinimumCooldown = TimeSpan.FromMinutes(2);
    private readonly object gate = new();
    private DateTimeOffset? retryAllowedAt;

    public UsageHttpException? CurrentError(string serviceName)
    {
        lock (gate)
        {
            if (retryAllowedAt is null)
            {
                return null;
            }

            var remaining = retryAllowedAt.Value - DateTimeOffset.Now;
            if (remaining <= TimeSpan.Zero)
            {
                retryAllowedAt = null;
                return null;
            }

            return new UsageHttpException(HttpStatusCode.TooManyRequests, serviceName, remaining);
        }
    }

    public void BackOff(TimeSpan retryAfter)
    {
        lock (gate)
        {
            var cooldown = retryAfter > MinimumCooldown ? retryAfter : MinimumCooldown;
            retryAllowedAt = DateTimeOffset.Now.Add(cooldown);
        }
    }

    public void Clear()
    {
        lock (gate)
        {
            retryAllowedAt = null;
        }
    }
}
