import AppKit
import SwiftUI
import TokenTrackerCore

@MainActor
final class PreferencesWindowController: NSWindowController {
    init(
        settings: TokenTrackerCore.Settings,
        onGeneralChange: @escaping () -> Void,
        onProviderChange: @escaping () -> Void,
        onNotificationsEnabled: @escaping () -> Void
    ) {
        let model = PreferencesModel(
            settings: settings,
            onGeneralChange: onGeneralChange,
            onProviderChange: onProviderChange,
            onNotificationsEnabled: onNotificationsEnabled
        )
        // Tall enough to show every section at once, but never taller than the screen:
        // a small display scrolls the form instead of pushing the window off-screen.
        let visibleHeight = NSScreen.main?.visibleFrame.height ?? 800
        let height = min(PreferencesView.fullHeight, visibleHeight - 80)
        let window = NSWindow(
            contentViewController: NSHostingController(rootView: PreferencesView(model: model, height: height))
        )
        window.styleMask = [.titled, .closable]
        window.title = "Token Tracker"
        window.isReleasedWhenClosed = false
        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show() {
        showWindow(nil)
        window?.center()
        NSApp.activate(ignoringOtherApps: true)
    }
}

/// Mirrors `Settings` for the form. Each property writes through to `Settings` and
/// fires the same callback the old AppKit controls did; this window is the only
/// writer of these keys, so the values read at init stay current.
@MainActor
final class PreferencesModel: ObservableObject {
    private let settings: TokenTrackerCore.Settings
    private let onGeneralChange: () -> Void
    private let onProviderChange: () -> Void
    private let onNotificationsEnabled: () -> Void

    @Published var claudeEnabled: Bool {
        didSet { settings.claudeEnabled = claudeEnabled; onProviderChange() }
    }
    @Published var codexEnabled: Bool {
        didSet { settings.codexEnabled = codexEnabled; onProviderChange() }
    }
    @Published var language: AppLanguage {
        didSet { settings.language = language; onGeneralChange() }
    }
    @Published var refreshInterval: TimeInterval {
        didSet { settings.refreshInterval = refreshInterval; onGeneralChange() }
    }
    @Published var displayMode: DisplayMode {
        didSet { settings.displayMode = displayMode; onGeneralChange() }
    }
    @Published var providerLabelStyle: ProviderLabelStyle {
        didSet { settings.providerLabelStyle = providerLabelStyle; onGeneralChange() }
    }
    @Published var showResetCountdown: Bool {
        didSet { settings.showResetCountdown = showResetCountdown; onGeneralChange() }
    }
    @Published var showForecast: Bool {
        didSet { settings.showForecast = showForecast; onGeneralChange() }
    }
    @Published var notificationsEnabled: Bool {
        didSet {
            settings.notificationsEnabled = notificationsEnabled
            if notificationsEnabled {
                onNotificationsEnabled()
            } else {
                onGeneralChange()
            }
        }
    }
    @Published var fiveHourAlertThreshold: Int {
        didSet { settings.fiveHourAlertThreshold = fiveHourAlertThreshold; onGeneralChange() }
    }
    @Published var sevenDayAlertThreshold: Int {
        didSet { settings.sevenDayAlertThreshold = sevenDayAlertThreshold; onGeneralChange() }
    }
    @Published var resetAlertMinutes: Int {
        didSet { settings.resetAlertMinutes = resetAlertMinutes; onGeneralChange() }
    }
    @Published var depletionAlertEnabled: Bool {
        didSet { settings.depletionAlertEnabled = depletionAlertEnabled; onGeneralChange() }
    }
    @Published var staleToleranceHours: Int {
        didSet { settings.staleToleranceHours = staleToleranceHours; onGeneralChange() }
    }
    @Published var historyRetentionDays: Int {
        didSet { settings.historyRetentionDays = historyRetentionDays; onGeneralChange() }
    }
    @Published var checkForUpdates: Bool {
        didSet { settings.checkForUpdates = checkForUpdates; onGeneralChange() }
    }

    var localizer: Localizer {
        Localizer(language: language)
    }

    init(
        settings: TokenTrackerCore.Settings,
        onGeneralChange: @escaping () -> Void,
        onProviderChange: @escaping () -> Void,
        onNotificationsEnabled: @escaping () -> Void
    ) {
        self.settings = settings
        self.onGeneralChange = onGeneralChange
        self.onProviderChange = onProviderChange
        self.onNotificationsEnabled = onNotificationsEnabled
        claudeEnabled = settings.claudeEnabled
        codexEnabled = settings.codexEnabled
        language = settings.language
        refreshInterval = settings.refreshInterval
        displayMode = settings.displayMode
        providerLabelStyle = settings.providerLabelStyle
        showResetCountdown = settings.showResetCountdown
        showForecast = settings.showForecast
        notificationsEnabled = settings.notificationsEnabled
        fiveHourAlertThreshold = settings.fiveHourAlertThreshold
        sevenDayAlertThreshold = settings.sevenDayAlertThreshold
        resetAlertMinutes = settings.resetAlertMinutes
        depletionAlertEnabled = settings.depletionAlertEnabled
        staleToleranceHours = settings.staleToleranceHours
        historyRetentionDays = settings.historyRetentionDays
        checkForUpdates = settings.checkForUpdates
    }
}

private struct PreferencesView: View {
    static let fullHeight: CGFloat = 885

    @ObservedObject var model: PreferencesModel
    let height: CGFloat

    var body: some View {
        let localizer = model.localizer
        Form {
            Section(localizer.text(.providers)) {
                Toggle("Claude", isOn: $model.claudeEnabled)
                Toggle("Codex", isOn: $model.codexEnabled)
            }

            Section {
                Picker(localizer.text(.language), selection: $model.language) {
                    ForEach(AppLanguage.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                Picker(localizer.text(.refreshInterval), selection: $model.refreshInterval) {
                    Text("1m").tag(TimeInterval(60))
                    Text("5m").tag(TimeInterval(300))
                    Text("15m").tag(TimeInterval(900))
                }
                Toggle(localizer.text(.checkForUpdates), isOn: $model.checkForUpdates)
            } header: {
                Text(localizer.text(.general))
            } footer: {
                if model.refreshInterval < 300 {
                    Label(localizer.text(.refreshIntervalWarning), systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section(localizer.text(.display)) {
                Picker(localizer.text(.displayMode), selection: $model.displayMode) {
                    ForEach(DisplayMode.allCases, id: \.self) { Text(displayModeLabel($0)).tag($0) }
                }
                Picker(localizer.text(.providerLabelStyle), selection: $model.providerLabelStyle) {
                    ForEach(ProviderLabelStyle.allCases, id: \.self) { Text(providerLabelStyleLabel($0)).tag($0) }
                }
                Toggle(localizer.text(.showResetCountdownLabel), isOn: $model.showResetCountdown)
                Toggle(localizer.text(.showForecastLabel), isOn: $model.showForecast)
            }

            Section(localizer.text(.notifications)) {
                Toggle(localizer.text(.enableNotifications), isOn: $model.notificationsEnabled)
                Group {
                    StepperRow(
                        title: localizer.text(.fiveHourAlertThreshold),
                        value: $model.fiveHourAlertThreshold,
                        range: 0...100,
                        unit: "%"
                    )
                    StepperRow(
                        title: localizer.text(.sevenDayAlertThreshold),
                        value: $model.sevenDayAlertThreshold,
                        range: 0...100,
                        unit: "%"
                    )
                    StepperRow(
                        title: localizer.text(.resetAlertMinutes),
                        value: $model.resetAlertMinutes,
                        range: 0...1440,
                        unit: "m"
                    )
                    Toggle(localizer.text(.depletionAlertToggle), isOn: $model.depletionAlertEnabled)
                }
                .disabled(!model.notificationsEnabled)
            }

            Section(localizer.text(.data)) {
                StepperRow(
                    title: localizer.text(.staleToleranceHours),
                    value: $model.staleToleranceHours,
                    range: 1...48,
                    unit: "h"
                )
                StepperRow(
                    title: localizer.text(.historyRetentionDays),
                    value: $model.historyRetentionDays,
                    range: 1...365,
                    unit: "d"
                )
            }
        }
        .formStyle(.grouped)
        .toggleStyle(.switch)
        .frame(width: 460, height: height)
    }

    private func displayModeLabel(_ mode: DisplayMode) -> String {
        switch mode {
        case .lowestRemaining: model.localizer.text(.lowestRemaining)
        case .both: model.localizer.text(.both)
        case .codexOnly: model.localizer.text(.codexOnly)
        case .claudeOnly: model.localizer.text(.claudeOnly)
        }
    }

    private func providerLabelStyleLabel(_ style: ProviderLabelStyle) -> String {
        switch style {
        case .abbreviation: "Cdx / Cl"
        case .icon: model.localizer.text(.officialLogos)
        }
    }
}

private struct StepperRow: View {
    let title: String
    @Binding var value: Int
    let range: ClosedRange<Int>
    let unit: String

    var body: some View {
        LabeledContent(title) {
            HStack(spacing: 6) {
                Text("\(value)\(unit)")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                Stepper(title, value: $value, in: range)
                    .labelsHidden()
            }
        }
    }
}
