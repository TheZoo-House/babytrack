import Foundation

public enum CareActionError: Error, LocalizedError {
    case noChild, invalidAmount, invalidMeasurement, noSleep
    public var errorDescription: String? {
        switch self {
        case .noChild: "Open the app and choose a child first."
        case .invalidAmount: "Enter a bottle amount greater than zero."
        case .invalidMeasurement: "Check the value and unit for this record."
        case .noSleep: "This child has no running sleep timer."
        }
    }
}

public enum CareAction: Sendable {
    case diaper(String)
    case bottle(Double, String)
    case measurement(Double, String, String)
    case temperature(Double, String)
    case medication(String, Double, String)
    case startSleep
    case endSleep
}

public extension SharedStorage {
    /// App, widgets and Siri resolve the child and enqueue under one lock.
    @discardableResult func record(_ action: CareAction, childID: String? = nil, now: Date = .now) throws -> Entity {
        try update { state in
            let children = state.visibleEntities.filter { $0.type == "child" }
            let id = childID ?? state.selectedChildID
            guard let child = children.first(where: { $0.id == id }) ?? (childID == nil && children.count == 1 ? children.first : nil)
            else { throw CareActionError.noChild }
            let active = state.visibleEntities.first { $0.type == "sleep" && $0.childID == child.id && $0.end == nil }
            var entity: Entity
            var operation = "upsert"
            switch action {
            case let .diaper(contents):
                guard ["Wet", "Dirty", "Both", "Dry"].contains(contents) else { throw CareActionError.invalidAmount }
                entity = Entity(type: "diaper", childID: child.id, title: "Diaper", date: now, fields: ["contents": contents])
            case let .bottle(amount, unit):
                guard amount.isFinite, amount > 0, amount <= 100_000, ["oz", "mL"].contains(unit) else { throw CareActionError.invalidAmount }
                entity = Entity(type: "feeding", childID: child.id, title: "Bottle", date: now, fields: ["amount": String(amount), "unit": unit])
            case let .measurement(value, measure, unit):
                let units = measure == "Weight" ? ["lb", "oz", "kg"] : ["in", "cm"]
                guard value.isFinite, value > 0, value <= 100_000, ["Weight", "Height", "Head circumference"].contains(measure), units.contains(unit) else { throw CareActionError.invalidMeasurement }
                entity = Entity(type: "growth", childID: child.id, title: "Measurement", date: now, fields: ["value": String(value), "measure": measure, "unit": unit])
            case let .temperature(value, unit):
                guard value.isFinite, value >= 0, value <= 100_000, ["°F", "°C"].contains(unit) else { throw CareActionError.invalidMeasurement }
                entity = Entity(type: "temperature", childID: child.id, title: "Temperature", date: now, fields: ["value": String(value), "unit": unit])
            case let .medication(name, dose, unit):
                let title = name.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !title.isEmpty, title.count <= 240, dose.isFinite, dose > 0, dose <= 100_000, !unit.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, unit.count <= 80 else { throw CareActionError.invalidMeasurement }
                entity = Entity(type: "medication", childID: child.id, title: title, date: now, fields: ["dose": String(dose), "unit": unit])
            case .startSleep:
                if let active {
                    return active
                }
                operation = "sleepStart"
                entity = Entity(type: "sleep", childID: child.id, title: "Sleep", date: now, fields: ["category": "Nap"])
            case .endSleep:
                guard var sleep = active else { throw CareActionError.noSleep }
                sleep.end = max(sleep.at, now.timeIntervalSince1970); entity = sleep; operation = "sleepStop"
            }
            state.enqueue(Command(action: operation, entity: entity))
            return entity
        }
    }
}
