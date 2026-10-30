using System.Diagnostics;
using System.Globalization;
using System.Net;
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
Expect(!DisplayFormatter.IsSevenDayWarning(healthySevenDay), "healthy 7d is not highlighted");

var thresholdSevenDay = Usage(
    Provider.Claude,
    remainingPercent5h: 100,
    remainingPercent7d: 10,
    now);
ExpectEqual(DisplayFormatter.DisplayPercent(thresholdSevenDay), 10, "7d threshold overrides 5h");
Expect(DisplayFormatter.IsSevenDayWarning(thresholdSevenDay), "7d threshold is highlighted");

var missingFiveHour = Usage(
    Provider.Claude,
    remainingPercent5h: null,
    remainingPercent7d: 42,
    now);
ExpectEqual(DisplayFormatter.DisplayPercent(missingFiveHour), 42, "7d is used when 5h is missing");
Expect(!DisplayFormatter.IsSevenDayWarning(missingFiveHour), "healthy 7d fallback is not highlighted when 5h is missing");

var missingBothWindows = Usage(Provider.Codex, null, null, now);
ExpectEqual(DisplayFormatter.PreferredForecastWindow(Usage(Provider.Claude, 73, null, now)), ForecastWindow.FiveHour, "5h window is preferred when it reports");
ExpectEqual(DisplayFormatter.PreferredForecastWindow(missingFiveHour), ForecastWindow.SevenDay, "forecast surfaces fall back to 7d when 5h is missing");
ExpectEqual(DisplayFormatter.PreferredForecastWindow(missingBothWindows), ForecastWindow.FiveHour, "default window is 5h when neither reports");

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

// Since 2026-07 the API can report the weekly window as primary_window (the 5h
// window was removed); windows carrying limit_window_seconds map by length.
var codexWeeklyOnlyJson = """
{
  "plan_type": "plus",
  "rate_limit": {
    "primary_window": { "used_percent": 4, "limit_window_seconds": 604800, "reset_at": 1785331564 }
  }
}
""";
var codexWeeklyOnly = UsageParser.ParseCodexUsage(codexWeeklyOnlyJson, now);
ExpectEqual(codexWeeklyOnly.RemainingPercent5h, null, "a weekly primary window leaves the 5h lane empty");
ExpectEqual(codexWeeklyOnly.RemainingPercent7d, 96, "a weekly primary window fills the 7d lane");
ExpectEqual(codexWeeklyOnly.ResetAt5h, null, "no 5h reset when the 5h window is absent");
ExpectEqual(codexWeeklyOnly.ResetAt7d, DateTimeOffset.FromUnixTimeSeconds(1785331564), "the weekly reset lands in the 7d lane");
ExpectEqual(codexWeeklyOnly.Plan, "plus", "the plan is preserved");

var swappedWindows = CodexWindowMapper.Map(
    new CodexRateWindow(20, null, 604800),
    new CodexRateWindow(10, null, 18000));
ExpectEqual(swappedWindows.FiveHour?.UsedPercent, 10, "an 18000s window maps to the 5h lane regardless of position");
ExpectEqual(swappedWindows.SevenDay?.UsedPercent, 20, "a 604800s window maps to the 7d lane regardless of position");

var collidingWindows = CodexWindowMapper.Map(
    new CodexRateWindow(20, null, 604800),
    new CodexRateWindow(30, null, 604800));
ExpectEqual(collidingWindows.SevenDay?.UsedPercent, 20, "the first window wins a lane collision");
Expect(collidingWindows.FiveHour is null, "a colliding window is dropped rather than mislabeled");

var claudeJson = """
{
  "plan_type": "max",
  "five_hour": { "utilization": 15.0, "resets_at": "2026-05-27T12:00:00Z" },
  "seven_day": { "utilization": 100.0, "resets_at": "2026-05-29T12:00:00Z" }
}
""";
var claudeUsage = UsageParser.ParseClaudeUsage(claudeJson, now);
ExpectEqual(claudeUsage.RemainingPercent5h, 85, "Claude five hour remaining percent");
ExpectEqual(claudeUsage.RemainingPercent7d, 0, "Claude seven day remaining percent");
ExpectEqual(claudeUsage.Plan, "max", "Claude plan");

var claudeFallbackPlanUsage = UsageParser.ParseClaudeUsage("""
{
  "five_hour": { "utilization": 40.0, "resets_at": "2026-05-27T12:00:00Z" },
  "seven_day": { "utilization": 50.0, "resets_at": "2026-05-29T12:00:00Z" }
}
""", now, "team");
ExpectEqual(claudeFallbackPlanUsage.Plan, "team", "Claude fallback plan");

foreach (var invalidJson in new[]
{
    "{}", "[]", "null", """{"five_hour":{},"seven_day":null}""",
    """{"five_hour":{"utilization":true}}""",
    """{"five_hour":{"utilization":"unknown"}}""",
    """{"five_hour":{"utilization":"NaN"}}""",
    """{"seven_day":{"utilization":"Infinity"}}"""
})
{
    var rejected = false;
    try { UsageParser.ParseClaudeUsage(invalidJson); }
    catch (InvalidOperationException ex) when (ex.Message == "Invalid response") { rejected = true; }
    Expect(rejected, $"Claude rejects a response without usable measurements: {invalidJson}");
}
var weeklyClaude = UsageParser.ParseClaudeUsage("""{"seven_day":{"utilization":"25.4"}}""", now, "team");
ExpectEqual(weeklyClaude.RemainingPercent5h, (int?)null, "Claude allows a missing five-hour window");
ExpectEqual(weeklyClaude.RemainingPercent7d, 75, "Claude accepts numeric strings");
ExpectEqual(weeklyClaude.Plan, "team", "Partial Claude usage preserves the fallback plan");
var zeroClaude = UsageParser.ParseClaudeUsage("""{"five_hour":{"utilization":0},"seven_day":null}""");
ExpectEqual(zeroClaude.RemainingPercent5h, 100, "Zero usage is a valid Claude measurement");
var boundedClaude = UsageParser.ParseClaudeUsage("""{"five_hour":{"utilization":1e100},"seven_day":{"utilization":-1e100}}""");
ExpectEqual(boundedClaude.RemainingPercent5h, 0, "Large finite utilization is clamped before conversion");
ExpectEqual(boundedClaude.RemainingPercent7d, 100, "Negative utilization is clamped before conversion");

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
    "accessToken": "claude-token",
    "subscriptionType": "max"
  }
}
""");

// The Claude fetch falls back to the status-line bridge file when the API path
// yields nothing. Point these tests at a path that does not exist, so a machine
// with the bridge installed answers them the same way a bare one does.
var noStatusLine = Path.Combine(home, "absent-statusline.json");

var credentials = new CredentialReader();
var codexAuth = credentials.ReadCodexAuth(home);
ExpectEqual(codexAuth.AccessToken, "codex-token", "Codex access token read");
ExpectEqual(codexAuth.AccountId, "account-id", "Codex account id read");
ExpectEqual(credentials.ReadClaudeAccessToken(home), "claude-token", "Claude access token read");
ExpectEqual(credentials.ReadClaudeCredential(home).Plan, "max", "Claude credential plan read");

using (var malformedHandler = new QueueHttpMessageHandler(
    new HttpResponseMessage(HttpStatusCode.OK) { Content = new StringContent("{}") },
    new HttpResponseMessage(HttpStatusCode.OK) { Content = new StringContent(claudeJson) }))
using (var malformedHttp = new HttpClient(malformedHandler))
{
    var client = new UsageClient(malformedHttp, homeDirectory: home,
        rateLimitStatePath: Path.Combine(home, "malformed-cooldown.json"),
        claudeStatusLinePath: noStatusLine);
    var malformed = await client.FetchClaudeAsync();
    ExpectEqual(malformed.Source, UsageSource.Unavailable, "Malformed HTTP 200 is not marked as an API success");
    ExpectEqual(malformed.Error, "Invalid response", "Malformed HTTP 200 reports its cause");
    var recovered = await client.FetchClaudeAsync();
    ExpectEqual(recovered.Source, UsageSource.Api, "A valid response recovers after a malformed response");
    ExpectEqual(malformedHandler.CallCount, 2, "Malformed data does not create a rate-limit cooldown");
}

var rateLimitStatePath = Path.Combine(Path.GetTempPath(), $"tt-rate-limit-{Guid.NewGuid():N}.json");
try
{
    var rateLimitedResponse = new HttpResponseMessage(HttpStatusCode.TooManyRequests);
    rateLimitedResponse.Headers.TryAddWithoutValidation("Retry-After", "300");
    var rateLimitedHandler = new QueueHttpMessageHandler(rateLimitedResponse);
    var rateLimitedClient = new UsageClient(new HttpClient(rateLimitedHandler), new CredentialReader(), home, rateLimitStatePath, claudeStatusLinePath: noStatusLine);
    var firstRateLimit = await rateLimitedClient.FetchClaudeAsync();
    ExpectEqual(firstRateLimit.Source, UsageSource.Unavailable, "Claude 429 is unavailable");
    Expect(firstRateLimit.Error?.StartsWith("HTTP 429 from Claude API; retrying after") == true, "Claude 429 error includes retry delay");
    ExpectEqual(rateLimitedHandler.CallCount, 1, "Claude 429 first call reaches HTTP");
    var skippedDuringBackoff = await rateLimitedClient.FetchClaudeAsync();
    ExpectEqual(skippedDuringBackoff.Source, UsageSource.Unavailable, "Claude backoff returns unavailable");
    Expect(skippedDuringBackoff.Error?.StartsWith("HTTP 429 from Claude API; retrying after") == true, "Claude backoff error includes retry delay");
    ExpectEqual(rateLimitedHandler.CallCount, 1, "Claude backoff skips HTTP");

    // The cooldown must survive an app restart: a brand-new client reading the
    // same state file honors the outstanding cooldown without touching HTTP.
    Expect(File.Exists(rateLimitStatePath), "Claude 429 cooldown is persisted to disk");
    Expect(
        File.ReadAllText(rateLimitStatePath).Contains("\"FailureCount\":1", StringComparison.Ordinal),
        "Claude 429 persists the failure count for exponential backoff");
    var restartHandler = new QueueHttpMessageHandler(new HttpResponseMessage(HttpStatusCode.OK) { Content = new StringContent("{}") });
    var restartedClient = new UsageClient(new HttpClient(restartHandler), new CredentialReader(), home, rateLimitStatePath, claudeStatusLinePath: noStatusLine);
    var afterRestart = await restartedClient.FetchClaudeAsync();
    ExpectEqual(afterRestart.Source, UsageSource.Unavailable, "Claude cooldown survives restart");
    Expect(afterRestart.Error?.StartsWith("HTTP 429 from Claude API; retrying after") == true, "Restarted client reports persisted cooldown");
    ExpectEqual(restartHandler.CallCount, 0, "Restarted client honors persisted cooldown without HTTP");

    // A cooldown persisted by a build that stored no fingerprint cannot be shown
    // to belong to the current token, so it is dropped rather than waited out.
    File.WriteAllText(
        rateLimitStatePath,
        "{\"RetryAllowedAt\":\"" + DateTimeOffset.Now.AddMinutes(30).ToString("O") + "\",\"FailureCount\":40}");
    var legacyHandler = new QueueHttpMessageHandler(new HttpResponseMessage(HttpStatusCode.OK)
    {
        Content = new StringContent("""
        { "five_hour": { "utilization": 5.0 }, "seven_day": { "utilization": 5.0 } }
        """)
    });
    var legacyClient = new UsageClient(new HttpClient(legacyHandler), new CredentialReader(), home, rateLimitStatePath, claudeStatusLinePath: noStatusLine);
    var afterLegacy = await legacyClient.FetchClaudeAsync();
    ExpectEqual(legacyHandler.CallCount, 1, "A fingerprint-less cooldown is dropped instead of blocking the current token");
    ExpectEqual(afterLegacy.RemainingPercent5h, 95, "Dropping an unattributable cooldown loads usage again");

    // Restore a fingerprinted cooldown for the re-login case below.
    var reBackoffResponse = new HttpResponseMessage(HttpStatusCode.TooManyRequests);
    reBackoffResponse.Headers.TryAddWithoutValidation("Retry-After", "300");
    var reBackoffClient = new UsageClient(
        new HttpClient(new QueueHttpMessageHandler(reBackoffResponse)), new CredentialReader(), home, rateLimitStatePath,
        claudeStatusLinePath: noStatusLine);
    await reBackoffClient.FetchClaudeAsync();

    // Signing in again has to take effect immediately: a cooldown earned by the
    // previous token must not keep blocking refreshes for the new one.
    File.WriteAllText(Path.Combine(home, ".claude", ".credentials.json"), """
    {
      "claudeAiOauth": {
        "accessToken": "claude-token-after-relogin",
        "subscriptionType": "max"
      }
    }
    """);
    var reloginHandler = new QueueHttpMessageHandler(new HttpResponseMessage(HttpStatusCode.OK)
    {
        Content = new StringContent("""
        { "five_hour": { "utilization": 10.0 }, "seven_day": { "utilization": 20.0 } }
        """)
    });
    var reloginClient = new UsageClient(new HttpClient(reloginHandler), new CredentialReader(), home, rateLimitStatePath, claudeStatusLinePath: noStatusLine);
    var afterRelogin = await reloginClient.FetchClaudeAsync();
    ExpectEqual(reloginHandler.CallCount, 1, "New credentials retry immediately instead of waiting out the old cooldown");
    ExpectEqual(afterRelogin.RemainingPercent5h, 90, "New credentials load usage again");

    // An expired token is reported as such without spending a request on it.
    var expiredAtMilliseconds = DateTimeOffset.UtcNow.AddHours(-1).ToUnixTimeMilliseconds();
    File.WriteAllText(
        Path.Combine(home, ".claude", ".credentials.json"),
        "{\"claudeAiOauth\":{\"accessToken\":\"claude-token-expired\",\"subscriptionType\":\"max\"," +
        "\"expiresAt\":" + expiredAtMilliseconds + "}}");
    var expiredHandler = new QueueHttpMessageHandler(new HttpResponseMessage(HttpStatusCode.Unauthorized));
    var expiredClient = new UsageClient(new HttpClient(expiredHandler), new CredentialReader(), home, rateLimitStatePath, claudeStatusLinePath: noStatusLine);
    var expiredResult = await expiredClient.FetchClaudeAsync();
    ExpectEqual(expiredHandler.CallCount, 0, "An expired token is not spent on a request");
    Expect(
        expiredResult.Error?.StartsWith("Credentials expired for Claude API") == true,
        "An expired token reports the real cause instead of an HTTP code");
    ExpectEqual(
        UsageIssueFormatter.Kind(expiredResult.Error!),
        UsageIssueKind.ExpiredCredentials,
        "An expired token is classified as needing a new sign-in");
}
finally
{
    if (File.Exists(rateLimitStatePath))
    {
        File.Delete(rateLimitStatePath);
    }
    Directory.Delete(home, recursive: true);
}

Expect(
    AppPaths.ClaudeRateLimitStatePath != AppPaths.CodexRateLimitStatePath,
    "Each provider holds its own cooldown file");

var codexHome = Path.Combine(Path.GetTempPath(), "token-tracker-codex-tests-" + Guid.NewGuid().ToString("N"));
var codexStatePath = Path.Combine(Path.GetTempPath(), $"tt-codex-rate-limit-{Guid.NewGuid():N}.json");
Directory.CreateDirectory(Path.Combine(codexHome, ".codex"));
File.WriteAllText(Path.Combine(codexHome, ".codex", "auth.json"), """
{
  "tokens": { "access_token": "codex-token", "account_id": "account-id" }
}
""");
try
{
    var codexLimited = new HttpResponseMessage(HttpStatusCode.TooManyRequests);
    codexLimited.Headers.TryAddWithoutValidation("Retry-After", "300");
    var codexHandler = new QueueHttpMessageHandler(codexLimited);
    var codexClient = new UsageClient(
        new HttpClient(codexHandler), new CredentialReader(), codexHome, null, codexStatePath);

    var firstCodex = await codexClient.FetchCodexAsync();
    Expect(firstCodex.Error?.StartsWith("HTTP 429 from Codex API; retrying after") == true, "Codex 429 reports the retry delay");
    ExpectEqual(codexHandler.CallCount, 1, "Codex 429 first call reaches HTTP");

    // The point of the fix: the next poll must not walk straight back into the limit.
    var secondCodex = await codexClient.FetchCodexAsync();
    ExpectEqual(codexHandler.CallCount, 1, "Codex honors its cooldown instead of re-firing every refresh");
    Expect(secondCodex.Error?.StartsWith("HTTP 429 from Codex API; retrying after") == true, "Codex backoff reports the retry delay");
    Expect(File.Exists(codexStatePath), "Codex cooldown is persisted to its own file");
}
finally
{
    if (File.Exists(codexStatePath)) File.Delete(codexStatePath);
    Directory.Delete(codexHome, recursive: true);
}

// History records measurements, not re-displays of one: a cached reading repeats a
// value the provider never re-reported, which would flatten the sparkline, zero the
// trend delta and tell the forecast that usage stopped moving.
var cachedReading = Usage(Provider.Claude, 63, 80, now) with { Source = UsageSource.StaleCache };
var recorded = UsageHistoryPolicy.MeasurementsOnly(
    new UsageSnapshot(cachedReading, Usage(Provider.Codex, 91, 99, now), now));
Expect(recorded.Claude.RemainingPercent5h is null, "A cached reading contributes no 5h measurement");
Expect(recorded.Claude.RemainingPercent7d is null, "A cached reading contributes no 7d measurement");
ExpectEqual(recorded.Codex.RemainingPercent5h, 91, "A live reading is recorded unchanged");
ExpectEqual(recorded.Claude.Source, UsageSource.StaleCache, "Clearing the value keeps the reason it was cleared");

// The oldest entry in the window recorded no Claude measurement. A shared baseline
// would land on it and drop Claude's delta; per-provider baselines skip past it.
var trendGapEntry = new UsageHistoryEntry(
    now.AddHours(-2),
    UsageHistoryPolicy.MeasurementsOnly(
        new UsageSnapshot(cachedReading, Usage(Provider.Codex, 91, 99, now), now.AddHours(-2))));
var trendBaselineEntry = new UsageHistoryEntry(
    now.AddHours(-1),
    new UsageSnapshot(Usage(Provider.Claude, 90, 95, now), Usage(Provider.Codex, 91, 99, now), now.AddHours(-1)));
var perProviderTrend = UsageHistoryFormatter.TrendSummary(
    new[] { trendGapEntry, trendBaselineEntry },
    new UsageSnapshot(Usage(Provider.Claude, 63, 80, now), Usage(Provider.Codex, 91, 99, now), now));
Expect(
    perProviderTrend.Contains("Claude 5h -27", StringComparison.Ordinal),
    "Claude's delta survives an older entry that recorded no Claude measurement");

var staleSnapshot = new UsageSnapshot(
    Claude: Usage(Provider.Claude, 63, 80, now),
    Codex: Usage(Provider.Codex, 91, 99, now),
    UpdatedAt: now);
var freshFailure = new UsageSnapshot(
    Claude: ProviderUsage.Unavailable(Provider.Claude, "HTTP 429 from Claude API"),
    Codex: Usage(Provider.Codex, 88, 97, now),
    UpdatedAt: now);
var staleApplied = UsageSnapshotCachePolicy.Apply(freshFailure, staleSnapshot, updatedAt: now.AddMinutes(1));
ExpectEqual(staleApplied.Claude.Source, UsageSource.StaleCache, "Claude stale cache source");
ExpectEqual(staleApplied.Claude.RemainingPercent5h, 63, "Claude stale cache percent");
ExpectEqual(staleApplied.Claude.Error, "HTTP 429 from Claude API", "Claude stale cache preserves fresh error");
ExpectEqual(staleApplied.Codex.Source, UsageSource.Api, "Fresh Codex remains API source");
ExpectEqual(staleApplied.Claude.UpdatedAt, staleSnapshot.Claude.UpdatedAt, "Cached data retains its measurement time");
var repeatedlyCached = staleSnapshot;
for (var hour = 1; hour <= 13; hour++)
{
    var pollAt = now.AddHours(hour);
    var failedPoll = freshFailure with { Codex = Usage(Provider.Codex, 88, 97, pollAt), UpdatedAt = pollAt };
    repeatedlyCached = UsageSnapshotCachePolicy.Apply(failedPoll, repeatedlyCached, updatedAt: pollAt);
    ExpectEqual(repeatedlyCached.Claude.Source, hour <= 12 ? UsageSource.StaleCache : UsageSource.Unavailable,
        "Repeated failures cannot extend the twelve-hour lifetime");
    if (hour <= 12)
        ExpectEqual(repeatedlyCached.Claude.UpdatedAt, now, "Repeated failures preserve the original measurement time");
    ExpectEqual(repeatedlyCached.Codex, failedPoll.Codex, "Fresh Codex data does not extend Claude's lifetime");
}
var staggered = new UsageSnapshot(
    Usage(Provider.Claude, 63, 80, now.AddHours(-2)),
    Usage(Provider.Codex, 91, 99, now.AddMinutes(-30)), now);
var bothFailed = freshFailure with { Codex = ProviderUsage.Unavailable(Provider.Codex, "offline") };
var shortTolerance = UsageSnapshotCachePolicy.Apply(bothFailed, staggered, updatedAt: now, maxAge: TimeSpan.FromHours(1));
ExpectEqual(shortTolerance.Claude.Source, UsageSource.Unavailable, "Custom tolerance expires Claude independently");
ExpectEqual(shortTolerance.Codex.Source, UsageSource.StaleCache, "Custom tolerance keeps recent Codex data");
var longTolerance = UsageSnapshotCachePolicy.Apply(bothFailed, staggered, updatedAt: now, maxAge: TimeSpan.FromHours(48));
ExpectEqual(longTolerance.Claude.Source, UsageSource.StaleCache, "Longer configured tolerance is honored");
var cachedIssue = UsageIssueFormatter.Issue(staleApplied.Claude);
ExpectEqual(cachedIssue.Kind, UsageIssueKind.UsingCachedData, "Stale cache issue is classified");
ExpectEqual(cachedIssue.TechnicalDetail, "HTTP 429 from Claude API", "Stale cache keeps technical detail");
ExpectEqual(UsageIssueFormatter.Kind("Disabled"), UsageIssueKind.Disabled, "Disabled issue is classified");
ExpectEqual(UsageIssueFormatter.Kind("HTTP 429 from Claude API; retrying after 5m"), UsageIssueKind.RateLimited, "429 issue is classified");
ExpectEqual(UsageIssueFormatter.Kind("Missing credentials"), UsageIssueKind.MissingCredentials, "Missing credentials issue is classified");
ExpectEqual(UsageIssueFormatter.Kind("Credentials expired for Codex API"), UsageIssueKind.ExpiredCredentials, "Expired token issue is classified");
ExpectEqual(UsageIssueFormatter.Kind("HTTP 401 from Claude API"), UsageIssueKind.ExpiredCredentials, "401 is reported as an expired sign-in, not a bare HTTP error");
ExpectEqual(UsageIssueFormatter.Kind("HTTP 403 from Codex API"), UsageIssueKind.ExpiredCredentials, "403 is reported as an expired sign-in");
ExpectEqual(UsageIssueFormatter.Kind("HTTP 500 from Claude API"), UsageIssueKind.HttpStatus, "Other HTTP codes stay generic HTTP errors");
var codexRecovery = UsageIssueFormatter.Issue(ProviderUsage.Unavailable(Provider.Codex, "Credentials expired for Codex API")).Recovery;
Expect(codexRecovery?.Contains("codex login") == true, "Codex recovery names the Codex sign-in command");
Expect(codexRecovery?.Contains("/login") == false, "Codex recovery does not make the user read past Claude's command");
var claudeRecovery = UsageIssueFormatter.Issue(ProviderUsage.Unavailable(Provider.Claude, "HTTP 401 from Claude API")).Recovery;
Expect(claudeRecovery?.Contains("/login") == true, "Claude recovery names the Claude sign-in command");
Expect(claudeRecovery?.Contains("codex login") == false, "Claude recovery does not mention Codex");

// Credential expiry: the app reads tokens the provider CLIs refresh, so it has to
// recognize a lapsed one locally instead of spending a request to be told 401.
Expect(!CredentialExpiry.IsExpired(null), "An unknown expiry is not treated as expired");
Expect(!CredentialExpiry.IsExpired(DateTimeOffset.Now.AddHours(1)), "A token valid for an hour is usable");
Expect(CredentialExpiry.IsExpired(DateTimeOffset.Now.AddSeconds(-1)), "A lapsed token is expired");
Expect(
    CredentialExpiry.IsExpired(DateTimeOffset.Now.Add(CredentialExpiry.Skew / 2)),
    "A token inside the skew window is expired early rather than lapsing mid-request");
// {"alg":"none"} . {"exp":1770000000}
ExpectEqual(
    CredentialExpiry.JwtExpiry("eyJhbGciOiJub25lIn0.eyJleHAiOjE3NzAwMDAwMDB9.sig"),
    DateTimeOffset.FromUnixTimeSeconds(1_770_000_000),
    "The exp claim is read out of a JWT access token");
Expect(CredentialExpiry.JwtExpiry("not-a-jwt") is null, "A non-JWT token has no readable expiry");
ExpectEqual(TokenFingerprint.Of("a"), TokenFingerprint.Of("a"), "The same token fingerprints the same");
Expect(TokenFingerprint.Of("a") != TokenFingerprint.Of("b"), "Signing in again changes the fingerprint");
ExpectEqual(UsageIssueFormatter.Kind("Timed out contacting Claude API"), UsageIssueKind.TimedOut, "Timeout issue is classified");

var disabledStale = UsageSnapshotCachePolicy.Apply(freshFailure, staleSnapshot, claudeEnabled: false, updatedAt: now.AddMinutes(1));
ExpectEqual(disabledStale.Claude.Source, UsageSource.Unavailable, "Disabled Claude does not use stale cache");

var alertSnapshot = new UsageSnapshot(
    Claude: new ProviderUsage(
        Provider.Claude,
        RemainingPercent5h: 19,
        RemainingPercent7d: 9,
        ResetAt5h: now.AddMinutes(5),
        ResetAt7d: now.AddHours(2),
        UsageSource.Api,
        Error: null,
        Plan: null,
        Model: null,
        UpdatedAt: now),
    Codex: Usage(Provider.Codex, 80, 90, now),
    UpdatedAt: now);
var alerts = UsageAlertEvaluator.Candidates(
    alertSnapshot,
    new UsageAlertSettings(true, 20, 10, 10),
    now);
ExpectEqual(
    string.Join(",", alerts.Select(alert => alert.Id)),
    $"claude-5h-low,claude-7d-low,claude-5h-reset-{now.AddMinutes(5).ToUnixTimeSeconds()}",
    "Alert evaluator emits low usage and reset alerts");
ExpectEqual(
    UsageAlertEvaluator.Candidates(alertSnapshot, new UsageAlertSettings(false, 20, 10, 10), now).Count,
    0,
    "Disabled notifications emit no alerts");

var cachePath = Path.Combine(Path.GetTempPath(), "token-tracker-cache-" + Guid.NewGuid().ToString("N"), "usage-cache.json");
var cacheStore = new CacheStore(cachePath);
// CacheStore.Load compares UpdatedAt against the real wall clock, so save a
// snapshot stamped at the current time rather than the fixed test `now`
// (otherwise this assertion becomes a date-bomb once real time drifts past it).
cacheStore.Save(staleSnapshot with { UpdatedAt = DateTimeOffset.Now });
var loadedSnapshot = cacheStore.Load(TimeSpan.FromHours(1));
Expect(loadedSnapshot is not null, "Cache loads saved snapshot");
ExpectEqual(loadedSnapshot!.Claude.RemainingPercent5h, 63, "Cache preserves Claude percent");
var cacheNow = DateTimeOffset.Now;
var oldReading = new UsageSnapshot(
    Usage(Provider.Claude, 63, 80, cacheNow.AddHours(-13)),
    Usage(Provider.Codex, 91, 99, cacheNow.AddHours(-13)), cacheNow.AddHours(-13));
var firstFailedPoll = bothFailed with { UpdatedAt = cacheNow.AddHours(-3) };
cacheStore.Save(UsageSnapshotCachePolicy.Apply(firstFailedPoll, oldReading, updatedAt: firstFailedPoll.UpdatedAt));
var persistedStale = cacheStore.Load(TimeSpan.FromHours(12));
Expect(persistedStale is not null, "Recent poll snapshot survives a restart");
ExpectEqual(persistedStale!.Claude.UpdatedAt, oldReading.Claude.UpdatedAt, "Disk cache preserves the original measurement time");
var afterRestartFailure = UsageSnapshotCachePolicy.Apply(bothFailed, persistedStale, updatedAt: cacheNow);
ExpectEqual(afterRestartFailure.Claude.Source, UsageSource.Unavailable, "Restart does not revive an expired Claude measurement");
ExpectEqual(afterRestartFailure.Codex.Source, UsageSource.Unavailable, "Restart does not revive an expired Codex measurement");
File.WriteAllText(cachePath, System.Text.Json.JsonSerializer.Serialize(staleSnapshot with { UpdatedAt = cacheNow }));
Expect(cacheStore.Load(TimeSpan.FromHours(12)) is null, "Legacy caches have untrustworthy timestamps and are discarded");
Directory.Delete(Path.GetDirectoryName(cachePath)!, recursive: true);

var historyPath = Path.Combine(Path.GetTempPath(), "token-tracker-history-" + Guid.NewGuid().ToString("N"), "usage-history.json");
var historyStore = new UsageHistoryStore(historyPath);
historyStore.Append(staleSnapshot, retentionDays: 7, now);
historyStore.Append(snapshot, retentionDays: 7, now.AddHours(1));
var historyEntries = historyStore.Load();
ExpectEqual(historyEntries.Count, 2, "History preserves entries outside merge window");
var trend = UsageHistoryFormatter.TrendSummary(
    historyEntries,
    snapshot,
    TimeSpan.FromDays(1),
    new Localizer(AppLanguage.English));
ExpectEqual(trend, "24h trend: Claude 5h 0% 7d 0% Codex 5h 0% 7d 0%", "History trend summarizes 5h and 7d provider deltas");

var missingSevenDayBaseline = new UsageSnapshot(
    Claude: Usage(Provider.Claude, 40, null, now),
    Codex: Usage(Provider.Codex, 90, 99, now),
    UpdatedAt: now);
var missingSevenDayTrend = UsageHistoryFormatter.TrendSummary(
    new[] { new UsageHistoryEntry(now, missingSevenDayBaseline) },
    snapshot,
    TimeSpan.FromDays(1),
    new Localizer(AppLanguage.English));
ExpectEqual(missingSevenDayTrend, "24h trend: Claude 5h +23% 7d -- Codex 5h +1% 7d 0%", "History trend shows -- when a 7d value is missing");
var csv = historyStore.CsvString();
Expect(csv.Contains("recorded_at,provider,remaining_5h", StringComparison.Ordinal), "History CSV includes header");
Expect(csv.Contains("claude,63,80", StringComparison.Ordinal), "History CSV includes Claude row");
Directory.Delete(Path.GetDirectoryName(historyPath)!, recursive: true);

var korean = new Localizer(AppLanguage.Korean);
ExpectEqual(korean.Text(L10nKey.RefreshNow), "지금 새로고침", "Korean refresh label");
ExpectEqual(korean.Text(L10nKey.ClaudeOnly), "Claude만", "Korean Claude-only label");
ExpectEqual(korean.Text(L10nKey.Diagnostics), "진단", "Korean diagnostics label");

var settingsPath = Path.Combine(Path.GetTempPath(), "token-tracker-settings-" + Guid.NewGuid().ToString("N"), "settings.json");
var settingsStore = new SettingsStore(settingsPath);
settingsStore.Save(new AppSettings
{
    Language = AppLanguage.Korean,
    DisplayMode = DisplayMode.ClaudeOnly,
    NotificationsEnabled = true,
    FiveHourAlertThreshold = 25,
    HistoryRetentionDays = 30
});
var loadedSettings = settingsStore.Load();
ExpectEqual(loadedSettings.Language, AppLanguage.Korean, "Language setting persists");
ExpectEqual(loadedSettings.DisplayMode, DisplayMode.ClaudeOnly, "Display mode setting persists");
ExpectEqual(loadedSettings.NotificationsEnabled, true, "Notification setting persists");
ExpectEqual(loadedSettings.FiveHourAlertThreshold, 25, "Alert threshold persists");
ExpectEqual(loadedSettings.HistoryRetentionDays, 30, "History retention persists");
Directory.Delete(Path.GetDirectoryName(settingsPath)!, recursive: true);

ExpectEqual(RateLimitBackoff.Cooldown(TimeSpan.FromSeconds(300), 0, 0).TotalSeconds, 300.0, "First headerless 429 waits the 300s default");
ExpectEqual(RateLimitBackoff.Cooldown(TimeSpan.Zero, 0, 0).TotalSeconds, 120.0, "Absent Retry-After falls back to the 120s minimum");
ExpectEqual(RateLimitBackoff.Cooldown(TimeSpan.FromSeconds(300), 2, 0).TotalSeconds, 1200.0, "Repeated 429 escalates exponentially");
ExpectEqual(RateLimitBackoff.Cooldown(TimeSpan.FromSeconds(300), 5, 0).TotalSeconds, 1800.0, "Escalation is capped at 30m");
ExpectEqual(RateLimitBackoff.Cooldown(TimeSpan.FromSeconds(3600), 0, 0).TotalSeconds, 3600.0, "An explicit longer Retry-After is honored above the cap");
var jitteredCooldown = RateLimitBackoff.Cooldown(TimeSpan.FromSeconds(300), 0, RateLimitBackoff.JitterFraction).TotalSeconds;
Expect(jitteredCooldown > 300.0 && jitteredCooldown <= 360.0, "Jitter adds up to 20 percent on top of the base cooldown");

var legacyIntervalPath = Path.Combine(Path.GetTempPath(), "token-tracker-settings-" + Guid.NewGuid().ToString("N"), "settings.json");
var legacyIntervalStore = new SettingsStore(legacyIntervalPath);
legacyIntervalStore.Save(new AppSettings { RefreshIntervalSeconds = 30 });
ExpectEqual(legacyIntervalStore.Load().RefreshIntervalSeconds, 60, "Legacy sub-60 refresh interval migrates to the 60s floor");
legacyIntervalStore.Save(new AppSettings { RefreshIntervalSeconds = 300 });
ExpectEqual(legacyIntervalStore.Load().RefreshIntervalSeconds, 300, "Valid refresh interval is left unchanged");
Directory.Delete(Path.GetDirectoryName(legacyIntervalPath)!, recursive: true);

// Usage forecast
UsageHistoryEntry ForecastEntry(double secondsAgo, int? claude5h, int? claude7d = 100)
{
    var at = now.AddSeconds(-secondsAgo);
    return new UsageHistoryEntry(at, new UsageSnapshot(
        Usage(Provider.Claude, claude5h, claude7d, at),
        Usage(Provider.Codex, 100, 100, at),
        at));
}

var steadyEntries = new[] { ForecastEntry(3600, 60), ForecastEntry(1800, 50), ForecastEntry(0, 40) };
var steadyForecast = UsageForecaster.Forecast(steadyEntries, Provider.Claude, ForecastWindow.FiveHour, now.AddHours(3), now);
Expect(steadyForecast is not null, "Forecast is produced for a steady decline");
ExpectEqual((int)steadyForecast!.BurnPerHour, 20, "Burn rate is 20%/h");
ExpectEqual((int)steadyForecast.SecondsToEmpty, 7200, "5h window empties in 2h at the observed rate");
Expect(steadyForecast.WillEmptyBeforeReset, "Empties before a 3h reset");

var earlyResetForecast = UsageForecaster.Forecast(steadyEntries, Provider.Claude, ForecastWindow.FiveHour, now.AddHours(1), now);
Expect(!earlyResetForecast!.WillEmptyBeforeReset, "Does not empty before an earlier reset");

var resetEntries = new[] { ForecastEntry(3600, 30), ForecastEntry(1800, 80), ForecastEntry(900, 70), ForecastEntry(0, 60) };
var resetForecast = UsageForecaster.Forecast(resetEntries, Provider.Claude, ForecastWindow.FiveHour, null, now);
ExpectEqual((int)resetForecast!.SecondsToEmpty, 5400, "Forecast uses only the post-reset segment");
ExpectEqual((int)resetForecast.BurnPerHour, 40, "Post-reset burn rate is 40%/h");

Expect(UsageForecaster.Forecast(new[] { ForecastEntry(3600, 40), ForecastEntry(0, 50) }, Provider.Claude, ForecastWindow.FiveHour, null, now) is null, "No forecast while replenishing");
Expect(UsageForecaster.Forecast(new[] { ForecastEntry(300, 60), ForecastEntry(0, 50) }, Provider.Claude, ForecastWindow.FiveHour, null, now) is null, "No forecast under the minimum span");
Expect(UsageForecaster.Forecast(new[] { ForecastEntry(10800, 60), ForecastEntry(7200, 40) }, Provider.Claude, ForecastWindow.FiveHour, null, now) is null, "No forecast when the newest sample is stale");

ExpectEqual(UsageForecaster.DurationText(7800), "2h 10m", "Duration formats hours and minutes");
ExpectEqual(UsageForecaster.DurationText(2700), "45m", "Duration formats minutes");
ExpectEqual(UsageForecaster.DurationText(30), "<1m", "Sub-minute duration collapses to <1m");
ExpectEqual(UsageForecaster.DurationText(86400), "1d 0h", "One-day duration switches to days");
ExpectEqual(UsageForecaster.DurationText(273000), "3d 3h", "Duration formats days and hours");

var forecastLocalizer = new Localizer(AppLanguage.English);
ExpectEqual(
    UsageForecastText.MenuLine(steadyForecast, ForecastWindow.FiveHour, forecastLocalizer),
    "Projected depletion: ~2h 0m · empties before reset",
    "5h forecast menu line format is unchanged");
ExpectEqual(
    UsageForecastText.MenuLine(steadyForecast, ForecastWindow.SevenDay, forecastLocalizer),
    "Projected depletion: ~2h 0m (7d) · empties before reset",
    "7d fallback forecast line carries the window marker");
Expect(UsageForecastText.MenuLine(null, ForecastWindow.SevenDay, forecastLocalizer) is null, "No forecast menu line without a forecast");

var forecastAlertInput = new ForecastAlertInput(Provider.Claude, ForecastWindow.FiveHour, steadyForecast, now.AddHours(3));
ExpectEqual(
    string.Join(",", UsageForecastAlert.Candidates(new[] { forecastAlertInput }, enabled: true).Select(candidate => candidate.Id)),
    $"claude-5h-empty-before-reset-{now.AddHours(3).ToUnixTimeSeconds()}",
    "Forecast alert fires when depletion precedes reset");
ExpectEqual(UsageForecastAlert.Candidates(new[] { forecastAlertInput }, enabled: false).Count, 0, "Forecast alert suppressed when disabled");
var safeForecastInput = new ForecastAlertInput(Provider.Claude, ForecastWindow.FiveHour, earlyResetForecast, now.AddHours(1));
ExpectEqual(UsageForecastAlert.Candidates(new[] { safeForecastInput }, enabled: true).Count, 0, "No forecast alert when the reset comes first");

// Sparkline
ExpectEqual(SparklineText.Render(new[] { 0, 25, 50, 75, 100 }), "▁▃▅▇█", "Sparkline maps values across the eight blocks");
ExpectEqual(SparklineText.Render(new[] { 42 }), "", "A single point renders nothing");
ExpectEqual(SparklineText.Render(Array.Empty<int>()), "", "An empty series renders nothing");
var sparkEntries = new[] { ForecastEntry(3600, 100), ForecastEntry(1800, 50), ForecastEntry(0, 0) };
ExpectEqual(string.Join(",", SparklineSeries.Build(sparkEntries, Provider.Claude, ForecastWindow.FiveHour)), "100,50,0", "Sparkline series extracts remaining values in time order");
ExpectEqual(SparklineText.Render(SparklineSeries.Build(sparkEntries, Provider.Claude, ForecastWindow.FiveHour)), "█▅▁", "End-to-end sparkline render");
var manySparkEntries = Enumerable.Range(0, 40).Select(i => ForecastEntry((40 - i) * 60, 100)).ToArray();
ExpectEqual(SparklineSeries.Build(manySparkEntries, Provider.Claude, ForecastWindow.FiveHour, 20).Count, 20, "Sparkline series is downsampled to maxPoints");

// Pause controller
var pauseNow = now;
Expect(PauseController.IsPaused(pauseNow.AddHours(1), pauseNow), "Paused while the resume instant is in the future");
Expect(!PauseController.IsPaused(pauseNow.AddSeconds(-10), pauseNow), "Not paused once the resume instant has passed");
Expect(!PauseController.IsPaused(null, pauseNow), "Not paused when unset");
ExpectEqual((int)PauseController.Remaining(pauseNow.AddMinutes(30), pauseNow).TotalSeconds, 1800, "Remaining reports seconds until resume");
ExpectEqual((int)PauseController.Remaining(null, pauseNow).TotalSeconds, 0, "Remaining is zero when not paused");
Expect(PauseController.IsIndefinite(DateTimeOffset.MaxValue, pauseNow), "A max-value pause is indefinite");
Expect(!PauseController.IsIndefinite(pauseNow.AddHours(1), pauseNow), "A timed pause is not indefinite");

var pausePath = Path.Combine(Path.GetTempPath(), "token-tracker-settings-" + Guid.NewGuid().ToString("N"), "settings.json");
var pauseStore = new SettingsStore(pausePath);
pauseStore.Save(new AppSettings { PollPausedUntil = pauseNow.AddHours(2) });
var reloadedPause = pauseStore.Load().PollPausedUntil;
Expect(reloadedPause is not null && reloadedPause.Value.ToUnixTimeSeconds() == pauseNow.AddHours(2).ToUnixTimeSeconds(), "PollPausedUntil round-trips through the settings store");
Directory.Delete(Path.GetDirectoryName(pausePath)!, recursive: true);

// Which credential store is live, and how long since anything wrote to it. The old
// diagnostic only asked whether the file existed, which says nothing about the
// question that matters when usage stops loading: is anything still refreshing it?
var credentialFilePath = Path.Combine(Path.GetTempPath(), "token-tracker-credentials-" + Guid.NewGuid().ToString("N") + ".json");
File.WriteAllText(credentialFilePath, "{}");

var keychainWrittenAt = now.AddHours(-48);
var fromKeychain = ClaudeCredentialSource.Detect(credentialFilePath, keychainWrittenAt);
ExpectEqual(fromKeychain.Kind, ClaudeCredentialStore.Keychain, "The keychain wins over the fallback file when both are present");
ExpectEqual(fromKeychain.LastWrittenAt, keychainWrittenAt, "The keychain's write time is reported");
ExpectEqual(fromKeychain.Age(now)!.Value.TotalHours, 48d, "Age measures from the last write");

var fromFile = ClaudeCredentialSource.Detect(credentialFilePath);
ExpectEqual(fromFile.Kind, ClaudeCredentialStore.CredentialsFile, "Without a keychain entry the fallback file is the source");
Expect(fromFile.LastWrittenAt is not null, "The fallback file reports its write time");

var noCredentialSource = ClaudeCredentialSource.Detect(credentialFilePath + ".missing");
ExpectEqual(noCredentialSource.Kind, ClaudeCredentialStore.None, "No keychain entry and no file means no source");
Expect(noCredentialSource.Age(now) is null, "A source that was never written has no age");
File.Delete(credentialFilePath);

// A store nothing has written for longer than a token lives is the whole answer to
// "I signed in and it still says sign in", so the menu says how stale it is. Only for
// a lapsed Claude token: no other failure is explained by the store's age.
var abandonedStore = new ClaudeCredentialSource(ClaudeCredentialStore.Keychain, now);
var expiredCredentialIssue = CredentialIssue(Provider.Claude, "HTTP 401", UsageSource.Unavailable);
ExpectEqual(
    CredentialStoreAdvice.StaleLine(Provider.Claude, expiredCredentialIssue, abandonedStore, now.AddHours(48)),
    "Credentials not refreshed in 2d 0h",
    "A lapsed token over an abandoned store reports how long it has been abandoned");
Expect(
    CredentialStoreAdvice.StaleLine(Provider.Claude, expiredCredentialIssue, abandonedStore, now.Add(CredentialStoreAdvice.StaleAfter).AddMinutes(-1)) is null,
    "A store younger than the token life explains nothing the recovery does not already say");
Expect(
    CredentialStoreAdvice.StaleLine(Provider.Claude, CredentialIssue(Provider.Claude, "HTTP 429", UsageSource.Unavailable), abandonedStore, now.AddHours(48)) is null,
    "A rate limit is not a credential problem, however old the store is");
Expect(
    CredentialStoreAdvice.StaleLine(Provider.Codex, CredentialIssue(Provider.Codex, "HTTP 401", UsageSource.Unavailable), abandonedStore, now.AddHours(48)) is null,
    "The Claude store says nothing about Codex");
// The state this is actually seen in: the last good reading is being carried, so the
// visible status is "using cached data" and only the error names the expiry.
Expect(
    CredentialStoreAdvice.StaleLine(Provider.Claude, CredentialIssue(Provider.Claude, "credentials expired", UsageSource.StaleCache), abandonedStore, now.AddHours(48)) is not null,
    "A lapsed token behind a carried reading still reports the stale store");
Expect(
    CredentialStoreAdvice.StaleLine(Provider.Claude, expiredCredentialIssue, new ClaudeCredentialSource(ClaudeCredentialStore.None, null), now.AddHours(48)) is null,
    "A store that was never written has no age to report");

// The tray app's own version line. Until the publish started stamping it, every
// build ever shipped reported 1.0.0 — including the diagnostics report whose job is
// to say which build the user is on.
ExpectEqual(AppVersionText.Format(new Version(1, 1, 6, 8)), "1.1.6 (build 8)", "A stamped release publish names its build");
ExpectEqual(AppVersionText.Format(new Version(1, 1, 6, 0)), "1.1.6", "A local build leaves the revision unstamped and shows just the version");
ExpectEqual(AppVersionText.Format(new Version(1, 1, 6)), "1.1.6", "A three-part version has no build to show");
ExpectEqual(AppVersionText.Format(null), "unknown", "An assembly with no version is reported as unknown");

// The status-line bridge. Same truth table as the macOS smoke tests: a reading
// relayed from Claude Code's status line is account data, but it was measured at
// a time this app did not choose, so it is aged by its own measurement time and
// never by the moment the bridge last ran.
var statusLineNow = new DateTimeOffset(2026, 5, 27, 12, 0, 0, TimeSpan.Zero);
var statusLineReset5h = statusLineNow.AddHours(1);
var statusLineReset7d = statusLineNow.AddDays(1);

var statusLineRecord = ClaudeStatusLineBridge.Parse(
    StatusLinePayload(statusLineNow, statusLineNow, 23.5, statusLineReset5h, 41.2, statusLineReset7d),
    statusLineNow);
ExpectEqual(statusLineRecord?.MeasuredAt, statusLineNow, "The measurement time is read from the record");
var statusLineUsage = ClaudeStatusLineBridge.Usage(statusLineRecord, null, statusLineNow);
ExpectEqual(statusLineUsage?.Source, UsageSource.StatusLine, "A status-line reading is not labelled as an API measurement");
ExpectEqual(statusLineUsage?.RemainingPercent5h, 77, "23.5% used leaves 77% of the 5h window");
ExpectEqual(statusLineUsage?.RemainingPercent7d, 59, "41.2% used leaves 59% of the 7d window");
ExpectEqual(statusLineUsage?.ResetAt5h, statusLineReset5h, "The 5h reset instant carries through");
ExpectEqual(statusLineUsage?.ResetAt7d, statusLineReset7d, "The 7d reset instant carries through");
ExpectEqual(statusLineUsage?.UpdatedAt, statusLineNow, "The reading is stamped with the measurement time, not the poll time");

// Either window can be absent, and one window is enough.
var fiveHourOnly = ClaudeStatusLineBridge.Usage(
    ClaudeStatusLineBridge.Parse(
        StatusLinePayload(statusLineNow, statusLineNow, 23.5, statusLineReset5h, null, null),
        statusLineNow),
    null,
    statusLineNow);
ExpectEqual(fiveHourOnly?.RemainingPercent5h, 77, "A record with only the 5h window still reports it");
ExpectEqual(fiveHourOnly?.RemainingPercent7d, (int?)null, "An absent 7d window reports nothing rather than zero");
var sevenDayOnly = ClaudeStatusLineBridge.Usage(
    ClaudeStatusLineBridge.Parse(
        StatusLinePayload(statusLineNow, statusLineNow, null, null, 41.2, statusLineReset7d),
        statusLineNow),
    null,
    statusLineNow);
ExpectEqual(sevenDayOnly?.RemainingPercent7d, 59, "A record with only the 7d window still reports it");
Expect(
    ClaudeStatusLineBridge.Parse(
        StatusLinePayload(statusLineNow, statusLineNow, null, null, null, null),
        statusLineNow) is null,
    "A record with neither window is not a reading");

// Claude Code drops a window once its reset passes, so one still sitting in the
// file describes a window instance that no longer exists.
var expiredWindow = ClaudeStatusLineBridge.Parse(
    StatusLinePayload(statusLineNow, statusLineNow, 99, statusLineNow.AddSeconds(-1), 41.2, statusLineReset7d),
    statusLineNow);
ExpectEqual(expiredWindow?.UsedPercent5h, (double?)null, "A window whose reset has passed is dropped");
ExpectEqual(expiredWindow?.UsedPercent7d, 41.2, "Dropping one expired window keeps the other");

// A malformed or future record is not a reading. Ageing a measurement stamped in
// the future would make it look permanently fresh.
Expect(ClaudeStatusLineBridge.Parse("{", statusLineNow) is null, "Truncated JSON is not a reading");
Expect(
    ClaudeStatusLineBridge.Parse(
        StatusLinePayload(statusLineNow, statusLineNow, 23.5, statusLineReset5h, 41.2, statusLineReset7d, version: 2),
        statusLineNow) is null,
    "An unknown format version is not read");
Expect(
    ClaudeStatusLineBridge.Parse(
        StatusLinePayload(null, statusLineNow, 23.5, statusLineReset5h, 41.2, statusLineReset7d),
        statusLineNow) is null,
    "A record without a measurement time is not read");
Expect(
    ClaudeStatusLineBridge.Parse(
        StatusLinePayload(
            statusLineNow + ClaudeStatusLineBridge.ClockSkew + TimeSpan.FromMinutes(1),
            statusLineNow,
            23.5,
            statusLineReset5h,
            41.2,
            statusLineReset7d),
        statusLineNow) is null,
    "A measurement stamped in the future is not read");

// The trap this whole design exists to avoid: the status-line command re-runs on
// a timer, and a re-run is not a new measurement. written_at moves, so a reading
// aged by it would never expire; measured_at does not, so it does.
var replayed = ClaudeStatusLineBridge.Parse(
    StatusLinePayload(statusLineNow.AddHours(-2), statusLineNow, 23.5, statusLineReset5h, 41.2, statusLineReset7d),
    statusLineNow);
ExpectEqual(replayed?.WrittenAt, statusLineNow, "The replay time is recorded");
Expect(
    ClaudeStatusLineBridge.Usage(replayed, null, statusLineNow) is null,
    "Replaying an old measurement does not make it current");
var atFreshnessEdge = ClaudeStatusLineBridge.Parse(
    StatusLinePayload(
        statusLineNow - ClaudeStatusLineBridge.FreshnessWindow + TimeSpan.FromSeconds(1),
        statusLineNow,
        23.5,
        statusLineReset5h,
        41.2,
        statusLineReset7d),
    statusLineNow);
Expect(
    ClaudeStatusLineBridge.Usage(atFreshnessEdge, null, statusLineNow) is not null,
    "A measurement inside the freshness window is still current");

// A stale status-line reading hands over to the ordinary cache path rather than
// presenting itself as live: the last good value keeps showing, but labelled as
// cached, and it expires on the measurement's own clock.
var agedStatusLineReading = new ProviderUsage(
    Provider.Claude,
    77,
    59,
    statusLineReset5h,
    statusLineReset7d,
    UsageSource.StatusLine,
    Error: null,
    Plan: null,
    Model: null,
    UpdatedAt: statusLineNow.AddHours(-1));
var statusLineFailure = new UsageSnapshot(
    ProviderUsage.Unavailable(Provider.Claude, "Credentials expired for Claude API"),
    ProviderUsage.Unavailable(Provider.Codex, "Timed out"),
    statusLineNow);
var statusLineCache = new UsageSnapshot(
    agedStatusLineReading,
    ProviderUsage.Unavailable(Provider.Codex, "Timed out"),
    statusLineNow);
var carriedStatusLine = UsageSnapshotCachePolicy.Apply(
    statusLineFailure, statusLineCache, updatedAt: statusLineNow, maxAge: TimeSpan.FromHours(12));
ExpectEqual(carriedStatusLine.Claude.Source, UsageSource.StaleCache, "An aged-out status-line reading is carried as cached data");
ExpectEqual(carriedStatusLine.Claude.RemainingPercent5h, 77, "The last status-line value keeps showing while it is in tolerance");
ExpectEqual(carriedStatusLine.Claude.UpdatedAt, agedStatusLineReading.UpdatedAt, "Carrying it forward does not refresh its measurement time");
var droppedStatusLine = UsageSnapshotCachePolicy.Apply(
    statusLineFailure, statusLineCache, updatedAt: statusLineNow, maxAge: TimeSpan.FromMinutes(30));
ExpectEqual(droppedStatusLine.Claude.Source, UsageSource.Unavailable, "Past tolerance the status-line reading is gone, not frozen");

// History records measurements this app took and timestamps them with the poll it
// took them on. A status-line reading is re-read on every poll, so admitting it
// would append one measurement under a run of fresh timestamps and tell the
// forecast that usage had stopped moving.
var liveStatusLineReading = agedStatusLineReading with { UpdatedAt = statusLineNow };
var statusLineForHistory = UsageHistoryPolicy.MeasurementsOnly(new UsageSnapshot(
    liveStatusLineReading,
    ProviderUsage.Unavailable(Provider.Codex, "Timed out"),
    statusLineNow));
ExpectEqual(statusLineForHistory.Claude.RemainingPercent5h, (int?)null, "A status-line reading does not enter history");
ExpectEqual(statusLineForHistory.Claude.RemainingPercent7d, (int?)null, "A status-line reading does not enter the trend or forecast");

// The menu says where the number came from, and still names the fix for whatever
// stopped the API path.
var statusLineIssue = UsageIssueFormatter.Issue(
    liveStatusLineReading with { Error = "Credentials expired for Claude API" },
    new Localizer(AppLanguage.English));
ExpectEqual(statusLineIssue.Kind, UsageIssueKind.StatusLine, "A status-line reading reads as its own status, not as OK");
ExpectEqual(statusLineIssue.TechnicalDetail, "Credentials expired for Claude API", "The reason the API path failed is kept");
ExpectEqual(
    statusLineIssue.Recovery,
    new Localizer(AppLanguage.English).Text(L10nKey.RecoverySignInAgainClaude),
    "Showing status-line numbers still tells the user to sign in again");

// Windows has no key-to-English fallback: a missing Korean string shows the enum
// name to the user.
foreach (var statusLineLanguage in new[] { AppLanguage.English, AppLanguage.Korean })
{
    var statusLineLocalizer = new Localizer(statusLineLanguage);
    foreach (var key in new[] { L10nKey.StatusFromStatusLine, L10nKey.StatusFromStatusLineDetail })
    {
        Expect(
            statusLineLocalizer.Text(key) != key.ToString(),
            $"{statusLineLanguage} has a string for {key}");
    }
}

RunStatusLineBridgeScriptTests();

Console.WriteLine("TokenTracker.Windows.Tests passed");

static string StatusLinePayload(
    DateTimeOffset? measuredAt,
    DateTimeOffset? writtenAt,
    double? usedPercent5h,
    DateTimeOffset? resetAt5h,
    double? usedPercent7d,
    DateTimeOffset? resetAt7d,
    int version = ClaudeStatusLineBridge.Version)
{
    var windows = new List<string>();
    if (usedPercent5h is not null && resetAt5h is not null)
    {
        windows.Add(StatusLineWindow("five_hour", usedPercent5h.Value, resetAt5h.Value));
    }

    if (usedPercent7d is not null && resetAt7d is not null)
    {
        windows.Add(StatusLineWindow("seven_day", usedPercent7d.Value, resetAt7d.Value));
    }

    var fields = new List<string>
    {
        "\"version\":" + version.ToString(CultureInfo.InvariantCulture),
        "\"provider\":\"claude\""
    };
    if (measuredAt is not null)
    {
        fields.Add("\"measured_at\":" + Seconds(measuredAt.Value));
    }

    if (writtenAt is not null)
    {
        fields.Add("\"written_at\":" + Seconds(writtenAt.Value));
    }

    fields.Add("\"rate_limits\":{" + string.Join(",", windows) + "}");
    return "{" + string.Join(",", fields) + "}";
}

static string StatusLineWindow(string name, double usedPercent, DateTimeOffset resetAt) =>
    "\"" + name + "\":{\"used_percentage\":"
    + usedPercent.ToString(CultureInfo.InvariantCulture)
    + ",\"resets_at\":" + Seconds(resetAt) + "}";

static string Seconds(DateTimeOffset date) =>
    date.ToUnixTimeSeconds().ToString(CultureInfo.InvariantCulture);

/// <summary>
/// Drives scripts/claude-statusline-bridge.ps1 the way Claude Code does. The
/// script is where "a re-run is not a new measurement" is actually decided on
/// this platform, and it is the one piece of this feature that no compiler looks
/// at. Skipped when the checkout or PowerShell is not reachable; the truth table
/// above does not depend on it.
/// </summary>
static void RunStatusLineBridgeScriptTests()
{
    var script = FindRepoFile(Path.Combine("scripts", "claude-statusline-bridge.ps1"));
    var shell = ResolvePowerShell();
    if (script is null || shell is null)
    {
        return;
    }

    var directory = Path.Combine(Path.GetTempPath(), "token-tracker-statusline-" + Guid.NewGuid().ToString("N"));
    Directory.CreateDirectory(directory);
    try
    {
        var output = Path.Combine(directory, "claude-statusline.json");
        var reset5h = DateTimeOffset.UtcNow.AddHours(1);
        var reset7d = DateTimeOffset.UtcNow.AddDays(1);

        // Stands in for whatever status-line command the user already had. It
        // drains stdin and prints its own line, which is exactly the contract the
        // bridge must not break.
        var inner = Path.Combine(directory, "inner.cmd");
        File.WriteAllText(inner, "@echo off\r\nmore > nul\r\necho MY STATUS LINE\r\n");

        string Run(double? usedPercent5h)
        {
            var limits = new List<string>();
            if (usedPercent5h is not null)
            {
                limits.Add(StatusLineWindow("five_hour", usedPercent5h.Value, reset5h));
            }

            limits.Add(StatusLineWindow("seven_day", 41.2, reset7d));
            var payload = "{\"session_id\":\"s-123\",\"transcript_path\":\"C:\\\\t\\\\t.jsonl\","
                + "\"model\":{\"id\":\"claude-opus-5\"},"
                + "\"rate_limits\":{" + string.Join(",", limits) + "}}";

            var startInfo = new ProcessStartInfo(shell)
            {
                ArgumentList = { "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", script, "--", inner },
                UseShellExecute = false,
                RedirectStandardInput = true,
                RedirectStandardOutput = true
            };
            startInfo.Environment["TOKEN_TRACKER_STATUSLINE_FILE"] = output;

            using var process = Process.Start(startInfo)
                ?? throw new InvalidOperationException("Could not start the bridge script");
            process.StandardInput.Write(payload);
            process.StandardInput.Close();
            // stderr is left attached to this test's own, so anything the script
            // complains about lands in the build log instead of a swallowed pipe.
            var printed = process.StandardOutput.ReadToEnd();
            Expect(process.WaitForExit(60_000), "The bridge script finishes");
            ExpectEqual(process.ExitCode, 0, "The bridge script exits cleanly");
            return printed;
        }

        ClaudeStatusLineRecord ReadRecord() =>
            ClaudeStatusLineBridge.Parse(File.ReadAllText(output))
            ?? throw new InvalidOperationException("The bridge wrote a record Core cannot read");

        // The user's own status line keeps printing. This is the requirement that
        // outranks everything else here: a bridge that eats the status line is
        // worse than no bridge.
        Expect(
            Run(23.5).Contains("MY STATUS LINE", StringComparison.Ordinal),
            "The wrapped status-line command still prints its own output");

        var firstScriptRecord = ReadRecord();
        ExpectEqual(firstScriptRecord.UsedPercent5h, 23.5, "The 5h percentage is recorded");
        ExpectEqual(firstScriptRecord.UsedPercent7d, 41.2, "The 7d percentage is recorded");
        ExpectEqual(firstScriptRecord.MeasuredAt, firstScriptRecord.WrittenAt, "A first reading was measured when it was written");

        // Only usage. Everything else the status line is handed — the session id,
        // the transcript path, the model — is read and dropped.
        var onDisk = File.ReadAllText(output);
        foreach (var leaked in new[] { "s-123", "transcript", "claude-opus-5", "session_id" })
        {
            Expect(!onDisk.Contains(leaked, StringComparison.Ordinal), "The bridge file does not carry " + leaked);
        }

        // Age the record on disk, so "preserved" and "recomputed" are two
        // different numbers rather than two runs landing in the same second.
        var aged = DateTimeOffset.UtcNow.AddHours(-2);
        void Backdate() => File.WriteAllText(
            output,
            StatusLinePayload(aged, aged, 23.5, reset5h, 41.2, reset7d));

        // Same numbers again: a re-run, not a measurement. This is the rule the
        // whole format exists for — the status-line command re-runs on the CLI's
        // own schedule.
        Backdate();
        Run(23.5);
        ExpectEqual(
            ReadRecord().MeasuredAt.ToUnixTimeSeconds(),
            aged.ToUnixTimeSeconds(),
            "An unchanged payload does not advance the measurement time");
        Expect(
            ReadRecord().WrittenAt > aged,
            "An unchanged payload still records that the bridge ran");

        // Numbers moved: a measurement.
        Backdate();
        Run(44.0);
        var advancedScriptRecord = ReadRecord();
        ExpectEqual(advancedScriptRecord.UsedPercent5h, 44.0, "A changed payload is recorded");
        Expect(
            advancedScriptRecord.MeasuredAt > aged,
            "A changed payload advances the measurement time");

        // A second session rendering a staler copy of the same window must not
        // drag the record backwards: within one window instance, usage only climbs.
        Run(30.0);
        ExpectEqual(ReadRecord().UsedPercent5h, 44.0, "A lower percentage for the same window does not overwrite a newer one");
        ExpectEqual(ReadRecord().MeasuredAt, advancedScriptRecord.MeasuredAt, "An older concurrent reading does not advance the measurement time");

        // Early in a session, or on a plan without them, rate_limits is absent.
        // That must not erase what is already known.
        Run(null);
        ExpectEqual(ReadRecord().UsedPercent5h, 44.0, "A payload missing one window keeps the window already recorded");
    }
    finally
    {
        Directory.Delete(directory, recursive: true);
    }
}

/// Walks up from the test binary to the checkout, so the script can be found
/// whatever the build output layout is.
static string? FindRepoFile(string relativePath)
{
    var directory = new DirectoryInfo(AppContext.BaseDirectory);
    while (directory is not null)
    {
        var candidate = Path.Combine(directory.FullName, relativePath);
        if (File.Exists(candidate))
        {
            return candidate;
        }

        directory = directory.Parent;
    }

    return null;
}

static string? ResolvePowerShell()
{
    foreach (var candidate in new[] { "pwsh", "powershell" })
    {
        try
        {
            var startInfo = new ProcessStartInfo(candidate)
            {
                ArgumentList = { "-NoProfile", "-Command", "exit 0" },
                UseShellExecute = false,
                RedirectStandardOutput = true,
                RedirectStandardError = true
            };
            using var probe = Process.Start(startInfo);
            if (probe is null)
            {
                continue;
            }

            probe.StandardOutput.ReadToEnd();
            probe.StandardError.ReadToEnd();
            if (probe.WaitForExit(60_000) && probe.ExitCode == 0)
            {
                return candidate;
            }
        }
        catch
        {
        }
    }

    return null;
}

static UsageIssue CredentialIssue(Provider provider, string error, UsageSource source) =>
    UsageIssueFormatter.Issue(new ProviderUsage(
        provider,
        RemainingPercent5h: source == UsageSource.StaleCache ? (int?)42 : null,
        RemainingPercent7d: null,
        ResetAt5h: null,
        ResetAt7d: null,
        source,
        error,
        Plan: null,
        Model: null,
        UpdatedAt: DateTimeOffset.Now));

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

sealed class QueueHttpMessageHandler : HttpMessageHandler
{
    private readonly Queue<HttpResponseMessage> responses;

    public int CallCount { get; private set; }

    public QueueHttpMessageHandler(params HttpResponseMessage[] responses)
    {
        this.responses = new Queue<HttpResponseMessage>(responses);
    }

    protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken)
    {
        CallCount++;
        if (responses.Count == 0)
        {
            throw new InvalidOperationException("No queued HTTP response");
        }

        return Task.FromResult(responses.Dequeue());
    }
}
