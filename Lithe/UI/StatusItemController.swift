import AppKit
import Combine
import IOKit.ps

/// Owns the menu bar item: renders the battery into it, builds its menu, and
/// reacts to power changes, preference changes, and removal by the user.
@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    /// Width of the (invisible) item when the settings hide the display, so
    /// that the menu can still be opened by clicking where the item would be.
    static let hiddenLength: CGFloat = 8

    private let statusItem: NSStatusItem
    private let menu = NSMenu()
    private let monitor = PowerMonitor()
    private let prefs: Preferences
    private let loginItem: LoginItem
    private let openPreferences: () -> Void
    private let lowBatteryAlert = LowBatteryAlert()
    private var cancellables = Set<AnyCancellable>()
    private var visibilityObservation: NSKeyValueObservation?
    private let weakSelf = WeakBox<StatusItemController>()
    private var changingVisibility = false
    private var warnedForThisDischarge = false
    private(set) var presentation = StatusPresentation(items: [], summaryLines: [])

    init(prefs: Preferences, loginItem: LoginItem, openPreferences: @escaping () -> Void) {
        self.prefs = prefs
        self.loginItem = loginItem
        self.openPreferences = openPreferences
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        weakSelf.value = self

        statusItem.behavior = .removalAllowed
        statusItem.isVisible = true
        statusItem.menu = menu
        menu.delegate = self
        if let button = statusItem.button {
            button.imagePosition = .imageLeading
            button.imageHugsTitle = true
            button.font = BatteryIconRenderer.menuBarFont()
        }

        let box = weakSelf
        visibilityObservation = statusItem.observe(\.isVisible, options: [.new]) { _, change in
            guard change.newValue == false else { return }
            MainActor.assumeIsolated { box.value?.itemWasRemovedByUser() }
        }
    }

    func start() {
        monitor.onChange = { [weak self] snapshot in
            self?.snapshotChanged(snapshot)
        }
        prefs.$settings
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] settings in
                self?.render(settings: settings)
            }
            .store(in: &cancellables)
        monitor.start()
    }

    /// Shows the low-battery panel with sample values (development aid).
    func showLowBatteryPanelForTesting() {
        lowBatteryAlert.show(percent: 9, minutes: 17, playSound: prefs.settings.warningSoundEnabled)
    }

    /// Makes the item visible again after "remove until next launch".
    func showItem() {
        changingVisibility = true
        statusItem.isVisible = true
        changingVisibility = false
    }

    // MARK: - Updates

    private func snapshotChanged(_ snapshot: PowerSnapshot) {
        render(settings: prefs.settings)
        checkLowBattery(snapshot: snapshot, settings: prefs.settings)
    }

    private func render(settings: DisplaySettings) {
        presentation = StatusPresentation.make(snapshot: monitor.snapshot, settings: settings)
        guard let button = statusItem.button else { return }
        button.toolTip = presentation.tooltip

        let items = presentation.items.filter { !$0.isEmpty }
        if items.isEmpty {
            button.image = nil
            button.title = ""
            button.imagePosition = .noImage
            statusItem.length = Self.hiddenLength
            return
        }
        statusItem.length = NSStatusItem.variableLength

        if items.count == 1 {
            let item = items[0]
            button.image = item.icon.map(BatteryIconRenderer.image(for:))
            if let text = item.text {
                switch item.textColor {
                case .automatic, .dimmed:
                    // A plain title gets the system's menu bar text styling.
                    button.title = text
                case .custom:
                    button.attributedTitle = NSAttributedString(string: text, attributes: [
                        .font: BatteryIconRenderer.menuBarFont(),
                        .foregroundColor: BatteryIconRenderer.nsColor(item.textColor),
                    ])
                }
            } else {
                button.title = ""
            }
            if item.icon == nil {
                button.imagePosition = .noImage
            } else if item.text == nil {
                button.imagePosition = .imageOnly
            } else {
                button.imagePosition = .imageLeading
            }
        } else {
            button.image = BatteryIconRenderer.composedImage(items: items)
            button.title = ""
            button.imagePosition = .imageOnly
        }
    }

    private func checkLowBattery(snapshot: PowerSnapshot, settings: DisplaySettings) {
        let primary = snapshot.sources.first { $0.isPresent && $0.kind == .internalBattery }
            ?? snapshot.sources.first { $0.isPresent }
        guard let battery = primary, battery.state == .onBattery, let percent = battery.percent else {
            // Plugged in (or no battery): reset so the next discharge warns again.
            warnedForThisDischarge = false
            lowBatteryAlert.dismiss()
            return
        }
        if settings.warningPanelEnabled, percent < settings.warningPanelPercent {
            if !warnedForThisDischarge {
                warnedForThisDischarge = true
                lowBatteryAlert.show(percent: percent, minutes: battery.minutesToEmpty, playSound: settings.warningSoundEnabled)
            }
        } else if percent >= settings.warningPanelPercent + 5 {
            warnedForThisDischarge = false
        }
    }

    // MARK: - Menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        for line in presentation.summaryLines {
            menu.addItem(disabled(line))
        }
        for line in detailLines() {
            menu.addItem(disabled(line))
        }
        menu.addItem(.separator())

        let preferences = NSMenuItem(title: "Preferences…", action: #selector(openPreferencesAction), keyEquivalent: ",")
        preferences.target = self
        menu.addItem(preferences)

        let battery = NSMenuItem(title: "Battery Settings…", action: #selector(openBatterySettings), keyEquivalent: "")
        battery.target = self
        menu.addItem(battery)

        let login = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        login.target = self
        loginItem.refresh()
        login.state = loginItem.isEnabled ? .on : .off
        menu.addItem(login)
        menu.addItem(.separator())

        let about = NSMenuItem(title: "About Lithe", action: #selector(showAbout), keyEquivalent: "")
        about.target = self
        menu.addItem(about)

        let github = NSMenuItem(title: "Lithe on GitHub", action: #selector(openRepository), keyEquivalent: "")
        github.target = self
        menu.addItem(github)
        menu.addItem(.separator())

        let remove = NSMenuItem(title: "Remove from Menu Bar…", action: #selector(removeFromMenuBar), keyEquivalent: "")
        remove.target = self
        menu.addItem(remove)

        let quit = NSMenuItem(title: "Quit Lithe", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)
    }

    private func disabled(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    /// Battery health and power details shown under the status line.
    private func detailLines() -> [String] {
        var lines: [String] = []
        let snapshot = monitor.snapshot
        let hasBattery = snapshot.sources.contains { $0.isPresent && $0.kind == .internalBattery }
        guard hasBattery, let health = BatteryHealth.read() else { return lines }
        if let cycles = health.cycleCount {
            lines.append("Cycle count: \(cycles)")
        }
        if let capacity = health.maximumCapacityPercent {
            lines.append("Maximum capacity: \(capacity)%")
        }
        if let condition = snapshot.sources.first(where: { $0.kind == .internalBattery })?.healthCondition {
            lines.append("Condition: \(condition)")
        }
        if let watts = health.watts, abs(watts) >= 0.05 {
            let direction = watts < 0 ? "from battery" : "into battery"
            lines.append(String(format: "Power: %.1f W %@", abs(watts), direction))
        }
        if let adapter = Self.adapterWatts() {
            lines.append("Power adapter: \(adapter) W")
        }
        return lines
    }

    private static func adapterWatts() -> Int? {
        guard let details = IOPSCopyExternalPowerAdapterDetails()?.takeRetainedValue() as? [String: Any],
              let watts = details[kIOPSPowerAdapterWattsKey] as? NSNumber else { return nil }
        return watts.intValue
    }

    // MARK: - Actions

    @objc private func openPreferencesAction() {
        openPreferences()
    }

    @objc private func openBatterySettings() {
        SystemSettings.openBattery()
    }

    @objc private func toggleLaunchAtLogin() {
        loginItem.setEnabled(!loginItem.isEnabled)
        if let error = loginItem.lastError {
            NSApp.activate()
            let alert = NSAlert()
            alert.messageText = "Could not change the login item"
            alert.informativeText = error
            alert.runModal()
        }
    }

    @objc private func showAbout() {
        NSApp.activate()
        NSApp.orderFrontStandardAboutPanel(options: [
            .credits: NSAttributedString(string: "A slim battery meter for the menu bar.\nhttps://github.com/asmeurer/Lithe"),
        ])
    }

    @objc private func openRepository() {
        NSWorkspace.shared.open(AppInfo.repositoryURL)
    }

    @objc private func removeFromMenuBar() {
        askRemoveOnceOrForever(alreadyHidden: false)
    }

    /// Called when the user Cmd-drags the item out of the menu bar. The
    /// notification arrives during the system's drag session, so the modal
    /// alert is deferred by one run loop turn to let the drag finish.
    private func itemWasRemovedByUser() {
        guard !changingVisibility else { return }
        Task { @MainActor [weak self] in
            self?.askRemoveOnceOrForever(alreadyHidden: true)
        }
    }

    private func askRemoveOnceOrForever(alreadyHidden: Bool) {
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = "Remove Lithe from the menu bar?"
        alert.informativeText = """
            Remove once: the icon disappears until you next log in or open Lithe again.

            Remove forever: Lithe quits and is removed from your login items. To bring it back later, simply open Lithe again.
            """
        alert.addButton(withTitle: "Remove Once")
        alert.addButton(withTitle: "Remove Forever")
        alert.addButton(withTitle: "Cancel")
        let response = alert.runModal()
        switch response {
        case .alertFirstButtonReturn:
            if !alreadyHidden {
                changingVisibility = true
                statusItem.isVisible = false
                changingVisibility = false
            }
        case .alertSecondButtonReturn:
            if loginItem.isEnabled {
                loginItem.setEnabled(false)
            }
            NSApp.terminate(nil)
        default:
            if alreadyHidden {
                showItem()
            }
        }
    }
}
