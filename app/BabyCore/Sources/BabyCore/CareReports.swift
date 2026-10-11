import Foundation

public struct CareReportRow: Sendable {
    public var entity: Entity
    public var detail: String
    public init(entity: Entity, detail: String) { self.entity = entity; self.detail = detail }
}

public enum CareReports {
    public static func records(_ entities: [Entity], childID: String, from: Date, through: Date) -> [CareReportRow] {
        let index = Dictionary(entities.map { ($0.id, $0) }, uniquingKeysWith: { _, latest in latest })
        return entities.filter { !$0.deleted && $0.childID == childID && Catalog.shared.spec($0.type).scope == "care" && $0.at >= from.timeIntervalSince1970 && $0.at <= through.timeIntervalSince1970 }
            .sorted { $0.at == $1.at ? $0.id < $1.id : $0.at < $1.at }
            .map { CareReportRow(entity: $0, detail: RecordDetails.text(for: $0, records: index)) }
    }

    public static func csv(child: String, rows: [CareReportRow]) -> String {
        func cell(_ raw: String) -> String {
            let text = raw.first.map { "=+-@".contains($0) } == true ? "'" + raw : raw
            return "\"" + text.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        let format = ISO8601DateFormatter(); format.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let values = rows.map { row in [child, Catalog.shared.spec(row.entity.type).title, format.string(from: row.entity.date), row.detail, row.entity.fields["notes"] ?? "", row.entity.actor, row.entity.updatedBy ?? row.entity.actor] }
        return ([ ["Child", "Type", "Time", "Details", "Notes", "Recorded by", "Last updated by"] ] + values).map { $0.map(cell).joined(separator: ",") }.joined(separator: "\r\n") + "\r\n"
    }

    public static func text(child: String, rows: [CareReportRow]) -> String {
        ([child] + rows.map { row in "\(row.entity.date.formatted(date: .abbreviated, time: .shortened)) · \(row.entity.title) · \(row.detail) · \(row.entity.updatedBy ?? row.entity.actor)" }).joined(separator: "\n")
    }
}

public extension DiskState {
    func summary(forDay date: Date, childID: String, now: Date = .now) -> DaySummary? {
        let calendar = Calendar.current
        let end = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: date))!.addingTimeInterval(-0.001)
        return careSummary(for: childID, now: min(end, now))
    }
    func lastMedication(named name: String, childID: String) -> Entity? {
        currentEntities.filter { $0.type == "medication" && $0.childID == childID && $0.title.caseInsensitiveCompare(name.trimmingCharacters(in: .whitespacesAndNewlines)) == .orderedSame }.max { $0.at < $1.at }
    }
    func caregiverChanges(childID: String, since: Double) -> [Entity] {
        visibleEntities.filter { entity in
            guard entity.childID == childID, Catalog.shared.spec(entity.type).scope == "care", entity.updatedAt > since else { return false }
            if entity.imported != nil && entity.updatedByID == nil { return false }
            return entity.updatedByID.map { $0 != snapshot.user.id } ?? (!entity.actor.isEmpty && entity.actor != snapshot.user.name)
        }.sorted { $0.updatedAt > $1.updatedAt }
    }
    mutating func markHandoffSeen(childID: String, through: Double) {
        if handoffSeenAt == nil { handoffSeenAt = [:] }
        let previous = handoffSeenAt?[childID] ?? 0
        handoffSeenAt?[childID] = max(previous, through)
    }
}
