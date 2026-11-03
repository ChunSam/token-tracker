import AppKit
import SwiftUI
import TokenTrackerCore

@MainActor
final class PreferencesWindowController: NSWindowController {
    init(
        settings: TokenTrackerCore.Settings,
        onGeneralChange: @escaping () -> Void,
        onProviderChange: @escaping () -> Void,
        onNotificationsEnabled: @escaping () -> Void,
        onCostChange: @escaping () -> Void
    ) {
        let model = PreferencesModel(
            settings: settings,
            onGeneralChange: onGeneralChange,
            onProviderChange: onProviderChange,
            onNotificationsEnabled: onNotificationsEnabled,
            onCostChange: onCostChange
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
    private let onCostChange: () -> Void
    private let adminKeys = KeychainAdminKeyStore()

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
    @Published var renewClaudeTokenWithCLI: Bool {
        didSet { settings.renewClaudeTokenWithCLI = renewClaudeTokenWithCLI; onGeneralChange() }
    }
    @Published var claudeCostEnabled: Bool {
        didSet { settings.claudeCostEnabled = claudeCostEnabled; onCostChange() }
    }
    @Published var codexCostEnabled: Bool {
        didSet { settings.codexCostEnabled = codexCostEnabled; onCostChange() }
    }
    @Published var claudeMonthlyBudget: Int {
        didSet {
            guard claudeMonthlyBudget >= 0 else { claudeMonthlyBudget = 0; return }
            settings.claudeMonthlyBudget = claudeMonthlyBudget
            onGeneralChange()
        }
    }
    @Published var codexMonthlyBudget: Int {
        didSet {
            guard codexMonthlyBudget >= 0 else { codexMonthlyBudget = 0; return }
            settings.codexMonthlyBudget = codexMonthlyBudget
            onGeneralChange()
        }
    }

    var localizer: Localizer {
        Localizer(language: language)
    }

    init(
        settings: TokenTrackerCore.Settings,
        onGeneralChange: @escaping () -> Void,
        onProviderChange: @escaping () -> Void,
        onNotificationsEnabled: @escaping () -> Void,
        onCostChange: @escaping () -> Void
    ) {
        self.settings = settings
        self.onGeneralChange = onGeneralChange
        self.onProviderChange = onProviderChange
        self.onNotificationsEnabled = onNotificationsEnabled
        self.onCostChange = onCostChange
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
        renewClaudeTokenWithCLI = settings.renewClaudeTokenWithCLI
        claudeCostEnabled = settings.claudeCostEnabled
        codexCostEnabled = settings.codexCostEnabled
        claudeMonthlyBudget = settings.claudeMonthlyBudget
        codexMonthlyBudget = settings.codexMonthlyBudget
    }

    /// Asks for the provider's Admin key. The keychain is read only here, when the
    /// user opens this, and the key never leaves the alert except into the keychain.
    func editAdminKey(_ provider: Provider) {
        if AdminKeyPrompt.run(provider: provider, store: adminKeys, localizer: localizer) {
            onCostChange()
        }
    }
}

@MainActor
private enum AdminKeyPrompt {
    /// `true` when a key was saved or deleted.
    static func run(provider: Provider, store: KeychainAdminKeyStore, localizer: Localizer) -> Bool {
        let existing = store.key(for: provider)
        let alert = NSAlert()
        alert.messageText = localizer.text(.adminKeyTitle)
            .replacingOccurrences(of: "{organization}", with: AdminKeyText.organization(provider))
        let stored = existing.map {
            localizer.text(.adminKeyStored).replacingOccurrences(of: "{suffix}", with: AdminKeyText.suffix($0))
        } ?? localizer.text(.adminKeyNone)
        alert.informativeText = localizer.text(.adminKeyGuidance) + "\n\n" + stored
        let field = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
        field.placeholderString = AdminKeyText.prefix(provider) + "…"
        alert.accessoryView = field
        alert.addButton(withTitle: localizer.text(.adminKeySave))
        alert.addButton(withTitle: localizer.text(.adminKeyCancel))
        if existing != nil {
            alert.addButton(withTitle: localizer.text(.adminKeyDelete)).hasDestructiveAction = true
        }
        alert.window.initialFirstResponder = field

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            let key = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty else { return false }
            guard AdminKeyText.looksLikeAdminKey(key, for: provider) else {
                fail(localizer.text(.adminKeyInvalid).replacingOccurrences(of: "{prefix}", with: AdminKeyText.prefix(provider)))
                return false
            }
            guard store.save(key, for: provider) else {
                fail(localizer.text(.adminKeySaveFailed))
                return false
            }
            return true
        case .alertThirdButtonReturn:
            store.delete(for: provider)
            return true
        default:
            return false
        }
    }

    private static func fail(_ message: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = message
        alert.runModal()
    }
}

private struct PreferencesView: View {
    static let fullHeight: CGFloat = 1180

    @ObservedObject var model: PreferencesModel
    let height: CGFloat

    var body: some View {
        let localizer = model.localizer
        Form {
            Section("Claude") {
                Toggle(localizer.text(.subscriptionLimits), isOn: $model.claudeEnabled)
                Toggle(localizer.text(.renewClaudeTokenWithCLI), isOn: $model.renewClaudeTokenWithCLI)
                    .disabled(!model.claudeEnabled)
                apiCostRows(.claude, enabled: $model.claudeCostEnabled, budget: $model.claudeMonthlyBudget)
            }

            Section("Codex") {
                Toggle(localizer.text(.subscriptionLimits), isOn: $model.codexEnabled)
                apiCostRows(.codex, enabled: $model.codexCostEnabled, budget: $model.codexMonthlyBudget)
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

    /// The organization's API cost: on or off, its Admin key, its monthly budget.
    @ViewBuilder
    private func apiCostRows(_ provider: Provider, enabled: Binding<Bool>, budget: Binding<Int>) -> some View {
        let localizer = model.localizer
        Toggle(localizer.text(.apiCost), isOn: enabled)
        LabeledContent(localizer.text(.monthlyBudget)) {
            TextField(localizer.text(.monthlyBudget), value: budget, format: .number)
                .labelsHidden()
                .multilineTextAlignment(.trailing)
                .frame(width: 90)
        }
        .disabled(!enabled.wrappedValue)
        HStack {
            Spacer()
            Button(localizer.text(.adminKeyButton)) { model.editAdminKey(provider) }
        }
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
