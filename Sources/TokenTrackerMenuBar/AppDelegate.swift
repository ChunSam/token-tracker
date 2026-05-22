import AppKit
import Foundation
import TokenTrackerCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let settings = Settings()
    private let loginItemManager = LoginItemManager()
    private lazy var usageService = UsageService(settings: settings)
    private var snapshot: UsageSnapshot?
    private var timer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        statusItem.button?.title = "AI --"
        configureMenu()
        refreshNow()
        scheduleTimer()
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
        statusItem.button?.title = "AI ..."
        Task { @MainActor in
            let result = await usageService.refresh()
            snapshot = result
            updateStatusTitle()
            configureMenu()
        }
    }

    private func updateStatusTitle() {
        statusItem.button?.title = DisplayFormatter.statusTitle(snapshot: snapshot, mode: settings.displayMode)
        if let percent = activePercent() {
            statusItem.button?.contentTintColor = tintColor(for: percent)
        } else {
            statusItem.button?.contentTintColor = nil
        }
    }

    private func activePercent() -> Int? {
        guard let snapshot else { return nil }
        switch settings.displayMode {
        case .lowestRemaining, .both:
            return [snapshot.claude.remainingPercent5h, snapshot.codex.remainingPercent5h].compactMap { $0 }.min()
        case .codexOnly:
            return snapshot.codex.remainingPercent5h
        }
    }

    private func tintColor(for remaining: Int) -> NSColor? {
        if remaining < 20 { return .systemRed }
        if remaining < 50 { return .systemOrange }
        return nil
    }

    private func configureMenu() {
        let menu = NSMenu()

        if let snapshot {
            addUsage(snapshot.claude, to: menu)
            menu.addItem(.separator())
            addUsage(snapshot.codex, to: menu)
            menu.addItem(.separator())
            menu.addItem(NSMenuItem(title: "Updated \(relative(snapshot.updatedAt))", action: nil, keyEquivalent: ""))
        } else {
            menu.addItem(NSMenuItem(title: "No usage loaded yet", action: nil, keyEquivalent: ""))
        }

        menu.addItem(.separator())
        let refresh = NSMenuItem(title: "Refresh Now", action: #selector(refreshNow), keyEquivalent: "r")
        refresh.target = self
        menu.addItem(refresh)

        let displayMenu = NSMenu()
        for mode in DisplayMode.allCases {
            let item = NSMenuItem(title: mode.label, action: #selector(selectDisplayMode(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = mode.rawValue
            item.state = settings.displayMode == mode ? .on : .off
            displayMenu.addItem(item)
        }
        let display = NSMenuItem(title: "Display Mode", action: nil, keyEquivalent: "")
        display.submenu = displayMenu
        menu.addItem(display)

        let launchAtLogin = NSMenuItem(
            title: "Launch at Login: \(loginItemManager.statusLabel)",
            action: #selector(toggleLaunchAtLogin),
            keyEquivalent: ""
        )
        launchAtLogin.target = self
        launchAtLogin.state = loginItemManager.isEnabled ? .on : .off
        menu.addItem(launchAtLogin)

        let quit = NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        statusItem.menu = menu
    }

    private func addUsage(_ usage: ProviderUsage, to menu: NSMenu) {
        menu.addItem(NSMenuItem(title: DisplayFormatter.detailLine(usage), action: nil, keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "  5h reset: \(DisplayFormatter.formatReset(usage.resetAt5h))", action: nil, keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "  7d reset: \(DisplayFormatter.formatReset(usage.resetAt7d))", action: nil, keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "  Source: \(usage.source.rawValue)", action: nil, keyEquivalent: ""))
        if let error = usage.error {
            menu.addItem(NSMenuItem(title: "  Error: \(error)", action: nil, keyEquivalent: ""))
        }
        if let plan = usage.plan {
            menu.addItem(NSMenuItem(title: "  Plan: \(plan)", action: nil, keyEquivalent: ""))
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

    @objc private func toggleLaunchAtLogin() {
        do {
            try loginItemManager.setEnabled(!loginItemManager.isEnabled)
        } catch {
            showError("Launch at Login failed", detail: error.localizedDescription)
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
        if minutes < 60 { return "\(minutes)m ago" }
        return "\(minutes / 60)h ago"
    }
}
