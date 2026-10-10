import AppIntents
import BabyCore

struct BabytrackShortcuts: AppShortcutsProvider {
    static var shortcutTileColor: ShortcutTileColor {
        .teal
    }

    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: LogBottleIntent(), phrases: ["Log a bottle in \(.applicationName)", "Add a bottle in \(.applicationName)", "Log a bottle for \(\.$child) in \(.applicationName)"], shortTitle: "Log bottle", systemImageName: "waterbottle.fill")
        AppShortcut(intent: LogDiaperIntent(), phrases: ["Log a diaper in \(.applicationName)", "Log a diaper for \(\.$child) in \(.applicationName)"], shortTitle: "Log diaper", systemImageName: "drop.fill")
        AppShortcut(intent: LogDiaperIntent(contents: .wet), phrases: ["Log a wet diaper in \(.applicationName)"], shortTitle: "Wet diaper", systemImageName: "drop.fill")
        AppShortcut(intent: LogDiaperIntent(contents: .dirty), phrases: ["Log a dirty diaper in \(.applicationName)"], shortTitle: "Dirty diaper", systemImageName: "drop.fill")
        AppShortcut(intent: StartSleepIntent(), phrases: ["Start sleep in \(.applicationName)", "Start sleep for \(\.$child) in \(.applicationName)"], shortTitle: "Start sleep", systemImageName: "moon.zzz.fill")
        AppShortcut(intent: EndSleepIntent(), phrases: ["End sleep in \(.applicationName)", "Wake up in \(.applicationName)", "End sleep for \(\.$child) in \(.applicationName)"], shortTitle: "End sleep", systemImageName: "sun.max.fill")
        AppShortcut(intent: LogMeasurementIntent(), phrases: ["Log a measurement in \(.applicationName)"], shortTitle: "Log measurement", systemImageName: "ruler.fill")
        AppShortcut(intent: LogTemperatureIntent(), phrases: ["Log a temperature in \(.applicationName)"], shortTitle: "Log temperature", systemImageName: "thermometer.medium")
        AppShortcut(intent: LogMedicationIntent(), phrases: ["Log medication in \(.applicationName)"], shortTitle: "Log medication", systemImageName: "pills.fill")
        AppShortcut(intent: OpenCareEntryIntent(), phrases: ["Add a record in \(.applicationName)", "Add \(\.$kind) in \(.applicationName)"], shortTitle: "Add record", systemImageName: "plus")
    }
}

enum CareEntryKind: String, AppEnum {
    case feeding, diaper, sleep, reading, growth, medication, temperature, vaccine, milestone, note
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Record"
    static let caseDisplayRepresentations: [CareEntryKind: DisplayRepresentation] = [.feeding: "Bottle", .diaper: "Diaper", .sleep: "Past sleep", .reading: "Reading", .growth: "Measurement", .medication: "Medication", .temperature: "Temperature", .vaccine: "Vaccine", .milestone: "Milestone", .note: "Note"]
}

struct OpenCareEntryIntent: AppIntent {
    static let title: LocalizedStringResource = "Add record"
    static let openAppWhenRun = true
    @Parameter(title: "Record", default: .feeding) var kind: CareEntryKind
    func perform() async throws -> some IntentResult & OpensIntent {
        .result(opensIntent: OpenURLIntent(DeepLink.log(kind.rawValue).url))
    }
}
