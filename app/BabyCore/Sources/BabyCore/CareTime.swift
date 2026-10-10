import Foundation

public enum CareTime {
    public static func relative(_ date: Date, now: Date = .now) -> String {
        let elapsed = now.timeIntervalSince(date)
        if elapsed < 0 { return date.formatted(date: .abbreviated, time: .shortened) }
        let minutes = Int(elapsed / 60)
        if minutes == 0 { return "Just now" }
        if minutes < 60 { return "\(minutes)m ago" }
        if minutes < 1440 { let remainder = minutes % 60; return "\(minutes / 60)h" + (remainder == 0 ? "" : " \(remainder)m") + " ago" }
        return date.formatted(date: .abbreviated, time: .shortened)
    }
    public static func volume(_ ml: Int, imperial: Bool) -> String { imperial ? (Double(ml) / 29.5735295625).formatted(.number.precision(.fractionLength(0 ... 1))) + " oz" : "\(ml) mL" }
    public static func sleep(_ minutes: Int) -> String { minutes < 60 ? "\(minutes)m" : "\(minutes / 60)h" + (minutes % 60 == 0 ? "" : " \(minutes % 60)m") }
    public static func totals(_ summary: DaySummary, imperial: Bool) -> String { "\(volume(summary.feedingML, imperial: imperial)) · \(summary.diaperCount) diaper\(summary.diaperCount == 1 ? "" : "s") · \(sleep(summary.sleepMinutes)) sleep" }
}

public enum CareNotification: Equatable, Sendable {
    case open(String), done(String), snooze(String)
    public init?(recordID: String?, action: String) {
        guard let recordID, !recordID.isEmpty, recordID.count <= 80 else { return nil }
        switch action { case "reminder-done": self = .done(recordID); case "reminder-snooze": self = .snooze(recordID); case "default": self = .open(recordID); default: return nil }
    }
}
