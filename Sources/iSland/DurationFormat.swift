import Foundation

enum DurationFormat {
    /// 45 -> "45s", 125 -> "2m 05s", 3720 -> "1h 02m"
    static func short(_ seconds: Int) -> String {
        let total = max(0, seconds)
        if total < 60 { return "\(total)s" }
        if total < 3600 { return String(format: "%dm %02ds", total / 60, total % 60) }
        return String(format: "%dh %02dm", total / 3600, (total % 3600) / 60)
    }

    /// "24:59" or "1:05:00": a countdown.
    static func clock(_ seconds: Int) -> String {
        let s = max(0, seconds)
        return s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, s % 3600 / 60, s % 60) : String(format: "%d:%02d", s / 60, s % 60)
    }
}
