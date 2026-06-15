import AppKit
import Foundation
import TokenTrackerCore
import UniformTypeIdentifiers
import UserNotifications

private enum StatusSegment {
    case icon(NSImage)
    case text(String, NSColor)
    case separator
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let settings = Settings()
    private let loginItemManager = LoginItemManager()
    private let historyStore = UsageHistoryStore()
    private lazy var usageService = UsageService(settings: settings)
    private var preferencesWindowController: PreferencesWindowController?
    private var snapshot: UsageSnapshot?
    private var timer: Timer?
    private var refreshTask: Task<Void, Never>?
    private var lastSuccessfulRefreshAt: Date?
    private var deliveredAlertIDs = Set<String>()
    private lazy var claudeIcon = loadIcon(named: "claudeTemplate@2x")
    private lazy var codexIcon = loadIcon(named: "codexTemplate@2x")
    private let sevenDayWarningColor = NSColor(red: 1.0, green: 0.54, blue: 0.56, alpha: 1.0)
    private let refreshIntervalOptions: [TimeInterval] = [30, 60, 300]
    private let statusItemHorizontalPadding: CGFloat = 10
    private var appearanceObserver: NSObjectProtocol?
    private var localizer: Localizer {
        Localizer(language: settings.language)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        setStatusTitle("AI --")
        configureMenu()
        refreshNow()
        scheduleTimer()
        observeAppearanceChanges()
        if settings.notificationsEnabled {
            requestNotificationAuthorization()
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
            setStatusTitle("AI ...")
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
            handleNotifications(for: result)
            updateStatusTitle()
            configureMenu()
        }
    }

    private func updateStatusTitle() {
        if let snapshot {
            let textColor = statusTextColor
            setStatusSegments(
                statusSegments(
                    snapshot: snapshot,
                    mode: settings.displayMode,
                    labelStyle: settings.providerLabelStyle,
                    baseColor: textColor,
                    warningColor: statusWarningColor
                ),
                iconTint: textColor
            )
        } else {
            setStatusTitle(DisplayFormatter.statusTitle(snapshot: snapshot, mode: settings.displayMode))
        }
    }

    private func setStatusTitle(_ title: String) {
        guard let button = statusItem.button else { return }
        let image = statusTitleImage(title, color: statusTextColor)
        setStatusImage(image, on: button)
    }

    private func setStatusSegments(_ segments: [StatusSegment], iconTint: NSColor) {
        guard let button = statusItem.button else { return }
        let image = statusTitleImage(segments: segments, iconTint: iconTint)
        setStatusImage(image, on: button)
    }

    private func setStatusImage(_ image: NSImage, on button: NSStatusBarButton) {
        let targetLength = max(image.size.width + statusItemHorizontalPadding, reservedStatusItemLength())
        if abs(statusItem.length - targetLength) > 0.5 {
            statusItem.length = targetLength
        }
        button.title = ""
        button.attributedTitle = NSAttributedString(string: "")
        button.contentTintColor = nil
        button.image = image
        button.imagePosition = .imageOnly
    }

    private func reservedStatusItemLength() -> CGFloat {
        let sampleSnapshot = UsageSnapshot(
            claude: sampleUsage(.claude),
            codex: sampleUsage(.codex),
            updatedAt: Date()
        )

        let image: NSImage
        if settings.providerLabelStyle == .icon {
            image = statusTitleImage(
                segments: statusSegments(
                    snapshot: sampleSnapshot,
                    mode: settings.displayMode,
                    labelStyle: settings.providerLabelStyle,
                    baseColor: statusTextColor,
                    warningColor: statusWarningColor
                ),
                iconTint: statusTextColor
            )
        } else {
            image = statusTitleImage(
                DisplayFormatter.statusTitle(
                    snapshot: sampleSnapshot,
                    mode: settings.displayMode,
                    labelStyle: settings.providerLabelStyle
                ),
                color: statusTextColor
            )
        }

        return image.size.width + statusItemHorizontalPadding
    }

    private func sampleUsage(_ provider: Provider) -> ProviderUsage {
        ProviderUsage(
            provider: provider,
            remainingPercent5h: 100,
            remainingPercent7d: 100,
            resetAt5h: nil,
            resetAt7d: nil,
            source: .api,
            error: nil,
            plan: nil,
            model: nil,
            updatedAt: Date()
        )
    }

    private func statusTitleImage(_ title: String, color: NSColor) -> NSImage {
        let font = NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color
        ]
        let textSize = ceilSize((title as NSString).size(withAttributes: attributes))
        let image = NSImage(size: NSSize(width: textSize.width, height: 18))
        image.isTemplate = false

        image.lockFocus()
        NSColor.clear.setFill()
        NSRect(origin: .zero, size: image.size).fill()
        let y = floor((image.size.height - textSize.height) / 2)
        (title as NSString).draw(
            at: NSPoint(x: 0, y: y),
            withAttributes: attributes
        )
        image.unlockFocus()

        return image
    }

    private func statusTitleImage(segments: [StatusSegment], iconTint: NSColor) -> NSImage {
        let font = NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: iconTint
        ]
        let iconSize = NSSize(width: 14, height: 14)
        let spacing: CGFloat = 5
        let separatorSpacing: CGFloat = 8
        let height: CGFloat = 18

        let width = segments.reduce(CGFloat(0)) { total, segment in
            switch segment {
            case .icon:
                return total + iconSize.width + spacing
            case .text(let text, _):
                return total + ceil((text as NSString).size(withAttributes: attributes).width)
            case .separator:
                return total + separatorSpacing + ceil(("·" as NSString).size(withAttributes: attributes).width) + separatorSpacing
            }
        }

        let image = NSImage(size: NSSize(width: ceil(width), height: height))
        image.isTemplate = false
        image.lockFocus()
        NSColor.clear.setFill()
        NSRect(origin: .zero, size: image.size).fill()

        var x: CGFloat = 0
        for segment in segments {
            switch segment {
            case .icon(let icon):
                let rect = NSRect(x: x, y: floor((height - iconSize.height) / 2), width: iconSize.width, height: iconSize.height)
                drawIcon(icon, in: rect, tint: iconTint)
                x += iconSize.width + spacing
            case .text(let text, let color):
                var textAttributes = attributes
                textAttributes[.foregroundColor] = color
                let textSize = (text as NSString).size(withAttributes: textAttributes)
                (text as NSString).draw(at: NSPoint(x: x, y: floor((height - textSize.height) / 2)), withAttributes: textAttributes)
                x += ceil(textSize.width)
            case .separator:
                x += separatorSpacing
                let text = "·"
                let textSize = (text as NSString).size(withAttributes: attributes)
                (text as NSString).draw(at: NSPoint(x: x, y: floor((height - textSize.height) / 2)), withAttributes: attributes)
                x += ceil(textSize.width) + separatorSpacing
            }
        }

        image.unlockFocus()
        return image
    }

    private func ceilSize(_ size: NSSize) -> NSSize {
        NSSize(width: ceil(size.width), height: ceil(size.height))
    }

    private func statusSegments(
        snapshot: UsageSnapshot,
        mode: DisplayMode,
        labelStyle: ProviderLabelStyle,
        baseColor: NSColor,
        warningColor: NSColor
    ) -> [StatusSegment] {
        switch mode {
        case .lowestRemaining:
            let usages = [snapshot.claude, snapshot.codex]
            let lowest = usages.compactMap { DisplayFormatter.displayPercent($0) }.min()
            let color = usages.contains { usage in
                DisplayFormatter.displayPercent(usage) == lowest && DisplayFormatter.displaysSevenDayPercent(usage)
            } ? warningColor : baseColor
            return [.text("AI ", baseColor), .text(DisplayFormatter.formatPercent(lowest), color)]
        case .both:
            if labelStyle == .icon {
                return [
                    .icon(codexIcon),
                    percentSegment(snapshot.codex, baseColor: baseColor, warningColor: warningColor),
                    .separator,
                    .icon(claudeIcon),
                    percentSegment(snapshot.claude, baseColor: baseColor, warningColor: warningColor)
                ]
            }
            return [
                .text("\(DisplayFormatter.providerLabel(.codex, style: labelStyle)) ", baseColor),
                percentSegment(snapshot.codex, baseColor: baseColor, warningColor: warningColor),
                .separator,
                .text("\(DisplayFormatter.providerLabel(.claude, style: labelStyle)) ", baseColor),
                percentSegment(snapshot.claude, baseColor: baseColor, warningColor: warningColor)
            ]
        case .codexOnly:
            if labelStyle == .icon {
                return [.icon(codexIcon), percentSegment(snapshot.codex, baseColor: baseColor, warningColor: warningColor)]
            }
            return [
                .text("\(DisplayFormatter.providerLabel(.codex, style: labelStyle)) ", baseColor),
                percentSegment(snapshot.codex, baseColor: baseColor, warningColor: warningColor)
            ]
        case .claudeOnly:
            if labelStyle == .icon {
                return [.icon(claudeIcon), percentSegment(snapshot.claude, baseColor: baseColor, warningColor: warningColor)]
            }
            return [
                .text("\(DisplayFormatter.providerLabel(.claude, style: labelStyle)) ", baseColor),
                percentSegment(snapshot.claude, baseColor: baseColor, warningColor: warningColor)
            ]
        }
    }

    private func percentSegment(_ usage: ProviderUsage, baseColor: NSColor, warningColor: NSColor) -> StatusSegment {
        let color = DisplayFormatter.displaysSevenDayPercent(usage)
            ? warningColor
            : baseColor
        return .text(DisplayFormatter.formatPercent(DisplayFormatter.displayPercent(usage)), color)
    }

    private func loadIcon(named name: String) -> NSImage {
        if let url = Bundle.module.url(forResource: name, withExtension: "png"),
           let image = NSImage(contentsOf: url) {
            return image
        }
        return NSImage(size: NSSize(width: 14, height: 14))
    }

    private func drawIcon(_ icon: NSImage, in rect: NSRect, tint: NSColor) {
        NSGraphicsContext.saveGraphicsState()
        tint.setFill()
        rect.fill()
        icon.draw(in: rect, from: .zero, operation: .destinationIn, fraction: 1.0)
        NSGraphicsContext.restoreGraphicsState()
    }

    private var statusTextColor: NSColor {
        guard
            let appearance = statusItem.button?.effectiveAppearance,
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        else {
            return .black
        }
        return .white
    }

    private var statusWarningColor: NSColor {
        sevenDayWarningColor
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

    private func configureMenu() {
        let menu = NSMenu()
        menu.autoenablesItems = false

        if let snapshot {
            addUsage(snapshot.claude, to: menu)
            menu.addItem(.separator())
            addUsage(snapshot.codex, to: menu)
            menu.addItem(.separator())
            menu.addItem(infoItem("\(localizer.text(.updated)) \(relative(snapshot.updatedAt))"))
            if let lastSuccessfulRefreshAt {
                menu.addItem(infoItem("\(localizer.text(.lastSuccessfulUpdate)): \(relative(lastSuccessfulRefreshAt))"))
            } else {
                menu.addItem(infoItem(localizer.text(.noSuccessfulUpdate)))
            }
        } else {
            menu.addItem(infoItem(localizer.text(.noUsageLoaded)))
        }

        menu.addItem(.separator())
        let refresh = NSMenuItem(title: localizer.text(.refreshNow), action: #selector(refreshNow), keyEquivalent: "r")
        refresh.target = self
        menu.addItem(refresh)
        let preferences = NSMenuItem(title: localizer.text(.preferences), action: #selector(showPreferences), keyEquivalent: ",")
        preferences.target = self
        menu.addItem(preferences)

        let diagnosticsMenu = NSMenu()
        diagnosticsMenu.autoenablesItems = false
        let copyDiagnosticsItem = NSMenuItem(title: localizer.text(.copyDiagnostics), action: #selector(copyDiagnostics), keyEquivalent: "")
        copyDiagnosticsItem.target = self
        diagnosticsMenu.addItem(copyDiagnosticsItem)
        diagnosticsMenu.addItem(.separator())
        let openClaudeCredentials = NSMenuItem(title: localizer.text(.openClaudeCredentials), action: #selector(openClaudeCredentials), keyEquivalent: "")
        openClaudeCredentials.target = self
        diagnosticsMenu.addItem(openClaudeCredentials)
        let openCodexAuth = NSMenuItem(title: localizer.text(.openCodexAuth), action: #selector(openCodexAuth), keyEquivalent: "")
        openCodexAuth.target = self
        diagnosticsMenu.addItem(openCodexAuth)
        diagnosticsMenu.addItem(.separator())
        diagnosticsMenu.addItem(infoItem("\(localizer.text(.duplicateInstances)): \(runningInstanceCount())"))
        if settings.refreshInterval < 60 {
            diagnosticsMenu.addItem(infoItem(localizer.text(.refreshIntervalWarning)))
        }
        let diagnostics = NSMenuItem(title: localizer.text(.diagnostics), action: nil, keyEquivalent: "")
        diagnostics.submenu = diagnosticsMenu
        menu.addItem(diagnostics)

        let historyMenu = NSMenu()
        historyMenu.autoenablesItems = false
        historyMenu.addItem(infoItem(historyTrendText()))
        historyMenu.addItem(infoItem("\(localizer.text(.historyRetentionDays)): \(settings.historyRetentionDays)d"))
        historyMenu.addItem(.separator())
        let exportHistory = NSMenuItem(title: localizer.text(.exportHistoryCSV), action: #selector(exportHistoryCSV), keyEquivalent: "")
        exportHistory.target = self
        historyMenu.addItem(exportHistory)
        let history = NSMenuItem(title: localizer.text(.history), action: nil, keyEquivalent: "")
        history.submenu = historyMenu
        menu.addItem(history)

        let displayMenu = NSMenu()
        displayMenu.autoenablesItems = false
        for mode in DisplayMode.allCases {
            let item = NSMenuItem(title: mode.label, action: #selector(selectDisplayMode(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = mode.rawValue
            item.state = settings.displayMode == mode ? .on : .off
            displayMenu.addItem(item)
        }
        let display = NSMenuItem(title: localizer.text(.displayMode), action: nil, keyEquivalent: "")
        display.submenu = displayMenu
        menu.addItem(display)

        let labelStyleMenu = NSMenu()
        labelStyleMenu.autoenablesItems = false
        for style in ProviderLabelStyle.allCases {
            let item = NSMenuItem(title: providerLabelStyleTitle(style), action: #selector(selectProviderLabelStyle(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = style.rawValue
            item.state = settings.providerLabelStyle == style ? .on : .off
            labelStyleMenu.addItem(item)
        }
        let labelStyle = NSMenuItem(title: localizer.text(.providerLabelStyle), action: nil, keyEquivalent: "")
        labelStyle.submenu = labelStyleMenu
        menu.addItem(labelStyle)

        let providersMenu = NSMenu()
        providersMenu.autoenablesItems = false
        for provider in Provider.allCases {
            let item = NSMenuItem(title: provider.displayName, action: #selector(toggleProvider(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = provider.rawValue
            item.state = isProviderEnabled(provider) ? .on : .off
            providersMenu.addItem(item)
        }
        let providers = NSMenuItem(title: localizer.text(.providers), action: nil, keyEquivalent: "")
        providers.submenu = providersMenu
        menu.addItem(providers)

        let notificationsMenu = NSMenu()
        notificationsMenu.autoenablesItems = false
        let notificationsEnabled = NSMenuItem(title: localizer.text(.statusEnabled), action: #selector(toggleNotifications), keyEquivalent: "")
        notificationsEnabled.target = self
        notificationsEnabled.state = settings.notificationsEnabled ? .on : .off
        notificationsMenu.addItem(notificationsEnabled)
        notificationsMenu.addItem(.separator())
        notificationsMenu.addItem(infoItem("\(localizer.text(.fiveHourAlertThreshold)): \(settings.fiveHourAlertThreshold)%"))
        notificationsMenu.addItem(infoItem("\(localizer.text(.sevenDayAlertThreshold)): \(settings.sevenDayAlertThreshold)%"))
        notificationsMenu.addItem(infoItem("\(localizer.text(.resetAlertMinutes)): \(settings.resetAlertMinutes)m"))
        let notifications = NSMenuItem(title: localizer.text(.notifications), action: nil, keyEquivalent: "")
        notifications.submenu = notificationsMenu
        menu.addItem(notifications)

        let refreshIntervalMenu = NSMenu()
        refreshIntervalMenu.autoenablesItems = false
        for option in refreshIntervalOptions {
            let item = NSMenuItem(title: refreshIntervalTitle(option), action: #selector(selectRefreshInterval(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = NSNumber(value: option)
            item.state = abs(settings.refreshInterval - option) < 0.5 ? .on : .off
            refreshIntervalMenu.addItem(item)
        }
        let refreshInterval = NSMenuItem(title: localizer.text(.refreshInterval), action: nil, keyEquivalent: "")
        refreshInterval.submenu = refreshIntervalMenu
        menu.addItem(refreshInterval)

        let languageMenu = NSMenu()
        languageMenu.autoenablesItems = false
        for language in AppLanguage.allCases {
            let item = NSMenuItem(title: language.label, action: #selector(selectLanguage(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = language.rawValue
            item.state = settings.language == language ? .on : .off
            languageMenu.addItem(item)
        }
        let language = NSMenuItem(title: localizer.text(.language), action: nil, keyEquivalent: "")
        language.submenu = languageMenu
        menu.addItem(language)

        let launchAtLogin = NSMenuItem(
            title: "\(localizer.text(.launchAtLogin)): \(loginItemManager.statusLabel(localizer: localizer))",
            action: #selector(toggleLaunchAtLogin),
            keyEquivalent: ""
        )
        launchAtLogin.target = self
        launchAtLogin.state = loginItemManager.isEnabled ? NSControl.StateValue.on : NSControl.StateValue.off
        menu.addItem(launchAtLogin)

        let quit = NSMenuItem(title: localizer.text(.quit), action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        statusItem.menu = menu
    }

    private func isProviderEnabled(_ provider: Provider) -> Bool {
        switch provider {
        case .claude:
            return settings.claudeEnabled
        case .codex:
            return settings.codexEnabled
        }
    }

    private func setProvider(_ provider: Provider, enabled: Bool) {
        switch provider {
        case .claude:
            settings.claudeEnabled = enabled
        case .codex:
            settings.codexEnabled = enabled
        }
    }

    private func addUsage(_ usage: ProviderUsage, to menu: NSMenu) {
        let issue = UsageIssueFormatter.issue(for: usage, localizer: localizer)
        menu.addItem(infoItem(DisplayFormatter.detailLine(usage)))
        menu.addItem(infoItem("  \(localizer.text(.status)): \(issue.title)"))
        menu.addItem(infoItem("  \(issue.detail)"))
        if let recovery = issue.recovery {
            menu.addItem(infoItem("  \(localizer.text(.recovery)): \(recovery)"))
        }
        menu.addItem(infoItem("  \(localizer.text(.fiveHourReset)): \(DisplayFormatter.formatReset(usage.resetAt5h, localizer: localizer))"))
        menu.addItem(infoItem("  \(localizer.text(.sevenDayReset)): \(DisplayFormatter.formatReset(usage.resetAt7d, localizer: localizer))"))
        menu.addItem(infoItem("  \(localizer.text(.source)): \(usage.source.rawValue)"))
        if let error = issue.technicalDetail {
            menu.addItem(infoItem("  \(localizer.text(.technicalError)): \(error)"))
        }
        if let plan = usage.plan {
            menu.addItem(infoItem("  \(localizer.text(.plan)): \(plan)"))
        }
    }

    private func infoItem(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.view = InfoMenuItemView(title: title)
        return item
    }

    private func providerLabelStyleTitle(_ style: ProviderLabelStyle) -> String {
        switch style {
        case .abbreviation:
            return "Cdx / Cl"
        case .icon:
            return "Official icons"
        }
    }

    private func refreshIntervalTitle(_ interval: TimeInterval) -> String {
        let seconds = Int(interval)
        if seconds < 60 {
            return "\(seconds)s"
        }
        return "\(seconds / 60)m"
    }

    @objc private func selectDisplayMode(_ sender: NSMenuItem) {
        guard
            let raw = sender.representedObject as? String,
            let mode = DisplayMode(rawValue: raw)
        else {
            return
        }
        settings.displayMode = mode
        updateStatusTitle()
        configureMenu()
    }

    @objc private func selectProviderLabelStyle(_ sender: NSMenuItem) {
        guard
            let raw = sender.representedObject as? String,
            let style = ProviderLabelStyle(rawValue: raw)
        else {
            return
        }
        settings.providerLabelStyle = style
        updateStatusTitle()
        configureMenu()
    }

    @objc private func toggleProvider(_ sender: NSMenuItem) {
        guard
            let raw = sender.representedObject as? String,
            let provider = Provider(rawValue: raw)
        else {
            return
        }
        setProvider(provider, enabled: !isProviderEnabled(provider))
        configureMenu()
        refreshNow()
    }

    @objc private func selectRefreshInterval(_ sender: NSMenuItem) {
        guard let interval = (sender.representedObject as? NSNumber)?.doubleValue else {
            return
        }
        settings.refreshInterval = interval
        scheduleTimer()
        configureMenu()
    }

    @objc private func selectLanguage(_ sender: NSMenuItem) {
        guard
            let raw = sender.representedObject as? String,
            let language = AppLanguage(rawValue: raw)
        else {
            return
        }
        settings.language = language
        configureMenu()
    }

    @objc private func toggleNotifications() {
        settings.notificationsEnabled.toggle()
        if settings.notificationsEnabled {
            requestNotificationAuthorization()
        } else {
            deliveredAlertIDs.removeAll()
        }
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
                        self?.requestNotificationAuthorization()
                        self?.configureMenu()
                    }
                }
            )
        }
        preferencesWindowController?.show()
    }

    @objc private func copyDiagnostics() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(diagnosticsText(), forType: .string)
    }

    @objc private func openClaudeCredentials() {
        revealInFinder(claudeCredentialsURL())
    }

    @objc private func openCodexAuth() {
        revealInFinder(codexAuthURL())
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

    private func handleNotifications(for snapshot: UsageSnapshot) {
        guard settings.notificationsEnabled else {
            deliveredAlertIDs.removeAll()
            return
        }

        let candidates = UsageAlertEvaluator.candidates(
            snapshot: snapshot,
            settings: alertSettings(),
            localizer: localizer
        )
        let activeIDs = Set(candidates.map(\.id))
        deliveredAlertIDs.formIntersection(activeIDs)

        for candidate in candidates where !deliveredAlertIDs.contains(candidate.id) {
            sendNotification(candidate)
            deliveredAlertIDs.insert(candidate.id)
        }
    }

    private func alertSettings() -> UsageAlertSettings {
        UsageAlertSettings(
            notificationsEnabled: settings.notificationsEnabled,
            fiveHourThreshold: settings.fiveHourAlertThreshold,
            sevenDayThreshold: settings.sevenDayAlertThreshold,
            resetWarningMinutes: settings.resetAlertMinutes
        )
    }

    private func requestNotificationAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private func sendNotification(_ candidate: UsageAlertCandidate) {
        let content = UNMutableNotificationContent()
        content.title = candidate.title
        content.body = candidate.body
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: "TokenTracker.\(candidate.id)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    private func diagnosticsText() -> String {
        var lines: [String] = []
        lines.append("Token Tracker Diagnostics")
        lines.append("Generated: \(isoString(Date()))")
        lines.append("App version: \(appVersion) (\(appBuild))")
        lines.append("Bundle id: \(Bundle.main.bundleIdentifier ?? "unknown")")
        lines.append("macOS: \(ProcessInfo.processInfo.operatingSystemVersionString)")
        lines.append("Architecture: \(machineArchitecture())")
        lines.append("Display mode: \(settings.displayMode.rawValue)")
        lines.append("Provider labels: \(settings.providerLabelStyle.rawValue)")
        lines.append("Refresh interval: \(Int(settings.refreshInterval))s")
        lines.append("Claude enabled: \(settings.claudeEnabled)")
        lines.append("Codex enabled: \(settings.codexEnabled)")
        lines.append("Language: \(settings.language.rawValue)")
        lines.append("Notifications enabled: \(settings.notificationsEnabled)")
        lines.append("5h alert threshold: \(settings.fiveHourAlertThreshold)%")
        lines.append("7d alert threshold: \(settings.sevenDayAlertThreshold)%")
        lines.append("Reset alert window: \(settings.resetAlertMinutes)m")
        lines.append("History retention: \(settings.historyRetentionDays)d")
        lines.append("History entries: \(historyStore.load().count)")
        lines.append("History trend: \(historyTrendText(language: .english))")
        lines.append("Last successful update: \(lastSuccessfulRefreshAt.map(isoString) ?? "none")")
        lines.append("Running instances: \(runningInstanceCount())")
        if settings.refreshInterval < 60 {
            lines.append("Refresh warning: \(Localizer(language: .english).text(.refreshIntervalWarning))")
        }
        lines.append("Claude credentials file exists: \(fileExists(at: claudeCredentialsURL()))")
        lines.append("Codex auth file exists: \(fileExists(at: codexAuthURL()))")

        if let snapshot {
            lines.append("Snapshot updated: \(isoString(snapshot.updatedAt))")
            lines.append(contentsOf: diagnosticsLines(for: snapshot.claude))
            lines.append(contentsOf: diagnosticsLines(for: snapshot.codex))
        } else {
            lines.append("Snapshot: none")
        }

        return lines.joined(separator: "\n")
    }

    private func diagnosticsLines(for usage: ProviderUsage) -> [String] {
        let issue = UsageIssueFormatter.issue(for: usage, localizer: Localizer(language: .english))
        return [
            "\(usage.provider.displayName) source: \(usage.source.rawValue)",
            "\(usage.provider.displayName) status: \(issue.kind.rawValue)",
            "\(usage.provider.displayName) 5h remaining: \(DisplayFormatter.formatPercent(usage.remainingPercent5h))",
            "\(usage.provider.displayName) 7d remaining: \(DisplayFormatter.formatPercent(usage.remainingPercent7d))",
            "\(usage.provider.displayName) 5h reset: \(isoStringOrDash(usage.resetAt5h))",
            "\(usage.provider.displayName) 7d reset: \(isoStringOrDash(usage.resetAt7d))",
            "\(usage.provider.displayName) plan: \(usage.plan ?? "--")",
            "\(usage.provider.displayName) technical error: \(issue.technicalDetail ?? "--")"
        ]
    }

    private func historyTrendText(language: AppLanguage? = nil) -> String {
        guard let snapshot else {
            return Localizer(language: language ?? settings.language).text(.notEnoughHistory)
        }
        return UsageHistoryFormatter.trendSummary(
            entries: historyStore.load(),
            current: snapshot,
            localizer: Localizer(language: language ?? settings.language)
        )
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
    }

    private var appBuild: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"
    }

    private func machineArchitecture() -> String {
        #if arch(arm64)
        return "arm64"
        #elseif arch(x86_64)
        return "x86_64"
        #else
        return "unknown"
        #endif
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

    private func claudeCredentialsURL() -> URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/.credentials.json")
    }

    private func codexAuthURL() -> URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex/auth.json")
    }

    private func isoString(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }

    private func isoStringOrDash(_ date: Date?) -> String {
        guard let date else { return "--" }
        return isoString(date)
    }

    private func relative(_ date: Date) -> String {
        let seconds = Int(Date().timeIntervalSince(date))
        if seconds < 60 { return "\(seconds)s \(localizer.text(.ago))" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes)m \(localizer.text(.ago))" }
        return "\(minutes / 60)h \(localizer.text(.ago))"
    }
}

private final class InfoMenuItemView: NSView {
    private let label: NSTextField
    private static let horizontalPadding: CGFloat = 28
    private static let maxWidth: CGFloat = 360

    init(title: String) {
        label = NSTextField(labelWithString: title)
        let textWidth = ceil((title as NSString).size(withAttributes: [.font: NSFont.menuFont(ofSize: 0)]).width)
        let width = min(max(textWidth + Self.horizontalPadding, 220), Self.maxWidth)
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: 24))

        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .menuFont(ofSize: 0)
        label.textColor = .labelColor
        label.backgroundColor = .clear
        label.lineBreakMode = .byTruncatingTail
        label.maximumNumberOfLines = 1

        addSubview(label)

        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            label.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
