import Foundation

public enum RecordDetails {
    public static func text(for entity: Entity, records: [String: Entity] = [:], now: Date = .now) -> String {
        let fields = entity.fields, spec = Catalog.shared.spec(entity.type)
        func join(_ values: [String?]) -> String { values.compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ") }
        func value(_ key: String) -> String? { fields[key].map { spec.displayValue(key, $0) } }
        func reference(_ key: String) -> String? { fields[key].flatMap { records[$0]?.title } }
        func location(_ id: String?) -> String {
            var id = id, names: [String] = [], seen: Set<String> = []
            while let current = id, seen.insert(current).inserted, let record = records[current], record.type == "location", !record.deleted {
                names.insert(record.title, at: 0); id = record.fields["parentID"]
            }
            return names.joined(separator: " → ")
        }
        switch entity.type {
        case "feeding": return join([fields["amount"].flatMap { $0.isEmpty ? nil : $0 + " " + (fields["unit"] ?? "") } ?? "Amount not recorded", fields["milkType"], fields["milkType"] == "Breast milk" || fields["brand"] == fields["milkType"] ? nil : fields["brand"]])
        case "diaper":
            let dirty = DiaperFields.selected("Dirty", in: fields)
            let detail = fields["detail"]?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "blowout" ? nil : fields["detail"]
            return join([value("contents")] + (dirty ? [detail, value("color"), value("consistency")] : []) + [DiaperFields.hasBlowout(fields) ? "Blowout" : nil, fields["rash"] == "true" ? "Diaper rash" : nil])
        case "sleep": return entity.end.map { join(["\(Int((max(0, $0 - entity.at) / 60).rounded())) min", fields["category"]]) } ?? (fields["category"]?.isEmpty == false ? fields["category"]! : "Sleeping")
        case "reading": return join([reference("itemID"), fields["minutes"].flatMap { $0.isEmpty ? nil : $0 + " min" }])
        case "growth": return join([value("measure"), (fields["value"] ?? "") + " " + (fields["unit"]?.isEmpty == false ? fields["unit"]! : "· unit unknown")])
        case "temperature": return join([(fields["value"] ?? "") + " " + (fields["unit"]?.isEmpty == false ? fields["unit"]! : "· unit unknown"), fields["method"]])
        case "medication": return join([fields["dose"].flatMap { $0.isEmpty ? nil : $0 + " " + (fields["unit"]?.isEmpty == false ? fields["unit"]! : "· unit unknown") } ?? "Dose not recorded", fields["route"]])
        case "book": return join([fields["author"], location(fields["locationID"]), fields["status"]])
        case "toy":
            let ages = fields["minAge"].flatMap { $0.isEmpty ? nil : $0 + (fields["maxAge"]?.isEmpty == false ? "–" + fields["maxAge"]! : "+") + " months" }
            return join([fields["brand"], ages, location(fields["locationID"]), fields["status"]])
        case "clothing": return join([fields["size"], fields["brand"], location(fields["locationID"]), fields["status"]])
        case "location": return location(fields["parentID"])
        case "child":
            if entity.at == 0, entity.imported != nil { return "Birthday not recorded" }
            let months = max(0, Int(floor((now.timeIntervalSince1970 - entity.at) / (86400 * 30.4375))))
            return months > 0 ? "\(months) month\(months == 1 ? "" : "s") old" : "Newborn"
        default: return fields["provider"]?.isEmpty == false ? fields["provider"]! : fields["symptoms"]?.isEmpty == false ? fields["symptoms"]! : fields["notes"] ?? ""
        }
    }
}

public extension Entity {
    var displayDetail: String { detail.isEmpty ? RecordDetails.text(for: self) : detail }
}
