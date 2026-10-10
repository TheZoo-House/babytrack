import Foundation

public enum ReminderTiming {
    public static func due(_ entity: Entity, records: [Entity], now: Date = .now) -> Double? {
        guard !entity.deleted, entity.fields["done"] != "true" else { return nil }
        var due = entity.at
        if entity.fields["trigger"] == "After last log", let hours = Double(entity.fields["afterHours"] ?? ""), hours.isFinite, hours > 0 {
            let name = entity.fields["anchorTitle"]?.trimmingCharacters(in: .whitespacesAndNewlines)
            let latest = records.filter { !$0.deleted && $0.childID == entity.childID && $0.type == entity.fields["kind"] && $0.at <= now.timeIntervalSince1970 && (name?.isEmpty != false || $0.title.caseInsensitiveCompare(name!) == .orderedSame) }.max { $0.at < $1.at }
            due = (latest?.at ?? entity.createdAt ?? now.timeIntervalSince1970) + hours * 3600
        }
        return max(due, entity.snoozedUntil ?? 0)
    }
}
