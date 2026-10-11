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
    case endSleepSession(String)
    case reminderDone(String)
    case reminderSnooze(String, Double)
}

public extension SharedStorage {
    /// App, widgets and Siri resolve the child and enqueue under one lock.
    @discardableResult func record(_ action: CareAction, childID: String? = nil, now: Date = .now) throws -> Entity {
        try update { state in
            let records = state.currentEntities
            let children = records.filter { $0.type == "child" }
            let referenceID: String?
            switch action { case let .reminderDone(id), let .reminderSnooze(id, _), let .endSleepSession(id): referenceID = id; default: referenceID = nil }
            let referenced = referenceID.flatMap { id in records.first { $0.id == id } }
            let id = childID ?? referenced?.childID ?? state.resolvedChild?.id ?? ""
            guard let child = children.first(where: { $0.id == id })
            else { throw CareActionError.noChild }
            let active = state.activeSleep(for: child.id)
            var entity: Entity
            var operation = "upsert"
            switch action {
            case let .diaper(contents):
                guard Catalog.shared.spec("diaper").options("contents").contains(contents) else { throw CareActionError.invalidAmount }
                entity = Entity(type: "diaper", childID: child.id, title: "Diaper", date: now, fields: ["contents": contents])
            case let .bottle(amount, unit):
                guard amount.isFinite, amount > 0, amount <= 100_000, Catalog.shared.spec("feeding").options("unit").contains(unit) else { throw CareActionError.invalidAmount }
                entity = Entity(type: "feeding", childID: child.id, title: "Bottle", date: now, fields: ["amount": String(amount), "unit": unit])
            case let .measurement(value, measure, unit):
                let spec = Catalog.shared.spec("growth"), units = spec.options("unit", measure: measure)
                guard value.isFinite, value > 0, value <= 100_000, spec.options("measure").contains(measure), units.contains(unit) else { throw CareActionError.invalidMeasurement }
                entity = Entity(type: "growth", childID: child.id, title: "Measurement", date: now, fields: ["value": String(value), "measure": measure, "unit": unit])
            case let .temperature(value, unit):
                guard value.isFinite, value >= 0, value <= 100_000, Catalog.shared.spec("temperature").options("unit").contains(unit) else { throw CareActionError.invalidMeasurement }
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
            case .endSleep, .endSleepSession:
                guard var sleep = active else { throw CareActionError.noSleep }
                if case let .endSleepSession(id) = action, sleep.id != id { throw CareActionError.noSleep }
                sleep.end = max(sleep.at, now.timeIntervalSince1970); entity = sleep; operation = "sleepStop"
            case .reminderDone:
                guard var reminder = referenced, reminder.type == "reminder" else { throw CareActionError.invalidMeasurement }
                reminder.fields["done"] = "true"; entity = reminder; operation = "reminderDone"
            case let .reminderSnooze(_, minutes):
                guard var reminder = referenced, reminder.type == "reminder", minutes.isFinite, minutes > 0, minutes <= 10080 else { throw CareActionError.invalidMeasurement }
                reminder.at = now.addingTimeInterval(minutes * 60).timeIntervalSince1970; reminder.snoozedUntil = reminder.at; reminder.fields["done"] = "false"; entity = reminder; operation = "reminderSnooze"
            }
            state.enqueue(Command(action: operation, entity: entity))
            return entity
        }
    }
}
