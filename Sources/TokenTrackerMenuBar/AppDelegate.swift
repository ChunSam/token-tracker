import AppKit
import Foundation
import TokenTrackerCore

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
    private lazy var usageService = UsageService(settings: settings)
    private var snapshot: UsageSnapshot?
    private var timer: Timer?
    private var refreshTask: Task<Void, Never>?
    private lazy var claudeIcon = loadIcon(named: "claudeTemplate@2x")
    private lazy var codexIcon = loadIcon(named: "codexTemplate@2x")
    private let sevenDayWarningColor = NSColor(red: 1.0, green: 0.54, blue: 0.56, alpha: 1.0)
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
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let appearanceObserver {
            DistributedNotificationCenter.default().removeObserver(appearanceObserver)
        }
    }

    private func scheduleTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: settings.refreshInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refreshNow()
            }
        }
    }

    @objc private func refreshNow() {
        guard refreshTask == nil else { return }
        setStatusTitle("AI ...")
        refreshTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { refreshTask = nil }
            let result = await usageService.refresh()
            snapshot = result
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
        statusItem.length = image.size.width + 10
        button.title = ""
        button.attributedTitle = NSAttributedString(string: "")
        button.contentTintColor = nil
        button.image = image
        button.imagePosition = .imageOnly
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
        } else {
            menu.addItem(infoItem(localizer.text(.noUsageLoaded)))
        }

        menu.addItem(.separator())
        let refresh = NSMenuItem(title: localizer.text(.refreshNow), action: #selector(refreshNow), keyEquivalent: "r")
        refresh.target = self
        menu.addItem(refresh)

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

    private func addUsage(_ usage: ProviderUsage, to menu: NSMenu) {
        menu.addItem(infoItem(DisplayFormatter.detailLine(usage)))
        menu.addItem(infoItem("  \(localizer.text(.fiveHourReset)): \(DisplayFormatter.formatReset(usage.resetAt5h, localizer: localizer))"))
        menu.addItem(infoItem("  \(localizer.text(.sevenDayReset)): \(DisplayFormatter.formatReset(usage.resetAt7d, localizer: localizer))"))
        menu.addItem(infoItem("  \(localizer.text(.source)): \(usage.source.rawValue)"))
        if let error = usage.error {
            menu.addItem(infoItem("  \(localizer.text(.error)): \(error)"))
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

    private func relative(_ date: Date) -> String {
        let seconds = Int(Date().timeIntervalSince(date))
        if seconds < 60 { return "\(seconds)s ago" }
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
