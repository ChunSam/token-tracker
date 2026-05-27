using System.Text.Json;

namespace TokenTracker.Windows.Core;

public sealed record CodexAuth(string AccessToken, string AccountId);

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
        using var document = JsonDocument.Parse(File.ReadAllText(AppPaths.ClaudeCredentialsPath(homeDirectory)));
        var token = document.RootElement
            .GetProperty("claudeAiOauth")
            .GetProperty("accessToken")
            .GetString();

        if (string.IsNullOrWhiteSpace(token))
        {
            throw new InvalidOperationException("Missing Claude credentials");
        }

        return token;
    }
}
