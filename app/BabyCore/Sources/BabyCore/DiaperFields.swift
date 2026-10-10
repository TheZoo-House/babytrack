import Foundation

public enum DiaperFields {
    public static func selected(_ option: String, in fields: [String: String]) -> Bool {
        let contents = fields["contents"] ?? ""
        return contents == option || (contents == "Both" && ["Wet", "Dirty"].contains(option))
    }

    public static func toggleContents(_ option: String, in fields: inout [String: String]) {
        guard ["Wet", "Dirty", "Dry"].contains(option) else { return }
        if option == "Dry" {
            fields["contents"] = selected("Dry", in: fields) ? "" : "Dry"
            return
        }
        var wet = selected("Wet", in: fields), dirty = selected("Dirty", in: fields)
        if option == "Wet" {
            wet.toggle()
        }
        if option == "Dirty" {
            dirty.toggle()
        }
        fields["contents"] = wet && dirty ? "Both" : wet ? "Wet" : dirty ? "Dirty" : ""
    }

    public static func tokens(_ key: String, in fields: [String: String]) -> [String] {
        (fields[key] ?? "").split(separator: " ").map(String.init)
    }

    public static func toggle(_ value: String, key: String, in fields: inout [String: String]) {
        var values = tokens(key, in: fields)
        if values.contains(value) {
            values.removeAll { $0 == value }
        } else {
            values.append(value)
        }
        fields[key] = values.joined(separator: " ")
    }

    public static func setBlowout(_ value: Bool, in fields: inout [String: String]) {
        fields["blowout"] = String(value)
        // Explicit edits replace the legacy flag; original export columns remain in ImportSource.
        if fields["detail"]?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "blowout" {
            fields.removeValue(forKey: "detail")
        }
    }

    public static func hasBlowout(_ fields: [String: String]) -> Bool {
        if let value = fields["blowout"] {
            return value == "true"
        }
        return fields["detail"]?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "blowout"
    }
}
