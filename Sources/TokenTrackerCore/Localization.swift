import Foundation

public enum AppLanguage: String, CaseIterable {
    case system
    case english
    case korean

    public var label: String {
        switch self {
        case .system: "System"
        case .english: "English"
        case .korean: "한국어"
        }
    }
}

public struct Localizer {
    public let language: AppLanguage

    public init(language: AppLanguage) {
        if language == .system {
            let preferred = Locale.preferredLanguages.first ?? "en"
            self.language = preferred.lowercased().hasPrefix("ko") ? .korean : .english
        } else {
            self.language = language
        }
    }

    public func text(_ key: L10nKey) -> String {
        switch language {
        case .korean:
            return korean[key] ?? english[key] ?? key.rawValue
        case .system, .english:
            return english[key] ?? key.rawValue
        }
    }

    private let english: [L10nKey: String] = [
        .noUsageLoaded: "No usage loaded yet",
        .updated: "Updated",
        .refreshNow: "Refresh Now",
        .preferences: "Preferences...",
        .displayMode: "Display Mode",
        .providerLabelStyle: "Provider Labels",
        .providers: "Providers",
        .refreshInterval: "Refresh Interval",
        .language: "Language",
        .launchAtLogin: "Launch at Login",
        .quit: "Quit",
        .fiveHourReset: "5h reset",
        .sevenDayReset: "7d reset",
        .source: "Source",
        .status: "Status",
        .error: "Error",
        .technicalError: "Technical error",
        .recovery: "Recovery",
        .diagnostics: "Diagnostics",
        .copyDiagnostics: "Copy Diagnostics",
        .diagnosticsCopied: "Diagnostics copied",
        .openClaudeCredentials: "Open Claude Credentials",
        .openCodexAuth: "Open Codex Auth",
        .lastSuccessfulUpdate: "Last successful update",
        .noSuccessfulUpdate: "No successful update yet",
        .duplicateInstances: "Running instances",
        .refreshIntervalWarning: "Short refresh intervals can trigger provider rate limits.",
        .notifications: "Notifications",
        .fiveHourAlertTitle: "5h usage is low",
        .sevenDayAlertTitle: "7d usage is low",
        .resetAlertTitle: "Usage window reset soon",
        .fiveHourAlertThreshold: "5h alert threshold",
        .sevenDayAlertThreshold: "7d alert threshold",
        .resetAlertMinutes: "Reset alert window",
        .history: "History",
        .historyTrend: "24h trend:",
        .notEnoughHistory: "Not enough history yet",
        .exportHistoryCSV: "Export History CSV...",
        .historyRetentionDays: "History retention",
        .forecastLabel: "Projected depletion",
        .forecastBeforeReset: "empties before reset",
        .depletionAlertTitle: "May run out before reset",
        .showForecastLabel: "Show depletion forecast",
        .depletionAlertToggle: "Depletion alert (before reset)",
        .pausePolling: "Pause updates",
        .pause1h: "For 1 hour",
        .pause3h: "For 3 hours",
        .pauseUntilResumed: "Until I resume",
        .resumeNow: "Resume now",
        .updatesPaused: "Updates paused",
        .plan: "Plan",
        .launchFailed: "Launch at Login failed",
        .statusEnabled: "Enabled",
        .statusDisabled: "Disabled",
        .statusNotFound: "App bundle not found",
        .statusRequiresApproval: "Requires approval in System Settings",
        .statusUnknown: "Unknown",
        .statusOK: "OK",
        .statusOKDetail: "Usage loaded normally.",
        .statusDisabledProvider: "Disabled",
        .statusDisabledProviderDetail: "This provider is turned off.",
        .statusRateLimited: "Rate limited",
        .statusRateLimitedDetail: "The provider temporarily rejected usage checks because requests were too frequent.",
        .statusMissingCredentials: "Login required",
        .statusMissingCredentialsDetail: "Token Tracker could not find local credentials for this provider.",
        .statusInvalidResponse: "Unexpected response",
        .statusInvalidResponseDetail: "The provider returned data in a format Token Tracker did not expect.",
        .statusTimedOut: "Timed out",
        .statusTimedOutDetail: "The provider did not respond before the request timed out.",
        .statusNetworkIssue: "Network issue",
        .statusNetworkIssueDetail: "The request failed before a usable provider response was received.",
        .statusHTTPError: "Provider HTTP error",
        .statusHTTPErrorDetail: "The provider returned an HTTP error while checking usage.",
        .statusUsingCachedData: "Using cached data",
        .statusUsingCachedDataDetail: "The latest check failed, so the last successful value is being shown.",
        .statusUnavailable: "Unavailable",
        .statusUnavailableDetail: "No usage value is currently available.",
        .recoveryEnableProvider: "Enable the provider if you want Token Tracker to check it again.",
        .recoveryWaitForCooldown: "Wait for the cooldown to pass or use a longer refresh interval.",
        .recoveryCheckCredentials: "Sign in to the provider CLI/app, then refresh Token Tracker.",
        .recoveryUpdateOrTryLater: "Try again later. If this keeps happening, update Token Tracker.",
        .recoveryCheckNetwork: "Check your network connection and try again.",
        .recoveryRefreshLater: "Refresh again later.",
        .recoveryTryAgainLater: "Try again later.",
        .now: "now",
        .ago: "ago"
    ]

    private let korean: [L10nKey: String] = [
        .noUsageLoaded: "아직 사용량을 불러오지 못했습니다",
        .updated: "업데이트",
        .refreshNow: "지금 새로고침",
        .preferences: "설정...",
        .displayMode: "표시 방식",
        .providerLabelStyle: "제공자 표기",
        .providers: "제공자",
        .refreshInterval: "새로고침 간격",
        .language: "언어",
        .launchAtLogin: "로그인 시 실행",
        .quit: "종료",
        .fiveHourReset: "5시간 리셋",
        .sevenDayReset: "7일 리셋",
        .source: "데이터 출처",
        .status: "상태",
        .error: "오류",
        .technicalError: "기술 오류",
        .recovery: "복구 방법",
        .diagnostics: "진단",
        .copyDiagnostics: "진단 정보 복사",
        .diagnosticsCopied: "진단 정보가 복사됨",
        .openClaudeCredentials: "Claude 인증 파일 열기",
        .openCodexAuth: "Codex 인증 파일 열기",
        .lastSuccessfulUpdate: "마지막 성공 업데이트",
        .noSuccessfulUpdate: "아직 성공한 업데이트 없음",
        .duplicateInstances: "실행 중인 인스턴스",
        .refreshIntervalWarning: "짧은 새로고침 간격은 제공자 요청 제한을 유발할 수 있습니다.",
        .notifications: "알림",
        .fiveHourAlertTitle: "5시간 사용량 부족",
        .sevenDayAlertTitle: "7일 사용량 부족",
        .resetAlertTitle: "사용량 창 리셋 임박",
        .fiveHourAlertThreshold: "5시간 알림 기준",
        .sevenDayAlertThreshold: "7일 알림 기준",
        .resetAlertMinutes: "리셋 알림 시간",
        .history: "히스토리",
        .historyTrend: "24시간 추세:",
        .notEnoughHistory: "아직 히스토리가 부족합니다",
        .exportHistoryCSV: "히스토리 CSV 내보내기...",
        .historyRetentionDays: "히스토리 보관 기간",
        .forecastLabel: "예상 소진",
        .forecastBeforeReset: "리셋 전 소진",
        .depletionAlertTitle: "리셋 전 소진 예상",
        .showForecastLabel: "소진 예측 표시",
        .depletionAlertToggle: "소진 예측 알림 (리셋 전)",
        .pausePolling: "업데이트 일시중지",
        .pause1h: "1시간",
        .pause3h: "3시간",
        .pauseUntilResumed: "재개할 때까지",
        .resumeNow: "지금 재개",
        .updatesPaused: "업데이트 일시중지됨",
        .plan: "플랜",
        .launchFailed: "로그인 시 실행 설정 실패",
        .statusEnabled: "켜짐",
        .statusDisabled: "꺼짐",
        .statusNotFound: "앱 번들을 찾을 수 없음",
        .statusRequiresApproval: "시스템 설정에서 승인 필요",
        .statusUnknown: "알 수 없음",
        .statusOK: "정상",
        .statusOKDetail: "사용량을 정상적으로 불러왔습니다.",
        .statusDisabledProvider: "꺼짐",
        .statusDisabledProviderDetail: "이 제공자는 비활성화되어 있습니다.",
        .statusRateLimited: "요청 제한",
        .statusRateLimitedDetail: "요청이 너무 잦아 제공자가 사용량 확인을 일시적으로 거절했습니다.",
        .statusMissingCredentials: "로그인 필요",
        .statusMissingCredentialsDetail: "이 제공자의 로컬 인증 정보를 찾지 못했습니다.",
        .statusInvalidResponse: "예상과 다른 응답",
        .statusInvalidResponseDetail: "제공자가 Token Tracker가 예상하지 못한 형식의 데이터를 반환했습니다.",
        .statusTimedOut: "시간 초과",
        .statusTimedOutDetail: "요청 제한 시간 안에 제공자가 응답하지 않았습니다.",
        .statusNetworkIssue: "네트워크 문제",
        .statusNetworkIssueDetail: "사용 가능한 제공자 응답을 받기 전에 요청이 실패했습니다.",
        .statusHTTPError: "제공자 HTTP 오류",
        .statusHTTPErrorDetail: "사용량 확인 중 제공자가 HTTP 오류를 반환했습니다.",
        .statusUsingCachedData: "캐시 데이터 사용 중",
        .statusUsingCachedDataDetail: "최신 확인에 실패해 마지막 성공 값을 표시하고 있습니다.",
        .statusUnavailable: "사용 불가",
        .statusUnavailableDetail: "현재 표시할 사용량 값이 없습니다.",
        .recoveryEnableProvider: "다시 확인하려면 제공자를 켜세요.",
        .recoveryWaitForCooldown: "쿨다운이 끝날 때까지 기다리거나 새로고침 간격을 늘리세요.",
        .recoveryCheckCredentials: "제공자 CLI/앱에 로그인한 뒤 Token Tracker를 새로고침하세요.",
        .recoveryUpdateOrTryLater: "나중에 다시 시도하세요. 계속 발생하면 Token Tracker를 업데이트하세요.",
        .recoveryCheckNetwork: "네트워크 연결을 확인한 뒤 다시 시도하세요.",
        .recoveryRefreshLater: "나중에 다시 새로고침하세요.",
        .recoveryTryAgainLater: "나중에 다시 시도하세요.",
        .now: "지금",
        .ago: "전"
    ]
}

public enum L10nKey: String {
    case noUsageLoaded
    case updated
    case refreshNow
    case preferences
    case displayMode
    case providerLabelStyle
    case providers
    case refreshInterval
    case language
    case launchAtLogin
    case quit
    case fiveHourReset
    case sevenDayReset
    case source
    case status
    case error
    case technicalError
    case recovery
    case diagnostics
    case copyDiagnostics
    case diagnosticsCopied
    case openClaudeCredentials
    case openCodexAuth
    case lastSuccessfulUpdate
    case noSuccessfulUpdate
    case duplicateInstances
    case refreshIntervalWarning
    case notifications
    case fiveHourAlertTitle
    case sevenDayAlertTitle
    case resetAlertTitle
    case fiveHourAlertThreshold
    case sevenDayAlertThreshold
    case resetAlertMinutes
    case history
    case historyTrend
    case notEnoughHistory
    case exportHistoryCSV
    case historyRetentionDays
    case forecastLabel
    case forecastBeforeReset
    case depletionAlertTitle
    case showForecastLabel
    case depletionAlertToggle
    case pausePolling
    case pause1h
    case pause3h
    case pauseUntilResumed
    case resumeNow
    case updatesPaused
    case plan
    case launchFailed
    case statusEnabled
    case statusDisabled
    case statusNotFound
    case statusRequiresApproval
    case statusUnknown
    case statusOK
    case statusOKDetail
    case statusDisabledProvider
    case statusDisabledProviderDetail
    case statusRateLimited
    case statusRateLimitedDetail
    case statusMissingCredentials
    case statusMissingCredentialsDetail
    case statusInvalidResponse
    case statusInvalidResponseDetail
    case statusTimedOut
    case statusTimedOutDetail
    case statusNetworkIssue
    case statusNetworkIssueDetail
    case statusHTTPError
    case statusHTTPErrorDetail
    case statusUsingCachedData
    case statusUsingCachedDataDetail
    case statusUnavailable
    case statusUnavailableDetail
    case recoveryEnableProvider
    case recoveryWaitForCooldown
    case recoveryCheckCredentials
    case recoveryUpdateOrTryLater
    case recoveryCheckNetwork
    case recoveryRefreshLater
    case recoveryTryAgainLater
    case now
    case ago
}
