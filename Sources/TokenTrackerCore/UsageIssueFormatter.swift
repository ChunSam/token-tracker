import Foundation

public enum UsageIssueKind: String, Equatable, Sendable {
    case ok
    case disabled
    case rateLimited
    case missingCredentials
    case invalidResponse
    case timedOut
    case network
    case httpStatus
    case usingCachedData
    case unavailable
}

public struct UsageIssue: Equatable, Sendable {
    public let kind: UsageIssueKind
    public let title: String
    public let detail: String
    public let recovery: String?
    public let technicalDetail: String?

    public init(kind: UsageIssueKind, title: String, detail: String, recovery: String?, technicalDetail: String?) {
        self.kind = kind
        self.title = title
        self.detail = detail
        self.recovery = recovery
        self.technicalDetail = technicalDetail
    }
}

public enum UsageIssueFormatter {
    public static func issue(for usage: ProviderUsage, localizer: Localizer = Localizer(language: .english)) -> UsageIssue {
        if usage.source == .staleCache {
            let technicalDetail = usage.error
            return UsageIssue(
                kind: .usingCachedData,
                title: localizer.text(.statusUsingCachedData),
                detail: localizer.text(.statusUsingCachedDataDetail),
                recovery: recovery(for: technicalDetail, localizer: localizer) ?? localizer.text(.recoveryTryAgainLater),
                technicalDetail: technicalDetail
            )
        }

        guard let error = usage.error, !error.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            if usage.isAvailable {
                return UsageIssue(
                    kind: .ok,
                    title: localizer.text(.statusOK),
                    detail: localizer.text(.statusOKDetail),
                    recovery: nil,
                    technicalDetail: nil
                )
            }
            return UsageIssue(
                kind: .unavailable,
                title: localizer.text(.statusUnavailable),
                detail: localizer.text(.statusUnavailableDetail),
                recovery: localizer.text(.recoveryRefreshLater),
                technicalDetail: nil
            )
        }

        let kind = kind(forError: error)
        return UsageIssue(
            kind: kind,
            title: title(for: kind, localizer: localizer),
            detail: detail(for: kind, localizer: localizer),
            recovery: recovery(for: error, localizer: localizer),
            technicalDetail: error
        )
    }

    public static func kind(forError error: String) -> UsageIssueKind {
        let normalized = error.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = normalized.lowercased()

        if lower == "disabled" {
            return .disabled
        }
        if lower.contains("http 429") || lower.contains("too many requests") {
            return .rateLimited
        }
        if lower.contains("missing credentials") {
            return .missingCredentials
        }
        if lower.contains("invalid response") {
            return .invalidResponse
        }
        if lower.contains("timed out") {
            return .timedOut
        }
        if lower.contains("network error") {
            return .network
        }
        if lower.hasPrefix("http ") {
            return .httpStatus
        }
        return .unavailable
    }

    private static func title(for kind: UsageIssueKind, localizer: Localizer) -> String {
        switch kind {
        case .ok:
            return localizer.text(.statusOK)
        case .disabled:
            return localizer.text(.statusDisabledProvider)
        case .rateLimited:
            return localizer.text(.statusRateLimited)
        case .missingCredentials:
            return localizer.text(.statusMissingCredentials)
        case .invalidResponse:
            return localizer.text(.statusInvalidResponse)
        case .timedOut:
            return localizer.text(.statusTimedOut)
        case .network:
            return localizer.text(.statusNetworkIssue)
        case .httpStatus:
            return localizer.text(.statusHTTPError)
        case .usingCachedData:
            return localizer.text(.statusUsingCachedData)
        case .unavailable:
            return localizer.text(.statusUnavailable)
        }
    }

    private static func detail(for kind: UsageIssueKind, localizer: Localizer) -> String {
        switch kind {
        case .ok:
            return localizer.text(.statusOKDetail)
        case .disabled:
            return localizer.text(.statusDisabledProviderDetail)
        case .rateLimited:
            return localizer.text(.statusRateLimitedDetail)
        case .missingCredentials:
            return localizer.text(.statusMissingCredentialsDetail)
        case .invalidResponse:
            return localizer.text(.statusInvalidResponseDetail)
        case .timedOut:
            return localizer.text(.statusTimedOutDetail)
        case .network:
            return localizer.text(.statusNetworkIssueDetail)
        case .httpStatus:
            return localizer.text(.statusHTTPErrorDetail)
        case .usingCachedData:
            return localizer.text(.statusUsingCachedDataDetail)
        case .unavailable:
            return localizer.text(.statusUnavailableDetail)
        }
    }

    private static func recovery(for error: String?, localizer: Localizer) -> String? {
        guard let error else {
            return nil
        }
        switch kind(forError: error) {
        case .disabled:
            return localizer.text(.recoveryEnableProvider)
        case .rateLimited:
            return localizer.text(.recoveryWaitForCooldown)
        case .missingCredentials:
            return localizer.text(.recoveryCheckCredentials)
        case .invalidResponse:
            return localizer.text(.recoveryUpdateOrTryLater)
        case .timedOut, .network:
            return localizer.text(.recoveryCheckNetwork)
        case .httpStatus, .unavailable:
            return localizer.text(.recoveryRefreshLater)
        case .ok, .usingCachedData:
            return nil
        }
    }
}
