import AppKit

@main
enum LitheMain {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        // `NSApplication.delegate` is unretained; keep ours alive for the
        // whole run loop rather than trusting the local's lifetime.
        withExtendedLifetime(delegate) {
            app.run()
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var prefs: Preferences?
    private var loginItem: LoginItem?
    private var settingsController: SettingsWindowController?
    private var statusController: StatusItemController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let prefs = Preferences()
        prefs.importLegacySettingsIfNeeded()
        let loginItem = LoginItem()
        let settings = SettingsWindowController(prefs: prefs, loginItem: loginItem)
        let status = StatusItemController(prefs: prefs, loginItem: loginItem) { [weak settings] in
            settings?.show()
        }
        self.prefs = prefs
        self.loginItem = loginItem
        self.settingsController = settings
        self.statusController = status

        installMainMenu()
        status.start()

        // Development aid: `Lithe.app/Contents/MacOS/Lithe --show-low-battery-panel`
        // shows the warning panel without waiting for a real low battery.
        if CommandLine.arguments.contains("--show-low-battery-panel") {
            status.showLowBatteryPanelForTesting()
        }
    }

    /// Opening the app again (for example double-clicking it in the Finder)
    /// brings the menu bar item back if it was removed and shows preferences.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        statusController?.showItem()
        settingsController?.show()
        return false
    }

    /// The app has no visible main menu (it lives in the menu bar), but a
    /// main menu is still needed for standard key equivalents such as ⌘W and
    /// ⌘Q to work in the preferences window.
    private func installMainMenu() {
        let mainMenu = NSMenu()

        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About Lithe", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        let preferences = appMenu.addItem(withTitle: "Preferences…", action: #selector(openPreferences), keyEquivalent: ",")
        preferences.target = self
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide Lithe", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(withTitle: "Quit Lithe", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        mainMenu.addItem(appItem)

        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = editMenu
        mainMenu.addItem(editItem)

        let windowItem = NSMenuItem()
        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowItem.submenu = windowMenu
        mainMenu.addItem(windowItem)

        NSApp.mainMenu = mainMenu
        NSApp.windowsMenu = windowMenu
    }

    @objc private func openPreferences() {
        settingsController?.show()
    }
}
