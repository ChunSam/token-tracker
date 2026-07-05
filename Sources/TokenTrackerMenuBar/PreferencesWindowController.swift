import AppKit
import TokenTrackerCore

@MainActor
final class PreferencesWindowController: NSWindowController {
    private let settings: Settings
    private let onGeneralChange: () -> Void
    private let onProviderChange: () -> Void
    private let onNotificationsEnabled: () -> Void

    private lazy var claudeEnabled = NSButton(checkboxWithTitle: "Claude", target: self, action: #selector(toggleProvider(_:)))
    private lazy var codexEnabled = NSButton(checkboxWithTitle: "Codex", target: self, action: #selector(toggleProvider(_:)))
    private lazy var displayMode = NSPopUpButton()
    private lazy var labelStyle = NSPopUpButton()
    private lazy var refreshInterval = NSPopUpButton()
    private lazy var language = NSPopUpButton()
    private lazy var notificationsEnabled = NSButton(checkboxWithTitle: localizer.text(.statusEnabled), target: self, action: #selector(toggleNotifications))
    private lazy var fiveHourValue = NSTextField(labelWithString: "")
    private lazy var fiveHourStepper = NSStepper()
    private lazy var sevenDayValue = NSTextField(labelWithString: "")
    private lazy var sevenDayStepper = NSStepper()
    private lazy var resetValue = NSTextField(labelWithString: "")
    private lazy var resetStepper = NSStepper()
    private lazy var historyValue = NSTextField(labelWithString: "")
    private lazy var historyStepper = NSStepper()

    private var localizer: Localizer {
        Localizer(language: settings.language)
    }

    init(
        settings: Settings,
        onGeneralChange: @escaping () -> Void,
        onProviderChange: @escaping () -> Void,
        onNotificationsEnabled: @escaping () -> Void
    ) {
        self.settings = settings
        self.onGeneralChange = onGeneralChange
        self.onProviderChange = onProviderChange
        self.onNotificationsEnabled = onNotificationsEnabled
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 420),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Token Tracker"
        window.isReleasedWhenClosed = false
        super.init(window: window)
        buildContent()
        reload()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show() {
        reload()
        showWindow(nil)
        window?.center()
        NSApp.activate(ignoringOtherApps: true)
    }

    private func buildContent() {
        guard let contentView = window?.contentView else {
            return
        }

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 14
        stack.edgeInsets = NSEdgeInsets(top: 18, left: 18, bottom: 18, right: 18)
        stack.translatesAutoresizingMaskIntoConstraints = false

        displayMode.target = self
        displayMode.action = #selector(selectDisplayMode)
        labelStyle.target = self
        labelStyle.action = #selector(selectLabelStyle)
        refreshInterval.target = self
        refreshInterval.action = #selector(selectRefreshInterval)
        language.target = self
        language.action = #selector(selectLanguage)

        configureStepper(fiveHourStepper, min: 0, max: 100, action: #selector(changeFiveHourThreshold))
        configureStepper(sevenDayStepper, min: 0, max: 100, action: #selector(changeSevenDayThreshold))
        configureStepper(resetStepper, min: 0, max: 1440, action: #selector(changeResetAlertMinutes))
        configureStepper(historyStepper, min: 1, max: 365, action: #selector(changeHistoryRetention))

        stack.addArrangedSubview(section(localizer.text(.providers), views: [claudeEnabled, codexEnabled]))
        stack.addArrangedSubview(row(label: localizer.text(.displayMode), control: displayMode))
        stack.addArrangedSubview(row(label: localizer.text(.providerLabelStyle), control: labelStyle))
        stack.addArrangedSubview(row(label: localizer.text(.refreshInterval), control: refreshInterval))
        stack.addArrangedSubview(row(label: localizer.text(.language), control: language))
        stack.addArrangedSubview(section(localizer.text(.notifications), views: [notificationsEnabled]))
        stack.addArrangedSubview(stepperRow(label: localizer.text(.fiveHourAlertThreshold), value: fiveHourValue, stepper: fiveHourStepper))
        stack.addArrangedSubview(stepperRow(label: localizer.text(.sevenDayAlertThreshold), value: sevenDayValue, stepper: sevenDayStepper))
        stack.addArrangedSubview(stepperRow(label: localizer.text(.resetAlertMinutes), value: resetValue, stepper: resetStepper))
        stack.addArrangedSubview(stepperRow(label: localizer.text(.historyRetentionDays), value: historyValue, stepper: historyStepper))

        contentView.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            stack.topAnchor.constraint(equalTo: contentView.topAnchor),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor)
        ])
    }

    private func reload() {
        claudeEnabled.state = settings.claudeEnabled ? .on : .off
        codexEnabled.state = settings.codexEnabled ? .on : .off
        notificationsEnabled.state = settings.notificationsEnabled ? .on : .off

        reloadPopup(displayMode, values: DisplayMode.allCases.map { ($0.label, $0.rawValue) }, selected: settings.displayMode.rawValue)
        reloadPopup(labelStyle, values: ProviderLabelStyle.allCases.map { ($0.label, $0.rawValue) }, selected: settings.providerLabelStyle.rawValue)
        reloadPopup(refreshInterval, values: [(title: "1m", value: "60"), (title: "5m", value: "300"), (title: "15m", value: "900")], selected: String(Int(settings.refreshInterval)))
        reloadPopup(language, values: AppLanguage.allCases.map { ($0.label, $0.rawValue) }, selected: settings.language.rawValue)

        fiveHourStepper.integerValue = settings.fiveHourAlertThreshold
        sevenDayStepper.integerValue = settings.sevenDayAlertThreshold
        resetStepper.integerValue = settings.resetAlertMinutes
        historyStepper.integerValue = settings.historyRetentionDays
        updateStepperLabels()
    }

    private func reloadPopup(_ popup: NSPopUpButton, values: [(title: String, value: String)], selected: String) {
        popup.removeAllItems()
        for item in values {
            popup.addItem(withTitle: item.title)
            popup.lastItem?.representedObject = item.value
        }
        if let item = popup.itemArray.first(where: { $0.representedObject as? String == selected }) {
            popup.select(item)
        }
    }

    private func updateStepperLabels() {
        fiveHourValue.stringValue = "\(settings.fiveHourAlertThreshold)%"
        sevenDayValue.stringValue = "\(settings.sevenDayAlertThreshold)%"
        resetValue.stringValue = "\(settings.resetAlertMinutes)m"
        historyValue.stringValue = "\(settings.historyRetentionDays)d"
    }

    @objc private func toggleProvider(_ sender: NSButton) {
        if sender === claudeEnabled {
            settings.claudeEnabled = sender.state == .on
        } else {
            settings.codexEnabled = sender.state == .on
        }
        onProviderChange()
    }

    @objc private func selectDisplayMode() {
        if let raw = displayMode.selectedItem?.representedObject as? String,
           let value = DisplayMode(rawValue: raw) {
            settings.displayMode = value
            onGeneralChange()
        }
    }

    @objc private func selectLabelStyle() {
        if let raw = labelStyle.selectedItem?.representedObject as? String,
           let value = ProviderLabelStyle(rawValue: raw) {
            settings.providerLabelStyle = value
            onGeneralChange()
        }
    }

    @objc private func selectRefreshInterval() {
        if let raw = refreshInterval.selectedItem?.representedObject as? String,
           let value = TimeInterval(raw) {
            settings.refreshInterval = value
            onGeneralChange()
        }
    }

    @objc private func selectLanguage() {
        if let raw = language.selectedItem?.representedObject as? String,
           let value = AppLanguage(rawValue: raw) {
            settings.language = value
            onGeneralChange()
        }
    }

    @objc private func toggleNotifications() {
        settings.notificationsEnabled = notificationsEnabled.state == .on
        if settings.notificationsEnabled {
            onNotificationsEnabled()
        } else {
            onGeneralChange()
        }
    }

    @objc private func changeFiveHourThreshold() {
        settings.fiveHourAlertThreshold = fiveHourStepper.integerValue
        updateStepperLabels()
        onGeneralChange()
    }

    @objc private func changeSevenDayThreshold() {
        settings.sevenDayAlertThreshold = sevenDayStepper.integerValue
        updateStepperLabels()
        onGeneralChange()
    }

    @objc private func changeResetAlertMinutes() {
        settings.resetAlertMinutes = resetStepper.integerValue
        updateStepperLabels()
        onGeneralChange()
    }

    @objc private func changeHistoryRetention() {
        settings.historyRetentionDays = historyStepper.integerValue
        updateStepperLabels()
        onGeneralChange()
    }

    private func configureStepper(_ stepper: NSStepper, min: Double, max: Double, action: Selector) {
        stepper.minValue = min
        stepper.maxValue = max
        stepper.increment = 1
        stepper.target = self
        stepper.action = action
    }

    private func section(_ title: String, views: [NSView]) -> NSView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.addArrangedSubview(header(title))
        for view in views {
            stack.addArrangedSubview(view)
        }
        return stack
    }

    private func row(label: String, control: NSView) -> NSView {
        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 12
        let labelView = NSTextField(labelWithString: label)
        labelView.widthAnchor.constraint(equalToConstant: 160).isActive = true
        control.widthAnchor.constraint(greaterThanOrEqualToConstant: 160).isActive = true
        stack.addArrangedSubview(labelView)
        stack.addArrangedSubview(control)
        return stack
    }

    private func stepperRow(label: String, value: NSTextField, stepper: NSStepper) -> NSView {
        let valueStack = NSStackView()
        valueStack.orientation = .horizontal
        valueStack.alignment = .centerY
        valueStack.spacing = 8
        value.widthAnchor.constraint(equalToConstant: 52).isActive = true
        valueStack.addArrangedSubview(value)
        valueStack.addArrangedSubview(stepper)
        return row(label: label, control: valueStack)
    }

    private func header(_ title: String) -> NSTextField {
        let label = NSTextField(labelWithString: title)
        label.font = .boldSystemFont(ofSize: NSFont.systemFontSize)
        return label
    }
}
