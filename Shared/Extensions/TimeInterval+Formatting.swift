import Foundation

public extension TimeInterval {
    /// "1:23:45" or "23:45"
    var formattedDuration: String {
        let h = Int(self) / 3600
        let m = (Int(self) % 3600) / 60
        let s = Int(self) % 60
        return h > 0
            ? String(format: "%d:%02d:%02d", h, m, s)
            : String(format: "%02d:%02d", m, s)
    }

    /// "1:23" (hours) or "23" (minutes) — for compact metric tiles
    var hhmm: String {
        let h = Int(self) / 3600
        let m = (Int(self) % 3600) / 60
        return h > 0 ? String(format: "%d:%02d", h, m) : String(format: "%02d", m)
    }

    /// "hr" or "min" — unit label companion to hhmm
    var unit: String { Int(self) >= 3600 ? "hr" : "min" }
}
