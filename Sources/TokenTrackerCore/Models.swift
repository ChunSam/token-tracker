import Foundation

public enum Provider: String, Codable, CaseIterable {
    case claude
    case codex

    public var displayName: String {
        switch self {
        case .claude: "Claude"
        case .codex: "Codex"
        }
    }
}

public enum UsageSource: String, Codable {
    case api
    case staleCache
    case localLog
    case unavailable
}

public enum DisplayMode: String, CaseIterable {
    case lowestRemaining
    case both
    case codexOnly

    public var label: String {
        switch self {
        case .lowestRemaining: "Lowest remaining"
        case .both: "Claude + Codex"
        case .codexOnly: "Codex only"
        }
    }
}

public struct ProviderUsage: Codable, Equatable {
    public var provider: Provider
    public var remainingPercent5h: Int?
    public var remainingPercent7d: Int?
    public var resetAt5h: Date?
    public var resetAt7d: Date?
    public var source: UsageSource
    public var error: String?
    public var plan: String?
    public var model: String?
    public var updatedAt: Date

    public init(provider: Provider, remainingPercent5h: Int?, remainingPercent7d: Int?, resetAt5h: Date?, resetAt7d: Date?, source: UsageSource, error: String?, plan: String?, model: String?, updatedAt: Date) {
        self.provider = provider
        self.remainingPercent5h = remainingPercent5h
        self.remainingPercent7d = remainingPercent7d
        self.resetAt5h = resetAt5h
        self.resetAt7d = resetAt7d
        self.source = source
        self.error = error
        self.plan = plan
        self.model = model
        self.updatedAt = updatedAt
    }

    public var isAvailable: Bool {
        remainingPercent5h != nil || remainingPercent7d != nil
    }
}

public struct UsageSnapshot: Codable, Equatable {
    public var claude: ProviderUsage
    public var codex: ProviderUsage
    public var updatedAt: Date

    public init(claude: ProviderUsage, codex: ProviderUsage, updatedAt: Date) {
        self.claude = claude
        self.codex = codex
        self.updatedAt = updatedAt
    }
}

extension ProviderUsage {
    public static func unavailable(_ provider: Provider, error: String) -> ProviderUsage {
        ProviderUsage(
            provider: provider,
            remainingPercent5h: nil,
            remainingPercent7d: nil,
            resetAt5h: nil,
            resetAt7d: nil,
            source: .unavailable,
            error: error,
            plan: nil,
            model: nil,
            updatedAt: Date()
        )
    }
}

public func clampPercent(_ value: Double) -> Int {
    min(100, max(0, Int(value.rounded())))
}

public func remainingPercent(fromUsed usedPercent: Double?) -> Int? {
    guard let usedPercent else { return nil }
    return clampPercent(100.0 - usedPercent)
}
