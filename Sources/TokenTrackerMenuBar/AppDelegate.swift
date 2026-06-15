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
        timer = Timer.scheduledTimer(withTimeInterval: max(15, settings.refreshInterval), repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.startRefresh(showLoadingIndicator: false)
            }
        }
    }

    @objc private func refreshNow() {
        startRefresh(showLoadingIndicator: true)
    }

    private func startRefresh(showLoadingIndicator: Bool) {
        guard refreshTask == nil else { return }
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
            notificationCoordinator.handleNotifications(for: result, localizer: localizer)
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
            historyTrendText: reporter.historyTrendText(),
            launchAtLoginEnabled: loginItemManager.isEnabled,
            launchAtLoginStatus: loginItemManager.statusLabel(localizer: localizer),
            runningInstanceCount: reporter.runningInstanceCount
        )
        let menu = StatusMenuBuilder(actions: statusMenuActions, context: context).build()
        statusItemRenderer.setMenu(menu)
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
}
