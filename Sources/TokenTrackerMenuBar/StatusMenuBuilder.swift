import AppKit
import Foundation
import TokenTrackerCore

struct StatusMenuActions {
    let target: AnyObject
    let refreshNow: Selector
    let showPreferences: Selector
    let copyDiagnostics: Selector
    let openClaudeCredentials: Selector
    let openCodexAuth: Selector
    let exportHistoryCSV: Selector
    let toggleLaunchAtLogin: Selector
    let pause1h: Selector
    let pause3h: Selector
    let pauseUntilResumed: Selector
    let resumePolling: Selector
    let quit: Selector
}

struct StatusMenuContext {
    let localizer: Localizer
    let settings: Settings
    let snapshot: UsageSnapshot?
    let lastSuccessfulRefreshAt: Date?
    let forecastLines: [Provider: String]
    let pausedRemainingText: String?
    let sparklines: [Provider: String]
    let historyTrendText: String
    let launchAtLoginEnabled: Bool
    let launchAtLoginStatus: String
    let runningInstanceCount: Int
}

@MainActor
struct StatusMenuBuilder {
    let actions: StatusMenuActions
    let context: StatusMenuContext

    func build() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false

        if let snapshot = context.snapshot {
            addUsage(snapshot.claude, to: menu)
            menu.addItem(.separator())
            addUsage(snapshot.codex, to: menu)
            menu.addItem(.separator())
            menu.addItem(infoItem("\(context.localizer.text(.updated)) \(relative(snapshot.updatedAt))"))
            if let lastSuccessfulRefreshAt = context.lastSuccessfulRefreshAt {
                menu.addItem(infoItem("\(context.localizer.text(.lastSuccessfulUpdate)): \(relative(lastSuccessfulRefreshAt))"))
            } else {
                menu.addItem(infoItem(context.localizer.text(.noSuccessfulUpdate)))
            }
        } else {
            menu.addItem(infoItem(context.localizer.text(.noUsageLoaded)))
        }

        menu.addItem(.separator())
        addAction(
            title: context.localizer.text(.refreshNow),
            selector: actions.refreshNow,
            keyEquivalent: "r",
            to: menu
        )
        addAction(
            title: context.localizer.text(.preferences),
            selector: actions.showPreferences,
            keyEquivalent: ",",
            to: menu
        )

        addPauseControls(to: menu)
        menu.addItem(diagnosticsItem())
        menu.addItem(historyItem())
        menu.addItem(.separator())
        addLaunchAtLogin(to: menu)
        addAction(title: context.localizer.text(.quit), selector: actions.quit, keyEquivalent: "q", to: menu)

        return menu
    }

    private func addPauseControls(to menu: NSMenu) {
        if let remaining = context.pausedRemainingText {
            menu.addItem(infoItem("\(context.localizer.text(.updatesPaused)): \(remaining)"))
            addAction(title: context.localizer.text(.resumeNow), selector: actions.resumePolling, to: menu)
        }

        let pauseMenu = NSMenu()
        pauseMenu.autoenablesItems = false
        addAction(title: context.localizer.text(.pause1h), selector: actions.pause1h, to: pauseMenu)
        addAction(title: context.localizer.text(.pause3h), selector: actions.pause3h, to: pauseMenu)
        addAction(title: context.localizer.text(.pauseUntilResumed), selector: actions.pauseUntilResumed, to: pauseMenu)

        let pauseItem = NSMenuItem(title: context.localizer.text(.pausePolling), action: nil, keyEquivalent: "")
        pauseItem.submenu = pauseMenu
        menu.addItem(pauseItem)
    }

    private func diagnosticsItem() -> NSMenuItem {
        let diagnosticsMenu = NSMenu()
        diagnosticsMenu.autoenablesItems = false
        addAction(
            title: context.localizer.text(.copyDiagnostics),
            selector: actions.copyDiagnostics,
            to: diagnosticsMenu
        )
        diagnosticsMenu.addItem(.separator())
        addAction(
            title: context.localizer.text(.openClaudeCredentials),
            selector: actions.openClaudeCredentials,
            to: diagnosticsMenu
        )
        addAction(
            title: context.localizer.text(.openCodexAuth),
            selector: actions.openCodexAuth,
            to: diagnosticsMenu
        )
        diagnosticsMenu.addItem(.separator())
        diagnosticsMenu.addItem(infoItem("\(context.localizer.text(.duplicateInstances)): \(context.runningInstanceCount)"))
        if context.settings.refreshInterval < 300 {
            diagnosticsMenu.addItem(infoItem(context.localizer.text(.refreshIntervalWarning)))
        }

        let diagnostics = NSMenuItem(title: context.localizer.text(.diagnostics), action: nil, keyEquivalent: "")
        diagnostics.submenu = diagnosticsMenu
        return diagnostics
    }

    private func historyItem() -> NSMenuItem {
        let historyMenu = NSMenu()
        historyMenu.autoenablesItems = false
        historyMenu.addItem(infoItem(context.historyTrendText))
        for provider in Provider.allCases {
            if let sparkline = context.sparklines[provider] {
                historyMenu.addItem(infoItem(sparkline))
            }
        }
        historyMenu.addItem(infoItem("\(context.localizer.text(.historyRetentionDays)): \(context.settings.historyRetentionDays)d"))
        historyMenu.addItem(.separator())
        addAction(
            title: context.localizer.text(.exportHistoryCSV),
            selector: actions.exportHistoryCSV,
            to: historyMenu
        )

        let history = NSMenuItem(title: context.localizer.text(.history), action: nil, keyEquivalent: "")
        history.submenu = historyMenu
        return history
    }

    private func addLaunchAtLogin(to menu: NSMenu) {
        let item = NSMenuItem(
            title: "\(context.localizer.text(.launchAtLogin)): \(context.launchAtLoginStatus)",
            action: actions.toggleLaunchAtLogin,
            keyEquivalent: ""
        )
        item.target = actions.target
        item.state = context.launchAtLoginEnabled ? .on : .off
        menu.addItem(item)
    }

    private func addUsage(_ usage: ProviderUsage, to menu: NSMenu) {
        let issue = UsageIssueFormatter.issue(for: usage, localizer: context.localizer)
        menu.addItem(infoItem(DisplayFormatter.detailLine(usage)))
        menu.addItem(infoItem("  \(context.localizer.text(.status)): \(issue.title)"))
        menu.addItem(infoItem("  \(issue.detail)"))
        if let recovery = issue.recovery {
            menu.addItem(infoItem("  \(context.localizer.text(.recovery)): \(recovery)"))
        }
        if let forecastLine = context.forecastLines[usage.provider] {
            menu.addItem(infoItem("  \(forecastLine)"))
        }
        menu.addItem(infoItem("  \(context.localizer.text(.fiveHourReset)): \(DisplayFormatter.formatReset(usage.resetAt5h, localizer: context.localizer))"))
        menu.addItem(infoItem("  \(context.localizer.text(.sevenDayReset)): \(DisplayFormatter.formatReset(usage.resetAt7d, localizer: context.localizer))"))
        menu.addItem(infoItem("  \(context.localizer.text(.source)): \(usage.source.rawValue)"))
        if let error = issue.technicalDetail {
            menu.addItem(infoItem("  \(context.localizer.text(.technicalError)): \(error)"))
        }
        if let plan = usage.plan {
            menu.addItem(infoItem("  \(context.localizer.text(.plan)): \(plan)"))
        }
    }

    private func addAction(
        title: String,
        selector: Selector,
        keyEquivalent: String = "",
        to menu: NSMenu
    ) {
        let item = NSMenuItem(title: title, action: selector, keyEquivalent: keyEquivalent)
        item.target = actions.target
        menu.addItem(item)
    }

    private func infoItem(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.view = InfoMenuItemView(title: title)
        return item
    }

    private func relative(_ date: Date) -> String {
        let seconds = Int(Date().timeIntervalSince(date))
        if seconds < 60 { return "\(seconds)s \(context.localizer.text(.ago))" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes)m \(context.localizer.text(.ago))" }
        return "\(minutes / 60)h \(context.localizer.text(.ago))"
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
