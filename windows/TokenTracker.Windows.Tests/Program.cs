using TokenTracker.Windows.Core;

static void ExpectEqual<T>(T actual, T expected, string message)
{
    if (!EqualityComparer<T>.Default.Equals(actual, expected))
    {
        throw new InvalidOperationException($"{message}. Expected {expected}, got {actual}");
    }
}

static void Expect(bool condition, string message)
{
    if (!condition)
    {
        throw new InvalidOperationException(message);
    }
}

var now = new DateTimeOffset(2026, 5, 27, 0, 0, 0, TimeSpan.Zero);

ExpectEqual(PercentMath.RemainingPercent(0), 100, "0 used leaves 100 remaining");
ExpectEqual(PercentMath.RemainingPercent(25.4), 75, "25.4 used rounds to 75 remaining");
ExpectEqual(PercentMath.RemainingPercent(100), 0, "100 used leaves 0 remaining");
ExpectEqual(PercentMath.RemainingPercent(120), 0, "remaining is clamped at 0");

var healthySevenDay = Usage(
    Provider.Claude,
    remainingPercent5h: 100,
    remainingPercent7d: 90,
    now);
ExpectEqual(DisplayFormatter.DisplayPercent(healthySevenDay), 100, "healthy 7d does not override 5h");
Expect(!DisplayFormatter.DisplaysSevenDayPercent(healthySevenDay), "healthy 7d is not highlighted");

var thresholdSevenDay = Usage(
    Provider.Claude,
    remainingPercent5h: 100,
    remainingPercent7d: 10,
    now);
ExpectEqual(DisplayFormatter.DisplayPercent(thresholdSevenDay), 10, "7d threshold overrides 5h");
Expect(DisplayFormatter.DisplaysSevenDayPercent(thresholdSevenDay), "7d threshold is highlighted");

var missingFiveHour = Usage(
    Provider.Claude,
    remainingPercent5h: null,
    remainingPercent7d: 42,
    now);
ExpectEqual(DisplayFormatter.DisplayPercent(missingFiveHour), 42, "7d is used when 5h is missing");
Expect(DisplayFormatter.DisplaysSevenDayPercent(missingFiveHour), "7d fallback is highlighted");

var snapshot = new UsageSnapshot(
    Claude: Usage(Provider.Claude, 63, 80, now),
    Codex: Usage(Provider.Codex, 91, 99, now, plan: "plus"),
    UpdatedAt: now);
ExpectEqual(DisplayFormatter.StatusTitle(snapshot, DisplayMode.Both), "Cdx 91% · Cl 63%", "both display mode");
ExpectEqual(DisplayFormatter.StatusTitle(snapshot, DisplayMode.CodexOnly), "Cdx 91%", "codex display mode");
ExpectEqual(DisplayFormatter.StatusTitle(snapshot, DisplayMode.ClaudeOnly), "Cl 63%", "claude display mode");
ExpectEqual(DisplayFormatter.StatusTitle(snapshot, DisplayMode.LowestRemaining), "AI 63%", "lowest display mode");
ExpectEqual(DisplayFormatter.Tooltip(snapshot, ProviderLabelStyle.Abbreviation), "Cdx 91%, Cl 63%", "abbreviated tooltip");
ExpectEqual(DisplayFormatter.Tooltip(snapshot, ProviderLabelStyle.Icon), "Codex 91%, Claude 63%", "named tooltip");

var unavailableSnapshot = new UsageSnapshot(
    Claude: ProviderUsage.Unavailable(Provider.Claude, "Disabled"),
    Codex: ProviderUsage.Unavailable(Provider.Codex, "HTTP request failed"),
    UpdatedAt: now);
ExpectEqual(DisplayFormatter.StatusTitle(unavailableSnapshot, DisplayMode.Both), "Cdx -- · Cl --", "unavailable providers display dashes");
ExpectEqual(DisplayFormatter.Tooltip(unavailableSnapshot), "Codex --, Claude --", "unavailable tooltip displays dashes");

var codexJson = """
{
  "plan_type": "prolite",
  "rate_limit": {
    "primary_window": { "used_percent": 24.2, "reset_at": 1770000000 },
    "secondary_window": { "used_percent": 98.0, "reset_at": 1770500000 }
  }
}
""";
var codexUsage = UsageParser.ParseCodexUsage(codexJson, now);
ExpectEqual(codexUsage.RemainingPercent5h, 76, "Codex primary remaining percent");
ExpectEqual(codexUsage.RemainingPercent7d, 2, "Codex secondary remaining percent");
ExpectEqual(codexUsage.Plan, "prolite", "Codex plan");

var claudeJson = """
{
  "five_hour": { "utilization": 15.0, "resets_at": "2026-05-27T12:00:00Z" },
  "seven_day": { "utilization": 100.0, "resets_at": "2026-05-29T12:00:00Z" }
}
""";
var claudeUsage = UsageParser.ParseClaudeUsage(claudeJson, now);
ExpectEqual(claudeUsage.RemainingPercent5h, 85, "Claude five hour remaining percent");
ExpectEqual(claudeUsage.RemainingPercent7d, 0, "Claude seven day remaining percent");

var home = Path.Combine(Path.GetTempPath(), "token-tracker-windows-tests-" + Guid.NewGuid().ToString("N"));
Directory.CreateDirectory(Path.Combine(home, ".codex"));
Directory.CreateDirectory(Path.Combine(home, ".claude"));
File.WriteAllText(Path.Combine(home, ".codex", "auth.json"), """
{
  "tokens": {
    "access_token": "codex-token",
    "account_id": "account-id"
  }
}
""");
File.WriteAllText(Path.Combine(home, ".claude", ".credentials.json"), """
{
  "claudeAiOauth": {
    "accessToken": "claude-token"
  }
}
""");

var credentials = new CredentialReader();
var codexAuth = credentials.ReadCodexAuth(home);
ExpectEqual(codexAuth.AccessToken, "codex-token", "Codex access token read");
ExpectEqual(codexAuth.AccountId, "account-id", "Codex account id read");
ExpectEqual(credentials.ReadClaudeAccessToken(home), "claude-token", "Claude access token read");
Directory.Delete(home, recursive: true);

var korean = new Localizer(AppLanguage.Korean);
ExpectEqual(korean.Text(L10nKey.RefreshNow), "지금 새로고침", "Korean refresh label");
ExpectEqual(korean.Text(L10nKey.ClaudeOnly), "Claude만", "Korean Claude-only label");

var settingsPath = Path.Combine(Path.GetTempPath(), "token-tracker-settings-" + Guid.NewGuid().ToString("N"), "settings.json");
var settingsStore = new SettingsStore(settingsPath);
settingsStore.Save(new AppSettings { Language = AppLanguage.Korean, DisplayMode = DisplayMode.ClaudeOnly });
var loadedSettings = settingsStore.Load();
ExpectEqual(loadedSettings.Language, AppLanguage.Korean, "Language setting persists");
ExpectEqual(loadedSettings.DisplayMode, DisplayMode.ClaudeOnly, "Display mode setting persists");
Directory.Delete(Path.GetDirectoryName(settingsPath)!, recursive: true);

Console.WriteLine("TokenTracker.Windows.Tests passed");

static ProviderUsage Usage(
    Provider provider,
    int? remainingPercent5h,
    int? remainingPercent7d,
    DateTimeOffset now,
    string? plan = null) =>
    new(
        provider,
        remainingPercent5h,
        remainingPercent7d,
        ResetAt5h: null,
        ResetAt7d: null,
        UsageSource.Api,
        Error: null,
        Plan: plan,
        Model: null,
        UpdatedAt: now);
