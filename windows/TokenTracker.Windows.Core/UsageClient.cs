using System.Net.Http.Headers;

namespace TokenTracker.Windows.Core;

public sealed class UsageClient
{
    private static readonly Uri CodexUsageUrl = new("https://chatgpt.com/backend-api/wham/usage");
    private static readonly Uri ClaudeUsageUrl = new("https://api.anthropic.com/api/oauth/usage");

    private readonly HttpClient http;
    private readonly CredentialReader credentialReader;

    public UsageClient(HttpClient? http = null, CredentialReader? credentialReader = null)
    {
        this.http = http ?? new HttpClient { Timeout = TimeSpan.FromSeconds(5) };
        this.credentialReader = credentialReader ?? new CredentialReader();
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
            var auth = credentialReader.ReadCodexAuth();
            using var request = new HttpRequestMessage(HttpMethod.Get, CodexUsageUrl);
            request.Headers.Accept.Add(new MediaTypeWithQualityHeaderValue("application/json"));
            request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", auth.AccessToken);
            request.Headers.TryAddWithoutValidation("ChatGPT-Account-Id", auth.AccountId);
            request.Headers.UserAgent.ParseAdd("TokenTrackerWindows/1.0");

            var json = await SendForJsonAsync(request, cancellationToken);
            return UsageParser.ParseCodexUsage(json);
        }
        catch (Exception ex) when (ex is not OperationCanceledException)
        {
            return ProviderUsage.Unavailable(Provider.Codex, ex.Message);
        }
    }

    public async Task<ProviderUsage> FetchClaudeAsync(CancellationToken cancellationToken = default)
    {
        try
        {
            var token = credentialReader.ReadClaudeAccessToken();
            using var request = new HttpRequestMessage(HttpMethod.Get, ClaudeUsageUrl);
            request.Headers.Accept.Add(new MediaTypeWithQualityHeaderValue("application/json"));
            request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", token);
            request.Headers.TryAddWithoutValidation("anthropic-beta", "oauth-2025-04-20");
            request.Headers.UserAgent.ParseAdd("TokenTrackerWindows/1.0");

            var json = await SendForJsonAsync(request, cancellationToken);
            return UsageParser.ParseClaudeUsage(json);
        }
        catch (Exception ex) when (ex is not OperationCanceledException)
        {
            return ProviderUsage.Unavailable(Provider.Claude, ex.Message);
        }
    }

    private async Task<string> SendForJsonAsync(HttpRequestMessage request, CancellationToken cancellationToken)
    {
        using var response = await http.SendAsync(request, cancellationToken);
        response.EnsureSuccessStatusCode();
        return await response.Content.ReadAsStringAsync(cancellationToken);
    }
}
