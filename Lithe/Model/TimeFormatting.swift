import Foundation

/// Formats minutes and percentages the way the menu bar shows them.
enum TimeFormatting {
    /// Formats a duration in minutes as `h:mm`, e.g. 150 -> "2:30", 5 -> "0:05".
    static func clock(minutes: Int) -> String {
        let m = max(0, minutes)
        return String(format: "%d:%02d", m / 60, m % 60)
    }

    /// Formats an optional minutes value for the menu bar. Unknown values show
    /// as an en-dash clock so the item keeps a stable width while macOS is
    /// still calculating an estimate.
    static func clock(minutes: Int?) -> String {
        guard let minutes else { return "–:––" }
        return clock(minutes: minutes)
    }

    /// Formats a duration in minutes as words, e.g. "2 hours 30 minutes".
    static func spoken(minutes: Int) -> String {
        let m = max(0, minutes)
        let hours = m / 60
        let mins = m % 60
        var parts: [String] = []
        if hours > 0 { parts.append(hours == 1 ? "1 hour" : "\(hours) hours") }
        if mins > 0 || hours == 0 { parts.append(mins == 1 ? "1 minute" : "\(mins) minutes") }
        return parts.joined(separator: " ")
    }

    static func percent(_ percent: Int?) -> String {
        guard let percent else { return "–%" }
        return "\(percent)%"
    }
}
