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
        .displayMode: "Display Mode",
        .language: "Language",
        .launchAtLogin: "Launch at Login",
        .quit: "Quit",
        .fiveHourReset: "5h reset",
        .sevenDayReset: "7d reset",
        .source: "Source",
        .error: "Error",
        .plan: "Plan",
        .launchFailed: "Launch at Login failed",
        .statusEnabled: "Enabled",
        .statusDisabled: "Disabled",
        .statusNotFound: "App bundle not found",
        .statusRequiresApproval: "Requires approval in System Settings",
        .statusUnknown: "Unknown",
        .now: "now",
        .ago: "ago"
    ]

    private let korean: [L10nKey: String] = [
        .noUsageLoaded: "아직 사용량을 불러오지 못했습니다",
        .updated: "업데이트",
        .refreshNow: "지금 새로고침",
        .displayMode: "표시 방식",
        .language: "언어",
        .launchAtLogin: "로그인 시 실행",
        .quit: "종료",
        .fiveHourReset: "5시간 리셋",
        .sevenDayReset: "7일 리셋",
        .source: "데이터 출처",
        .error: "오류",
        .plan: "플랜",
        .launchFailed: "로그인 시 실행 설정 실패",
        .statusEnabled: "켜짐",
        .statusDisabled: "꺼짐",
        .statusNotFound: "앱 번들을 찾을 수 없음",
        .statusRequiresApproval: "시스템 설정에서 승인 필요",
        .statusUnknown: "알 수 없음",
        .now: "지금",
        .ago: "전"
    ]
}

public enum L10nKey: String {
    case noUsageLoaded
    case updated
    case refreshNow
    case displayMode
    case language
    case launchAtLogin
    case quit
    case fiveHourReset
    case sevenDayReset
    case source
    case error
    case plan
    case launchFailed
    case statusEnabled
    case statusDisabled
    case statusNotFound
    case statusRequiresApproval
    case statusUnknown
    case now
    case ago
}
