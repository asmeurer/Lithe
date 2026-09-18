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
    /// Re-arm gate: a warning was shown for the current discharge.
    private var warnedForThisDischarge = false
    /// The low-battery panel was put up by `checkLowBattery` (as opposed to
    /// the development flag) and has not been taken down by this code yet.
    private var panelShownAutomatically = false
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
        // Enabled states are managed explicitly in menuNeedsUpdate; automatic
        // validation would re-enable items whose target implements the action.
        menu.autoenablesItems = false
        if let button = statusItem.button {
            button.imagePosition = .imageLeading
            button.imageHugsTitle = true
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
                guard let self else { return }
                self.render(settings: settings)
                self.checkLowBattery(snapshot: self.monitor.snapshot, settings: settings)
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
                // A plain title gets the system's menu bar font and layout;
                // a custom color is added on top of that same styling so the
                // text does not change size when the color changes.
                button.title = text
                if case .custom = item.textColor {
                    let styled = NSMutableAttributedString(attributedString: button.attributedTitle)
                    styled.addAttribute(.foregroundColor, value: BatteryIconRenderer.nsColor(item.textColor),
                                        range: NSRange(location: 0, length: styled.length))
                    button.attributedTitle = styled
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
            button.image = BatteryIconRenderer.composedImage(items: items, font: Self.titleFont(of: button))
            button.title = ""
            button.imagePosition = .imageOnly
        }
    }

    /// The font the status bar button uses for a plain title, so composed
    /// images match the system's menu bar text.
    private static func titleFont(of button: NSStatusBarButton) -> NSFont {
        let hadTitle = button.title
        if hadTitle.isEmpty { button.title = "0" }
        let font = button.attributedTitle.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
        button.title = hadTitle
        return font ?? BatteryIconRenderer.menuBarFont()
    }

    private func checkLowBattery(snapshot: PowerSnapshot, settings: DisplaySettings) {
        let primary = snapshot.sources.first { $0.isPresent && $0.kind == .internalBattery }
            ?? snapshot.sources.first { $0.isPresent }
        guard let battery = primary, battery.state == .onBattery, let percent = battery.percent,
              settings.warningPanelEnabled else {
            // Plugged in, no battery, or warnings turned off: take the panel
            // down if this code put it up, and re-arm for the next discharge.
            dismissAutomaticPanel()
            warnedForThisDischarge = false
            return
        }
        if percent < settings.warningPanelPercent {
            if !warnedForThisDischarge {
                warnedForThisDischarge = true
                panelShownAutomatically = true
                lowBatteryAlert.show(percent: percent, minutes: battery.minutesToEmpty, playSound: settings.warningSoundEnabled)
            }
        } else if percent >= settings.warningPanelPercent + 5 {
            // Comfortably above the threshold again (for example after the
            // threshold was lowered): the warning no longer applies.
            dismissAutomaticPanel()
            warnedForThisDischarge = false
        }
    }

    private func dismissAutomaticPanel() {
        if panelShownAutomatically {
            lowBatteryAlert.dismiss()
            panelShownAutomatically = false
        }
    }

    // MARK: - Menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        // One query per menu open; it is a synchronous XPC call.
        let hold = SmartCharge.shared.state()

        for line in presentation.summaryLines {
            menu.addItem(disabled(line))
        }
        for line in detailLines(hold: hold) {
            menu.addItem(disabled(line))
        }
        menu.addItem(.separator())

        if let hold = chargeHoldState(hold) {
            // The same action as the system battery menu's "Charge to Full Now".
            let charge = NSMenuItem(title: "Charge to Full Now", action: #selector(chargeToFullNow), keyEquivalent: "")
            charge.target = self
            charge.isEnabled = hold.overrideAllowed
            if !hold.overrideAllowed {
                charge.toolTip = "The system is not allowing a charging override right now."
            }
            menu.addItem(charge)
            menu.addItem(.separator())
        }

        let preferences = NSMenuItem(title: "Preferences…", action: #selector(openPreferencesAction), keyEquivalent: ",")
        preferences.target = self
        menu.addItem(preferences)

        let battery = NSMenuItem(title: "Battery Settings…", action: #selector(openBatterySettings), keyEquivalent: "")
        battery.target = self
        menu.addItem(battery)

        loginItem.refresh()
        let login = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        login.target = self
        if loginItem.isTranslocated {
            // A quarantined app running from a translocated copy cannot be
            // registered at a stable path; the preferences window explains.
            login.isEnabled = false
            login.toolTip = "Move Lithe to your Applications folder and open it again to enable this."
        } else if loginItem.requiresApproval {
            login.state = .mixed
            login.title = "Launch at Login (needs approval in System Settings)"
        } else {
            login.state = loginItem.isEnabled ? .on : .off
        }
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
    private func detailLines(hold: SmartCharge.State?) -> [String] {
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
        if let hold, hold.chargeLimitEnabled, hold.chargeLimit < 100 {
            lines.append("Charge limit: \(hold.chargeLimit)%")
        }
        return lines
    }

    /// The charge-hold state when the charge is being held (per the system or
    /// per the snapshot), otherwise `nil`.
    private func chargeHoldState(_ state: SmartCharge.State?) -> SmartCharge.State? {
        guard let state else { return nil }
        let onHold = monitor.snapshot.sources.contains { $0.isPresent && $0.chargeOnHold }
        return (state.isHolding || onHold) ? state : nil
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

    @objc private func chargeToFullNow() {
        do {
            try SmartCharge.shared.chargeToFullNow()
            // Charging resumes within a few seconds; IOKit will notify.
        } catch {
            NSApp.activate()
            let alert = NSAlert()
            alert.messageText = "Could not start charging to full"
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
    }

    @objc private func toggleLaunchAtLogin() {
        if loginItem.requiresApproval {
            loginItem.openSystemSettings()
            return
        }
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
        NSApp.orderFrontStandardAboutPanel(options: [.credits: Self.aboutCredits()])
    }

    static func aboutCredits() -> NSAttributedString {
        let font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        let credits = NSMutableAttributedString(string: "A slim battery meter for the menu bar.\n", attributes: [.font: font])
        let link = NSAttributedString(string: AppInfo.repositoryURL.absoluteString,
                                      attributes: [.font: font, .link: AppInfo.repositoryURL])
        credits.append(link)
        return credits
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
        loginItem.refresh()
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
            // Unregister unconditionally: the cached status may be stale, and
            // unregistering an item that is not registered is harmless.
            loginItem.setEnabled(false)
            if let error = loginItem.lastError {
                NSLog("Lithe: could not remove the login item: \(error)")
                let failed = NSAlert()
                failed.messageText = "Lithe could not remove itself from your login items"
                failed.informativeText = "\(error)\n\nLithe will quit now. If it comes back after your next login, remove it in System Settings > General > Login Items."
                failed.runModal()
            }
            NSApp.terminate(nil)
        default:
            if alreadyHidden {
                showItem()
            }
        }
    }
}
