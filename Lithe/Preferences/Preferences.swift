import Combine
import Foundation

/// The persisted user preferences. There is one instance per app; SwiftUI
/// views bind to `settings` and the status item controller subscribes to
/// `$settings`.
@MainActor
final class Preferences: ObservableObject {
    static let settingsKey = "DisplaySettings"
    static let legacyImportedKey = "ImportedSlimBatteryMonitorSettings"
    static let hiddenForSessionKey = "HiddenForSession"

    @Published var settings: DisplaySettings {
        didSet { if settings != oldValue { save() } }
    }

    let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        settings = Self.load(from: defaults) ?? DisplaySettings()
    }

    /// Restores the built-in defaults, discarding whatever is saved (even a
    /// blob that could not be read).
    func resetToDefaults() {
        defaults.removeObject(forKey: Self.settingsKey)
        settings = DisplaySettings()
    }

    private func save() {
        do {
            let data = try JSONEncoder().encode(settings)
            defaults.set(data, forKey: Self.settingsKey)
        } catch {
            // Encoding a plain Codable struct cannot realistically fail; log
            // loudly rather than silently ignoring if it ever does.
            NSLog("Lithe: failed to encode settings: \(error)")
        }
    }

    private static func load(from defaults: UserDefaults) -> DisplaySettings? {
        guard let data = defaults.data(forKey: settingsKey) else { return nil }
        do {
            return try JSONDecoder().decode(DisplaySettings.self, from: data)
        } catch {
            NSLog("Lithe: ignoring unreadable saved settings: \(error)")
            return nil
        }
    }

    /// Imports SlimBatteryMonitor's preferences the first time Lithe runs, if
    /// they exist and Lithe has no saved settings of its own yet.
    ///
    /// - Parameter legacy: The old app's defaults; read from its domain when
    ///   not supplied (tests pass a dictionary).
    /// - Returns: Whether anything was imported.
    @discardableResult
    func importLegacySettingsIfNeeded(legacy: [String: Any]? = nil) -> Bool {
        guard !defaults.bool(forKey: Self.legacyImportedKey) else { return false }
        defaults.set(true, forKey: Self.legacyImportedKey)
        guard defaults.data(forKey: Self.settingsKey) == nil else { return false }
        let old = legacy ?? UserDefaults(suiteName: LegacyImport.domain)?.dictionaryRepresentation() ?? [:]
        guard LegacyImport.looksLikeSlimBatteryMonitor(old) else { return false }
        settings = LegacyImport.settings(from: old, base: settings)
        NSLog("Lithe: imported SlimBatteryMonitor preferences")
        return true
    }
}
