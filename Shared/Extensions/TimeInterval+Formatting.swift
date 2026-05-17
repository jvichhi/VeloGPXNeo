import Foundation

public extension TimeInterval {
    /// "1:23" (hours) or "23" (minutes) — for compact metric tiles
    var hhmm: String {
        let h = Int(self) / 3600
        let m = (Int(self) % 3600) / 60
        return h > 0 ? String(format: "%d:%02d", h, m) : String(format: "%02d", m)
    }

    /// "hr" or "min" — unit label companion to hhmm
    var unit: String { Int(self) >= 3600 ? "hr" : "min" }
}
