import Foundation

public extension DiskState {
    /// Server summaries remain authoritative; project local/offline changes and time-dependent totals.
    func careSummary(for childID: String, now: Date = .now, timeZone: TimeZone = .current) -> DaySummary? {
        guard !childID.isEmpty else { return nil }
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = timeZone
        let components = calendar.dateComponents([.year, .month, .day], from: now)
        let day = String(format: "%04d-%02d-%02d", components.year!, components.month!, components.day!)
        let cached = snapshot.summaries.first { $0.childID == childID }
        let pending = outbox.contains { $0.entity.childID == childID && $0.error == nil }
        let records = visibleEntities
        let active = records.contains { $0.type == "sleep" && $0.childID == childID && $0.end == nil }
        if !localPreview, !pending, !active, cached?.day == day {
            return cached
        }
        let start = calendar.startOfDay(for: now).timeIntervalSince1970
        let end = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))!.timeIntervalSince1970
        var feeds = 0, diapers = 0, reading = 0
        var ml = 0.0, sleep = 0.0
        var latest: [String: Entity] = [:]
        for record in records where record.childID == childID && !record.deleted {
            if ["feeding", "diaper", "sleep"].contains(record.type), latest[record.type] == nil || record.at > latest[record.type]!.at || (record.at == latest[record.type]!.at && record.id < latest[record.type]!.id) {
                latest[record.type] = record
            }
            if record.type == "sleep" {
                sleep += max(0, min(record.end ?? now.timeIntervalSince1970, now.timeIntervalSince1970) - max(record.at, start)) / 60
            }
            guard record.at >= start, record.at < end else { continue }
            switch record.type {
            case "feeding":
                feeds += 1
                if let amount = Double(record.fields["amount"] ?? ""), amount.isFinite {
                    if record.fields["unit"] == "oz" {
                        ml += amount * 29.5735295625
                    }
                    if record.fields["unit"] == "mL" {
                        ml += amount
                    }
                }
            case "diaper": diapers += 1
            case "reading": reading += 1
            default: break
            }
        }
        return DaySummary(childID: childID, feedingCount: feeds, feedingML: Int(ml.rounded()), diaperCount: diapers,
                          sleepMinutes: Int(sleep.rounded()), readingCount: reading, day: day,
                          lastFeedingID: latest["feeding"]?.id, lastDiaperID: latest["diaper"]?.id, lastSleepID: latest["sleep"]?.id)
    }
}
