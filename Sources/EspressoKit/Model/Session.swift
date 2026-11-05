import Foundation

enum SessionLength: Equatable {
    case indefinitely
    case timed(seconds: Int)
    case untilAppQuits(pid: pid_t, name: String)
    case untilDownloadsFinish
}

struct Session: Equatable {
    let length: SessionLength
    let startedAt: Date

    var endsAt: Date? {
        guard case .timed(let seconds) = length else { return nil }
        return startedAt.addingTimeInterval(TimeInterval(seconds))
    }
}

enum Countdown {
    /// "45s", "25m", "1h", "1h 43m". Minutes round up, so "1m" means up to a minute left.
    static func short(_ seconds: Int) -> String {
        guard seconds >= 60 else { return "\(max(seconds, 0))s" }
        let minutes = (seconds + 59) / 60
        guard minutes >= 60 else { return "\(minutes)m" }
        let rest = minutes % 60
        return rest == 0 ? "\(minutes / 60)h" : "\(minutes / 60)h \(rest)m"
    }

    /// Hours and minutes for the menu bar, "1:43" or "0:25", with minutes rounded up.
    static func menuBar(_ seconds: Int) -> String {
        let minutes = (max(seconds, 0) + 59) / 60
        return String(format: "%d:%02d", minutes / 60, minutes % 60)
    }
}
