import AppKit
import SwiftUI

/// Owns the preferences window. The window is created once and hidden when
/// closed so that its position is kept.
@MainActor
final class SettingsWindowController {
    private let window: NSWindow

    init(prefs: Preferences, loginItem: LoginItem) {
        let hosting = NSHostingController(rootView: SettingsView(prefs: prefs, loginItem: loginItem))
        window = NSWindow(contentViewController: hosting)
        window.title = "Lithe Preferences"
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.isReleasedWhenClosed = false
        window.setFrameAutosaveName("Preferences")
    }

    func show() {
        NSApp.activate()
        if !window.isVisible {
            window.center()
        }
        window.makeKeyAndOrderFront(nil)
    }
}
