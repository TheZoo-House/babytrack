import Foundation

public struct BottleAmount: Equatable, Sendable {
    public var value: String
    public var unit: String
    public static func latest(in records: [Entity], childID: String, excluding id: String? = nil) -> BottleAmount? {
        guard let last = records.filter({ $0.type == "feeding" && $0.childID == childID && !$0.deleted && $0.id != id })
            .max(by: { $0.at < $1.at }),
            let raw = last.fields["amount"], let value = Double(raw), value.isFinite, value > 0,
            let unit = last.fields["unit"], ["oz", "mL"].contains(unit) else { return nil }
        return BottleAmount(value: raw, unit: unit)
    }
}
