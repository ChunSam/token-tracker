using System.Text.Json;

namespace TokenTracker.Windows.Core;

public sealed record CodexAuth(string AccessToken, string AccountId);
public sealed record ClaudeCredential(string AccessToken, string? Plan);

public sealed class CredentialReader
{
    public CodexAuth ReadCodexAuth(string? homeDirectory = null)
    {
        using var document = JsonDocument.Parse(File.ReadAllText(AppPaths.CodexAuthPath(homeDirectory)));
        var tokens = document.RootElement.GetProperty("tokens");
        var accessToken = tokens.GetProperty("access_token").GetString();
        var accountId = tokens.GetProperty("account_id").GetString();

        if (string.IsNullOrWhiteSpace(accessToken) || string.IsNullOrWhiteSpace(accountId))
        {
            throw new InvalidOperationException("Missing Codex credentials");
        }

        return new CodexAuth(accessToken, accountId);
    }

    public string ReadClaudeAccessToken(string? homeDirectory = null)
    {
        return ReadClaudeCredential(homeDirectory).AccessToken;
    }

    public ClaudeCredential ReadClaudeCredential(string? homeDirectory = null)
    {
        using var document = JsonDocument.Parse(File.ReadAllText(AppPaths.ClaudeCredentialsPath(homeDirectory)));
        var claudeOauth = document.RootElement.GetProperty("claudeAiOauth");
        var token = claudeOauth.GetProperty("accessToken").GetString();

        if (string.IsNullOrWhiteSpace(token))
        {
            throw new InvalidOperationException("Missing Claude credentials");
        }

        return new ClaudeCredential(token, ReadPlan(claudeOauth));
    }

    private static string? ReadPlan(JsonElement element)
    {
        foreach (var key in new[] { "plan_type", "planType", "subscription_type", "subscriptionType", "tier", "rate_limit_tier", "rateLimitTier" })
        {
            if (element.TryGetProperty(key, out var value) && value.ValueKind == JsonValueKind.String)
            {
                var text = value.GetString();
                if (!string.IsNullOrWhiteSpace(text))
                {
                    return text;
                }
            }
        }

        return null;
    }
}
