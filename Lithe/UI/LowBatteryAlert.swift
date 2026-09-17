import AppKit
import SwiftUI

/// A floating panel shown when the battery is nearly depleted.
@MainActor
final class LowBatteryAlert {
    private var panel: NSPanel?

    func show(percent: Int?, minutes: Int?, playSound: Bool) {
        let view = LowBatteryView(percent: percent, minutes: minutes, onOpenSettings: {
            SystemSettings.openBattery()
        }, onDismiss: { [weak self] in
            self?.dismiss()
        })
        let hosting = NSHostingController(rootView: view)
        let panel: NSPanel
        if let existing = self.panel {
            panel = existing
            panel.contentViewController = hosting
        } else {
            panel = NSPanel(contentViewController: hosting)
            panel.styleMask = [.titled, .closable, .utilityWindow]
            panel.title = "Low Battery"
            panel.isFloatingPanel = true
            panel.level = .floating
            panel.hidesOnDeactivate = false
            panel.isReleasedWhenClosed = false
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.center()
            self.panel = panel
        }
        NSApp.activate()
        panel.makeKeyAndOrderFront(nil)
        if playSound {
            if let sound = NSSound(named: NSSound.Name("Sosumi")) {
                sound.play()
            } else {
                NSSound.beep()
            }
        }
    }

    func dismiss() {
        panel?.orderOut(nil)
    }
}

struct LowBatteryView: View {
    var percent: Int?
    var minutes: Int?
    var onOpenSettings: () -> Void
    var onDismiss: () -> Void

    private var message: String {
        var s = "Your Mac is running on battery power and only \(TimeFormatting.percent(percent)) remains"
        if let minutes {
            s += " (about \(TimeFormatting.spoken(minutes: minutes)))"
        }
        s += ". Connect it to power now, or save your work and put it to sleep."
        return s
    }

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: "battery.25percent")
                .font(.system(size: 40))
                .foregroundStyle(.red)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 10) {
                Text("Battery nearly depleted")
                    .font(.headline)
                Text(message)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Spacer()
                    Button("Battery Settings…") { onOpenSettings() }
                    Button("OK") { onDismiss() }
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(20)
        .frame(width: 440)
    }
}

enum SystemSettings {
    /// Opens System Settings > Battery.
    static func openBattery() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Battery-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }
}
