import Foundation

public final class Settings {
    private enum Key {
        static let displayMode = "displayMode"
        static let providerLabelStyle = "providerLabelStyle"
        static let refreshInterval = "refreshInterval"
        static let claudeEnabled = "claudeEnabled"
        static let codexEnabled = "codexEnabled"
        static let language = "language"
        static let notificationsEnabled = "notificationsEnabled"
        static let fiveHourAlertThreshold = "fiveHourAlertThreshold"
        static let sevenDayAlertThreshold = "sevenDayAlertThreshold"
        static let resetAlertMinutes = "resetAlertMinutes"
        static let historyRetentionDays = "historyRetentionDays"
    }

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        registerDefaults()
    }

    public var displayMode: DisplayMode {
        get {
            let raw = defaults.string(forKey: Key.displayMode) ?? DisplayMode.lowestRemaining.rawValue
            return DisplayMode(rawValue: raw) ?? .lowestRemaining
        }
        set { defaults.set(newValue.rawValue, forKey: Key.displayMode) }
    }

    public var providerLabelStyle: ProviderLabelStyle {
        get {
            let raw = defaults.string(forKey: Key.providerLabelStyle) ?? ProviderLabelStyle.abbreviation.rawValue
            return ProviderLabelStyle(rawValue: raw) ?? .abbreviation
        }
        set { defaults.set(newValue.rawValue, forKey: Key.providerLabelStyle) }
    }

    public var refreshInterval: TimeInterval {
        get { defaults.double(forKey: Key.refreshInterval) }
        set { defaults.set(newValue, forKey: Key.refreshInterval) }
    }

    public var claudeEnabled: Bool {
        get { defaults.bool(forKey: Key.claudeEnabled) }
        set { defaults.set(newValue, forKey: Key.claudeEnabled) }
    }

    public var codexEnabled: Bool {
        get { defaults.bool(forKey: Key.codexEnabled) }
        set { defaults.set(newValue, forKey: Key.codexEnabled) }
    }

    public var language: AppLanguage {
        get {
            let raw = defaults.string(forKey: Key.language) ?? AppLanguage.system.rawValue
            return AppLanguage(rawValue: raw) ?? .system
        }
        set { defaults.set(newValue.rawValue, forKey: Key.language) }
    }

    public var notificationsEnabled: Bool {
        get { defaults.bool(forKey: Key.notificationsEnabled) }
        set { defaults.set(newValue, forKey: Key.notificationsEnabled) }
    }

    public var fiveHourAlertThreshold: Int {
        get { defaults.integer(forKey: Key.fiveHourAlertThreshold) }
        set { defaults.set(clampThreshold(newValue), forKey: Key.fiveHourAlertThreshold) }
    }

    public var sevenDayAlertThreshold: Int {
        get { defaults.integer(forKey: Key.sevenDayAlertThreshold) }
        set { defaults.set(clampThreshold(newValue), forKey: Key.sevenDayAlertThreshold) }
    }

    public var resetAlertMinutes: Int {
        get { defaults.integer(forKey: Key.resetAlertMinutes) }
        set { defaults.set(max(0, min(1440, newValue)), forKey: Key.resetAlertMinutes) }
    }

    public var historyRetentionDays: Int {
        get { defaults.integer(forKey: Key.historyRetentionDays) }
        set { defaults.set(max(1, min(365, newValue)), forKey: Key.historyRetentionDays) }
    }

    private func registerDefaults() {
        defaults.register(defaults: [
            Key.displayMode: DisplayMode.lowestRemaining.rawValue,
            Key.providerLabelStyle: ProviderLabelStyle.abbreviation.rawValue,
            Key.refreshInterval: 60.0,
            Key.claudeEnabled: true,
            Key.codexEnabled: true,
            Key.language: AppLanguage.system.rawValue,
            Key.notificationsEnabled: false,
            Key.fiveHourAlertThreshold: 20,
            Key.sevenDayAlertThreshold: 10,
            Key.resetAlertMinutes: 10,
            Key.historyRetentionDays: 7
        ])
    }

    private func clampThreshold(_ value: Int) -> Int {
        max(0, min(100, value))
    }
}
