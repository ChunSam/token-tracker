import Foundation

public final class Settings {
    private enum Key {
        static let displayMode = "displayMode"
        static let refreshInterval = "refreshInterval"
        static let claudeEnabled = "claudeEnabled"
        static let codexEnabled = "codexEnabled"
        static let language = "language"
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

    private func registerDefaults() {
        defaults.register(defaults: [
            Key.displayMode: DisplayMode.lowestRemaining.rawValue,
            Key.refreshInterval: 60.0,
            Key.claudeEnabled: true,
            Key.codexEnabled: true,
            Key.language: AppLanguage.system.rawValue
        ])
    }
}
