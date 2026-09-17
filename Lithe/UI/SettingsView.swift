import AppKit
import SwiftUI

/// The preferences window content.
struct SettingsView: View {
    @ObservedObject var prefs: Preferences
    @ObservedObject var loginItem: LoginItem

    var body: some View {
        TabView {
            DisplayTab(settings: $prefs.settings)
                .tabItem { Label("Display", systemImage: "menubar.rectangle") }
            AppearanceTab(settings: $prefs.settings)
                .tabItem { Label("Appearance", systemImage: "paintpalette") }
            GeneralTab(prefs: prefs, loginItem: loginItem)
                .tabItem { Label("General", systemImage: "gearshape") }
        }
        .frame(minWidth: 500, idealWidth: 500, minHeight: 560, idealHeight: 720)
    }
}

// MARK: - Display

struct DisplayTab: View {
    @Binding var settings: DisplaySettings

    var body: some View {
        Form {
            Section("What to show") {
                modePicker("On battery:", selection: $settings.onBatteryMode)
                modePicker("Charging:", selection: $settings.chargingMode)
                modePicker("Charged or plugged in:", selection: $settings.chargedMode)
                if settings.hidesEverything {
                    Text("These settings hide the menu bar item in every state. Its menu stays available by clicking where it would be, and opening Lithe again from the Finder shows the preferences.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            Section("Other power sources") {
                Toggle("Show a gray outline for a removed battery", isOn: $settings.showRemovedBattery)
                Toggle("Show a connected UPS as a battery", isOn: $settings.showUPS)
                Toggle("Reverse the order of multiple batteries", isOn: $settings.reverseOrder)
            }
            Section("Warnings") {
                Toggle("Show a warning panel when the charge is low", isOn: $settings.warningPanelEnabled)
                LabeledContent("Warn when the charge drops below:") {
                    PercentStepper(value: $settings.warningPanelPercent)
                }
                .disabled(!settings.warningPanelEnabled)
                Toggle("Play a sound with the warning", isOn: $settings.warningSoundEnabled)
                    .disabled(!settings.warningPanelEnabled)
            }
        }
        .formStyle(.grouped)
    }

    private func modePicker(_ title: String, selection: Binding<DisplayMode>) -> some View {
        Picker(title, selection: selection) {
            ForEach(DisplayMode.allCases) { mode in
                Text(mode.title).tag(mode)
            }
        }
    }
}

// MARK: - Appearance

struct AppearanceTab: View {
    @Binding var settings: DisplaySettings

    var body: some View {
        Form {
            Section("Preview") {
                PreviewStrip(settings: settings)
            }
            Section("Shape") {
                Picker("Icon shape:", selection: $settings.shape) {
                    ForEach(IconShape.allCases) { shape in
                        Text(shape.title).tag(shape)
                    }
                }
            }
            Section("Colors") {
                ColorSettingRow(title: "On battery:", setting: $settings.onBatteryColor, fallback: .currentLabel)
                ColorSettingRow(title: "Charging:", setting: $settings.chargingColor, fallback: .orange)
                ColorSettingRow(title: "Charged:", setting: $settings.chargedColor, fallback: .green)
                ColorSettingRow(title: "Outline and text:", setting: $settings.outlineColor, fallback: .currentLabel)
                Text("Automatic colors follow the menu bar, so they stay readable on light and dark backgrounds.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Section("Low charge") {
                Toggle("Use a warning color when the charge is low", isOn: $settings.lowColorEnabled)
                LabeledContent("Use it when the charge drops below:") {
                    PercentStepper(value: $settings.lowColorPercent)
                }
                .disabled(!settings.lowColorEnabled)
                // An automatic warning color would look like the normal
                // color, so this one is always a chosen color.
                ColorSettingRow(title: "Warning color:", setting: $settings.lowColor, fallback: .red, allowsAutomatic: false)
                    .disabled(!settings.lowColorEnabled)
            }
        }
        .formStyle(.grouped)
    }
}

/// Shows the icon in each state, using the current settings.
struct PreviewStrip: View {
    var settings: DisplaySettings

    private var samples: [(String, PowerSource)] {
        [
            ("On battery", PowerSource(state: .onBattery, charge: 0.72, minutesToEmpty: 150)),
            ("Charging", PowerSource(state: .charging, charge: 0.45, minutesToFull: 70)),
            ("Charged", PowerSource(state: .charged, charge: 1.0, isCharged: true)),
            ("Low", PowerSource(state: .onBattery, charge: 0.08, minutesToEmpty: 12)),
        ]
    }

    var body: some View {
        HStack(spacing: 24) {
            ForEach(samples, id: \.0) { name, source in
                VStack(spacing: 6) {
                    let presentation = StatusPresentation.make(
                        snapshot: PowerSnapshot(sources: [source], externalPowerConnected: source.state != .onBattery),
                        settings: settings)
                    if let image = BatteryIconRenderer.composedImage(items: presentation.items) {
                        Image(nsImage: image)
                    } else {
                        Text("hidden").font(.caption).foregroundStyle(.tertiary)
                    }
                    Text(name).font(.caption).foregroundStyle(.secondary)
                }
                .frame(minWidth: 70)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
    }
}

struct ColorSettingRow: View {
    let title: String
    @Binding var setting: ColorSetting
    /// The color to start from when switching from automatic to custom (for
    /// the first time; afterwards the last chosen color is restored).
    let fallback: RGBA
    var allowsAutomatic: Bool = true
    @State private var lastCustom: RGBA?

    var body: some View {
        LabeledContent(title) {
            HStack(spacing: 12) {
                ColorPicker("", selection: Binding(
                    get: { Color(rgba: setting.customColor ?? lastCustom ?? fallback) },
                    set: { setting = .custom(RGBA(color: $0)) }
                ), supportsOpacity: false)
                .labelsHidden()
                .disabled(allowsAutomatic && setting.isAutomatic)
                if allowsAutomatic {
                    Toggle("Automatic", isOn: Binding(
                        get: { setting.isAutomatic },
                        set: { automatic in
                            if automatic {
                                lastCustom = setting.customColor
                                setting = .automatic
                            } else {
                                setting = .custom(lastCustom ?? fallback)
                            }
                        }
                    ))
                }
            }
        }
    }
}

struct PercentStepper: View {
    @Binding var value: Int

    var body: some View {
        Stepper("\(value)%", value: $value, in: 1...99)
            .monospacedDigit()
            .fixedSize()
    }
}

// MARK: - General

struct GeneralTab: View {
    @ObservedObject var prefs: Preferences
    @ObservedObject var loginItem: LoginItem
    @Environment(\.appearsActive) private var appearsActive

    private var version: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        return "\(short) (\(build))"
    }

    var body: some View {
        Form {
            Section("Startup") {
                Toggle("Launch Lithe at login", isOn: Binding(
                    get: { loginItem.isEnabled },
                    set: { loginItem.setEnabled($0) }
                ))
                .disabled(loginItem.isTranslocated)
                if loginItem.isTranslocated {
                    Text("Move Lithe to your Applications folder and open it again to enable this.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                if loginItem.requiresApproval {
                    HStack {
                        Text("Lithe needs approval in System Settings before it can launch at login.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Open Login Items…") { loginItem.openSystemSettings() }
                    }
                }
                if let error = loginItem.lastError {
                    Text(error)
                        .font(.callout)
                        .foregroundStyle(.red)
                }
            }
            Section("About") {
                LabeledContent("Version", value: version)
                LabeledContent("License", value: "MIT")
                Link("Lithe on GitHub", destination: AppInfo.repositoryURL)
                Text("Lithe is a small replacement for the menu bar battery meter, in the spirit of SlimBatteryMonitor.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Section {
                Button("Reset All Settings to Defaults") { prefs.resetToDefaults() }
            }
        }
        .formStyle(.grouped)
        .onAppear { loginItem.refresh() }
        .onChange(of: appearsActive) { _, active in
            if active { loginItem.refresh() }
        }
    }
}

enum AppInfo {
    static let repositoryURL = URL(string: "https://github.com/asmeurer/Lithe")!
}

// MARK: - Color conversions

extension Color {
    init(rgba: RGBA) {
        self.init(.sRGB, red: rgba.red, green: rgba.green, blue: rgba.blue, opacity: rgba.alpha)
    }
}

extension RGBA {
    init(color: Color) {
        self.init(nsColor: NSColor(color))
    }

    init(nsColor: NSColor) {
        let ns = nsColor.usingColorSpace(.sRGB) ?? .black
        self.init(red: Double(ns.redComponent), green: Double(ns.greenComponent), blue: Double(ns.blueComponent), alpha: Double(ns.alphaComponent))
    }

    /// The label color as currently resolved for the app's appearance, so a
    /// color that starts out as "custom" is at least visible. The label color
    /// is slightly translucent; the result is made opaque because the color
    /// picker does not offer opacity.
    @MainActor
    static var currentLabel: RGBA {
        var resolved = NSColor.labelColor
        NSApp.effectiveAppearance.performAsCurrentDrawingAppearance {
            resolved = NSColor.labelColor.usingColorSpace(.sRGB) ?? .black
        }
        var rgba = RGBA(nsColor: resolved)
        rgba.alpha = 1
        return rgba
    }
}
