using System.Globalization;

namespace TokenTracker.Windows.Core;

public enum L10nKey
{
    NoUsageLoaded,
    Updated,
    Ago,
    RefreshNow,
    DisplayMode,
    ProviderLabels,
    Providers,
    RefreshInterval,
    LaunchAtLogin,
    AlwaysShowIconSettings,
    Quit,
    FiveHourReset,
    SevenDayReset,
    Source,
    Error,
    Plan,
    Language,
    LowestRemaining,
    Both,
    CodexOnly,
    ClaudeOnly,
    Names,
    OfficialLogos,
    TaskbarSettingsTip,
    TaskbarSettingsFallback
}

public sealed class Localizer
{
    public AppLanguage Language { get; }

    public Localizer(AppLanguage language)
    {
        Language = language == AppLanguage.System
            ? CultureInfo.CurrentUICulture.TwoLetterISOLanguageName.Equals("ko", StringComparison.OrdinalIgnoreCase)
                ? AppLanguage.Korean
                : AppLanguage.English
            : language;
    }

    public string Text(L10nKey key)
    {
        var table = Language == AppLanguage.Korean ? Korean : English;
        return table.TryGetValue(key, out var value) ? value : key.ToString();
    }

    public static string LanguageLabel(AppLanguage language) => language switch
    {
        AppLanguage.System => "System",
        AppLanguage.English => "English",
        AppLanguage.Korean => "한국어",
        _ => language.ToString()
    };

    private static readonly IReadOnlyDictionary<L10nKey, string> English = new Dictionary<L10nKey, string>
    {
        [L10nKey.NoUsageLoaded] = "No usage loaded yet",
        [L10nKey.Updated] = "Updated",
        [L10nKey.Ago] = "ago",
        [L10nKey.RefreshNow] = "Refresh Now",
        [L10nKey.DisplayMode] = "Display Mode",
        [L10nKey.ProviderLabels] = "Provider Labels",
        [L10nKey.Providers] = "Providers",
        [L10nKey.RefreshInterval] = "Refresh Interval",
        [L10nKey.LaunchAtLogin] = "Launch at Login",
        [L10nKey.AlwaysShowIconSettings] = "Always Show Icon Settings...",
        [L10nKey.Quit] = "Quit",
        [L10nKey.FiveHourReset] = "5h reset",
        [L10nKey.SevenDayReset] = "7d reset",
        [L10nKey.Source] = "Source",
        [L10nKey.Error] = "Error",
        [L10nKey.Plan] = "Plan",
        [L10nKey.Language] = "Language",
        [L10nKey.LowestRemaining] = "Lowest remaining",
        [L10nKey.Both] = "Claude + Codex",
        [L10nKey.CodexOnly] = "Codex only",
        [L10nKey.ClaudeOnly] = "Claude only",
        [L10nKey.Names] = "Names",
        [L10nKey.OfficialLogos] = "Official logos",
        [L10nKey.TaskbarSettingsTip] = "In Taskbar settings, enable Token Tracker under notification area / system tray icons.",
        [L10nKey.TaskbarSettingsFallback] = "Open Windows Settings > Personalization > Taskbar and enable Token Tracker under notification area icons."
    };

    private static readonly IReadOnlyDictionary<L10nKey, string> Korean = new Dictionary<L10nKey, string>
    {
        [L10nKey.NoUsageLoaded] = "아직 사용량을 불러오지 못했습니다",
        [L10nKey.Updated] = "업데이트",
        [L10nKey.Ago] = "전",
        [L10nKey.RefreshNow] = "지금 새로고침",
        [L10nKey.DisplayMode] = "표시 방식",
        [L10nKey.ProviderLabels] = "제공자 표기",
        [L10nKey.Providers] = "제공자",
        [L10nKey.RefreshInterval] = "새로고침 주기",
        [L10nKey.LaunchAtLogin] = "로그인 시 실행",
        [L10nKey.AlwaysShowIconSettings] = "아이콘 상시 표시 설정 열기...",
        [L10nKey.Quit] = "종료",
        [L10nKey.FiveHourReset] = "5시간 리셋",
        [L10nKey.SevenDayReset] = "7일 리셋",
        [L10nKey.Source] = "데이터 출처",
        [L10nKey.Error] = "오류",
        [L10nKey.Plan] = "플랜",
        [L10nKey.Language] = "언어",
        [L10nKey.LowestRemaining] = "가장 낮은 잔량",
        [L10nKey.Both] = "Claude + Codex",
        [L10nKey.CodexOnly] = "Codex만",
        [L10nKey.ClaudeOnly] = "Claude만",
        [L10nKey.Names] = "이름",
        [L10nKey.OfficialLogos] = "공식 로고",
        [L10nKey.TaskbarSettingsTip] = "작업표시줄 설정에서 알림 영역/시스템 트레이 아이콘 목록의 Token Tracker를 켜세요.",
        [L10nKey.TaskbarSettingsFallback] = "Windows 설정 > 개인 설정 > 작업 표시줄에서 알림 영역 아이콘의 Token Tracker를 켜세요."
    };
}
