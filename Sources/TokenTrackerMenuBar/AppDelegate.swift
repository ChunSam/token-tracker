import AppKit
import Foundation
import TokenTrackerCore
import UniformTypeIdentifiers

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let statusItemRenderer = StatusItemRenderer()
    private let settings = Settings()
    private let loginItemManager = LoginItemManager()
    private let historyStore = UsageHistoryStore()
    private lazy var usageService = UsageService(settings: settings)
    private lazy var notificationCoordinator = UsageNotificationCoordinator(settings: settings)
    private var preferencesWindowController: PreferencesWindowController?
    private var snapshot: UsageSnapshot?
    private var timer: Timer?
    private var refreshTask: Task<Void, Never>?
    private var lastSuccessfulRefreshAt: Date?
    private var appearanceObserver: NSObjectProtocol?
    private var localizer: Localizer {
        Localizer(language: settings.language)
    }
    private var diagnosticsReporter: DiagnosticsReporter {
        DiagnosticsReporter(
            settings: settings,
            historyStore: historyStore,
            snapshot: snapshot,
            lastSuccessfulRefreshAt: lastSuccessfulRefreshAt,
            runningInstanceCount: runningInstanceCount()
        )
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard !terminateIfDuplicateInstance() else { return }
        NSApp.setActivationPolicy(.accessory)
        statusItemRenderer.setPlaceholder(mode: settings.displayMode, labelStyle: settings.providerLabelStyle)
        configureMenu()
        refreshNow()
        scheduleTimer()
        observeAppearanceChanges()
        if settings.notificationsEnabled {
            notificationCoordinator.requestAuthorization()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let appearanceObserver {
            DistributedNotificationCenter.default().removeObserver(appearanceObserver)
        }
    }

    private func scheduleTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: max(60, settings.refreshInterval), repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.startRefresh(showLoadingIndicator: false)
            }
        }
    }

    @objc private func refreshNow() {
        // A manual refresh is an explicit request to fetch now, so it also
        // lifts an active pause.
        if PauseController.isPaused(until: settings.pollPausedUntil) {
            settings.pollPausedUntil = nil
        }
        startRefresh(showLoadingIndicator: true)
    }

    private func startRefresh(showLoadingIndicator: Bool) {
        guard refreshTask == nil else { return }
        if PauseController.isPaused(until: settings.pollPausedUntil) {
            // Skip the network fetch while paused; keep the menu's countdown fresh.
            configureMenu()
            return
        }
        if showLoadingIndicator || snapshot == nil {
            statusItemRenderer.setLoading(mode: settings.displayMode, labelStyle: settings.providerLabelStyle)
        }
        refreshTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { refreshTask = nil }
            let result = await usageService.refresh()
            snapshot = result
            if result.claude.source == .api || result.codex.source == .api {
                lastSuccessfulRefreshAt = result.updatedAt
            }
            historyStore.append(result, retentionDays: settings.historyRetentionDays)
            notificationCoordinator.handleNotifications(
                for: result,
                extraCandidates: forecastAlertCandidates(for: result),
                localizer: localizer
            )
            updateStatusTitle()
            configureMenu()
        }
    }

    private func updateStatusTitle() {
        statusItemRenderer.update(
            snapshot: snapshot,
            mode: settings.displayMode,
            labelStyle: settings.providerLabelStyle
        )
    }

    private func observeAppearanceChanges() {
        appearanceObserver = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("AppleInterfaceThemeChangedNotification"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.updateStatusTitle()
            }
        }
    }

    private var statusMenuActions: StatusMenuActions {
        StatusMenuActions(
            target: self,
            refreshNow: #selector(refreshNow),
            showPreferences: #selector(showPreferences),
            copyDiagnostics: #selector(copyDiagnostics),
            openClaudeCredentials: #selector(openClaudeCredentials),
            openCodexAuth: #selector(openCodexAuth),
            exportHistoryCSV: #selector(exportHistoryCSV),
            toggleLaunchAtLogin: #selector(toggleLaunchAtLogin),
            pause1h: #selector(pausePolling1h),
            pause3h: #selector(pausePolling3h),
            pauseUntilResumed: #selector(pausePollingUntilResumed),
            resumePolling: #selector(resumePolling),
            quit: #selector(quit)
        )
    }

    private func configureMenu() {
        let reporter = diagnosticsReporter
        let context = StatusMenuContext(
            localizer: localizer,
            settings: settings,
            snapshot: snapshot,
            lastSuccessfulRefreshAt: lastSuccessfulRefreshAt,
            forecastLines: forecastLines(),
            pausedRemainingText: pauseRemainingText(),
            sparklines: sparklines(),
            historyTrendText: reporter.historyTrendText(),
            launchAtLoginEnabled: loginItemManager.isEnabled,
            launchAtLoginStatus: loginItemManager.statusLabel(localizer: localizer),
            runningInstanceCount: reporter.runningInstanceCount
        )
        let menu = StatusMenuBuilder(actions: statusMenuActions, context: context).build()
        statusItemRenderer.setMenu(menu)
    }

    /// Per-provider "projected depletion" menu lines, computed from stored
    /// history (no network). Empty when the forecast display is off or there is
    /// not enough signal to project.
    private func forecastLines() -> [Provider: String] {
        guard settings.showForecast, let snapshot else { return [:] }
        let entries = historyStore.load()
        let loc = localizer
        var lines: [Provider: String] = [:]
        for provider in Provider.allCases {
            let usage = snapshot.usage(for: provider)
            let forecast = UsageForecaster.forecast(
                entries: entries,
                provider: provider,
                window: .fiveHour,
                resetAt: usage.resetAt5h
            )
            if let line = UsageForecastText.menuLine(forecast: forecast, localizer: loc) {
                lines[provider] = line
            }
        }
        return lines
    }

    /// Per-provider 5h remaining sparklines for the History submenu, built from
    /// stored history (no network). Absent when there aren't enough points.
    private func sparklines() -> [Provider: String] {
        let entries = historyStore.load()
        var lines: [Provider: String] = [:]
        for provider in Provider.allCases {
            let series = SparklineSeries.build(entries: entries, provider: provider, window: .fiveHour)
            let rendered = SparklineText.render(series)
            if !rendered.isEmpty {
                lines[provider] = "\(provider.displayName) 5h \(rendered)"
            }
        }
        return lines
    }

    /// Predictive "will empty before reset" alerts, gated by notifications +
    /// the depletion-alert toggle. Considers both the 5h and 7d windows.
    private func forecastAlertCandidates(for snapshot: UsageSnapshot) -> [UsageAlertCandidate] {
        guard settings.notificationsEnabled, settings.depletionAlertEnabled else { return [] }
        let entries = historyStore.load()
        var inputs: [ForecastAlertInput] = []
        for provider in Provider.allCases {
            let usage = snapshot.usage(for: provider)
            if let forecast = UsageForecaster.forecast(entries: entries, provider: provider, window: .fiveHour, resetAt: usage.resetAt5h, now: snapshot.updatedAt) {
                inputs.append(ForecastAlertInput(provider: provider, window: .fiveHour, forecast: forecast, resetAt: usage.resetAt5h))
            }
            if let forecast = UsageForecaster.forecast(entries: entries, provider: provider, window: .sevenDay, resetAt: usage.resetAt7d, now: snapshot.updatedAt) {
                inputs.append(ForecastAlertInput(provider: provider, window: .sevenDay, forecast: forecast, resetAt: usage.resetAt7d))
            }
        }
        return UsageForecastAlert.candidates(inputs: inputs, enabled: true, localizer: localizer)
    }

    /// The "Updates paused" menu text, or `nil` when not paused. Shows the
    /// localized "until I resume" for an indefinite pause, else a countdown.
    private func pauseRemainingText() -> String? {
        let until = settings.pollPausedUntil
        guard PauseController.isPaused(until: until) else { return nil }
        if PauseController.isIndefinite(until: until) {
            return localizer.text(.pauseUntilResumed)
        }
        return UsageForecaster.durationText(PauseController.remaining(until: until))
    }

    @objc private func pausePolling1h() { pausePolling(for: 3600) }

    @objc private func pausePolling3h() { pausePolling(for: 3 * 3600) }

    @objc private func pausePollingUntilResumed() {
        settings.pollPausedUntil = .distantFuture
        applyPauseChange()
    }

    @objc private func resumePolling() {
        settings.pollPausedUntil = nil
        applyPauseChange()
        refreshNow()
    }

    private func pausePolling(for seconds: TimeInterval) {
        settings.pollPausedUntil = Date().addingTimeInterval(seconds)
        applyPauseChange()
    }

    private func applyPauseChange() {
        updateStatusTitle()
        configureMenu()
    }

    @objc private func showPreferences() {
        if preferencesWindowController == nil {
            preferencesWindowController = PreferencesWindowController(
                settings: settings,
                onGeneralChange: { [weak self] in
                    Task { @MainActor in
                        self?.applySettingsChange()
                    }
                },
                onProviderChange: { [weak self] in
                    Task { @MainActor in
                        self?.configureMenu()
                        self?.refreshNow()
                    }
                },
                onNotificationsEnabled: { [weak self] in
                    Task { @MainActor in
                        self?.notificationCoordinator.requestAuthorization()
                        self?.configureMenu()
                    }
                }
            )
        }
        preferencesWindowController?.show()
    }

    @objc private func copyDiagnostics() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(diagnosticsReporter.diagnosticsText(), forType: .string)
    }

    @objc private func openClaudeCredentials() {
        revealInFinder(DiagnosticsReporter.claudeCredentialsURL)
    }

    @objc private func openCodexAuth() {
        revealInFinder(DiagnosticsReporter.codexAuthURL)
    }

    @objc private func exportHistoryCSV() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "token-tracker-history.csv"
        panel.allowedContentTypes = [.commaSeparatedText]
        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }

        do {
            try historyStore.csvString().write(to: url, atomically: true, encoding: .utf8)
        } catch {
            showError(localizer.text(.error), detail: error.localizedDescription)
        }
    }

    @objc private func toggleLaunchAtLogin() {
        do {
            try loginItemManager.setEnabled(!loginItemManager.isEnabled)
        } catch {
            showError(localizer.text(.launchFailed), detail: error.localizedDescription)
        }
        configureMenu()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func showError(_ title: String, detail: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = detail
        alert.alertStyle = .warning
        alert.runModal()
    }

    private func applySettingsChange() {
        scheduleTimer()
        updateStatusTitle()
        configureMenu()
    }

    private func fileExists(at url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    private func revealInFinder(_ url: URL) {
        let existingURL = fileExists(at: url) ? url : url.deletingLastPathComponent()
        NSWorkspace.shared.activateFileViewerSelecting([existingURL])
    }

    private func runningInstanceCount() -> Int {
        let bundleIdentifier = Bundle.main.bundleIdentifier ?? "local.token-tracker.menubar"
        return NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).count
    }

    /// Quit immediately when another instance is already running so a duplicate
    /// launch does not double the polling rate against the shared per-account
    /// Claude limit (parity with the Windows named-mutex guard). Returns `true`
    /// when this instance yielded and the caller must skip the rest of launch.
    private func terminateIfDuplicateInstance() -> Bool {
        let bundleIdentifier = Bundle.main.bundleIdentifier ?? "local.token-tracker.menubar"
        let current = NSRunningApplication.current
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
            .filter { $0.processIdentifier != current.processIdentifier }
            .map { InstanceArbiter.Instance(pid: $0.processIdentifier, launchDate: $0.launchDate) }
        let currentInstance = InstanceArbiter.Instance(pid: current.processIdentifier, launchDate: current.launchDate)
        guard InstanceArbiter.shouldYield(current: currentInstance, others: others) else {
            return false
        }
        NSApp.terminate(nil)
        return true
    }
}
