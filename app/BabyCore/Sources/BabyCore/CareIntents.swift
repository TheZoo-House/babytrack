#if os(iOS)
    import AppIntents
    import WidgetKit

    public struct CareChild: AppEntity {
        public static let typeDisplayRepresentation: TypeDisplayRepresentation = "Child"
        public static let defaultQuery = CareChildQuery()
        public var id: String
        public var name: String
        public var displayRepresentation: DisplayRepresentation {
            DisplayRepresentation(title: "\(name)")
        }

        public init(id: String, name: String) {
            self.id = id; self.name = name
        }
    }

    public struct CareChildQuery: EntityStringQuery {
        public init() {}
        public func entities(for identifiers: [String]) async throws -> [CareChild] {
            try children().filter { identifiers.contains($0.id) }
        }

        public func entities(matching string: String) async throws -> [CareChild] {
            try children().filter { $0.name.localizedCaseInsensitiveContains(string) }
        }

        public func suggestedEntities() async throws -> [CareChild] {
            try children()
        }

        public func defaultResult() async -> CareChild? {
            guard let state = try? SharedStorage.application.read() else { return nil }
            let children = state.visibleEntities.filter { $0.type == "child" }
            guard let child = children.first(where: { $0.id == state.selectedChildID }) ?? (children.count == 1 ? children.first : nil) else { return nil }
            return CareChild(id: child.id, name: child.title)
        }

        private func children() throws -> [CareChild] {
            try SharedStorage.application.read().visibleEntities.filter { $0.type == "child" }.map { CareChild(id: $0.id, name: $0.title) }
        }
    }

    public enum BottleUnit: String, AppEnum {
        case ounces, milliliters
        public static let typeDisplayRepresentation: TypeDisplayRepresentation = "Bottle unit"
        public static let caseDisplayRepresentations: [BottleUnit: DisplayRepresentation] = [.ounces: "Ounces", .milliliters: "Milliliters"]
        public var recordValue: String {
            self == .ounces ? "oz" : "mL"
        }
    }

    public enum DiaperContents: String, AppEnum {
        case wet, dirty, both, dry
        public static let typeDisplayRepresentation: TypeDisplayRepresentation = "Diaper contents"
        public static let caseDisplayRepresentations: [DiaperContents: DisplayRepresentation] = [.wet: "Wet", .dirty: "Dirty", .both: "Wet and dirty", .dry: "Dry"]
        public var recordValue: String {
            switch self { case .wet: "Wet"; case .dirty: "Dirty"; case .both: "Both"; case .dry: "Dry" }
        }
    }

    public struct LogBottleIntent: AppIntent {
        public static let title: LocalizedStringResource = "Log bottle"
        public static let openAppWhenRun = true
        @Parameter(title: "Child") public var child: CareChild
        @Parameter(title: "Amount", requestValueDialog: "How much did they drink?") public var amount: Double
        @Parameter(title: "Unit", requestValueDialog: "Ounces or milliliters?") public var unit: BottleUnit
        public static var parameterSummary: some ParameterSummary {
            Summary("Log \(\.$amount) \(\.$unit) for \(\.$child)")
        }

        public init() {}
        public func perform() async throws -> some IntentResult & ProvidesDialog {
            try SharedStorage.application.record(.bottle(amount, unit.recordValue), childID: child.id)
            WidgetCenter.shared.reloadAllTimelines()
            return .result(dialog: "Saved a \(amount) \(unit.recordValue) bottle for \(child.name).")
        }
    }

    public struct LogDiaperIntent: AppIntent {
        public static let title: LocalizedStringResource = "Log diaper"
        public static let openAppWhenRun = true
        @Parameter(title: "Child") public var child: CareChild
        @Parameter(title: "Contents", default: .wet) public var contents: DiaperContents
        public static var parameterSummary: some ParameterSummary {
            Summary("Log a \(\.$contents) diaper for \(\.$child)")
        }

        public init() {}
        public init(contents: DiaperContents) {
            self.contents = contents
        }

        public func perform() async throws -> some IntentResult & ProvidesDialog {
            try SharedStorage.application.record(.diaper(contents.recordValue), childID: child.id)
            WidgetCenter.shared.reloadAllTimelines()
            return .result(dialog: "Saved a \(contents.recordValue.lowercased()) diaper for \(child.name).")
        }
    }

    public struct StartSleepIntent: AppIntent {
        public static let title: LocalizedStringResource = "Start sleep"
        public static let openAppWhenRun = true
        @Parameter(title: "Child") public var child: CareChild
        public static var parameterSummary: some ParameterSummary {
            Summary("Start sleep for \(\.$child)")
        }

        public init() {}
        public func perform() async throws -> some IntentResult & ProvidesDialog {
            try SharedStorage.application.record(.startSleep, childID: child.id)
            WidgetCenter.shared.reloadAllTimelines()
            return .result(dialog: "Sleep timer is running for \(child.name).")
        }
    }

    public struct EndSleepIntent: AppIntent {
        public static let title: LocalizedStringResource = "End sleep"
        public static let openAppWhenRun = true
        @Parameter(title: "Child") public var child: CareChild
        public static var parameterSummary: some ParameterSummary {
            Summary("End sleep for \(\.$child)")
        }

        public init() {}
        public func perform() async throws -> some IntentResult & ProvidesDialog {
            try SharedStorage.application.record(.endSleep, childID: child.id)
            WidgetCenter.shared.reloadAllTimelines()
            return .result(dialog: "Ended sleep for \(child.name).")
        }
    }

    public struct WetDiaperIntent: AppIntent {
        public static let title: LocalizedStringResource = "Log wet diaper"
        public init() {}
        public func perform() async throws -> some IntentResult {
            try SharedStorage.application.record(.diaper("Wet"))
            WidgetCenter.shared.reloadAllTimelines()
            return .result()
        }
    }

    public enum GrowthMeasure: String, AppEnum {
        case weight, height, head
        public static let typeDisplayRepresentation: TypeDisplayRepresentation = "Measurement"
        public static let caseDisplayRepresentations: [GrowthMeasure: DisplayRepresentation] = [.weight: "Weight", .height: "Height", .head: "Head circumference"]
        public var recordValue: String {
            switch self { case .weight: "Weight"; case .height: "Height"; case .head: "Head circumference" }
        }
    }

    public enum MeasurementUnit: String, AppEnum {
        case pounds, ounces, kilograms, inches, centimeters
        public static let typeDisplayRepresentation: TypeDisplayRepresentation = "Measurement unit"
        public static let caseDisplayRepresentations: [MeasurementUnit: DisplayRepresentation] = [.pounds: "Pounds", .ounces: "Ounces", .kilograms: "Kilograms", .inches: "Inches", .centimeters: "Centimeters"]
        public var recordValue: String {
            switch self { case .pounds: "lb"; case .ounces: "oz"; case .kilograms: "kg"; case .inches: "in"; case .centimeters: "cm" }
        }
    }

    public enum TemperatureUnit: String, AppEnum {
        case fahrenheit, celsius
        public static let typeDisplayRepresentation: TypeDisplayRepresentation = "Temperature unit"
        public static let caseDisplayRepresentations: [TemperatureUnit: DisplayRepresentation] = [.fahrenheit: "Fahrenheit", .celsius: "Celsius"]
        public var recordValue: String {
            self == .fahrenheit ? "°F" : "°C"
        }
    }

    public struct LogMeasurementIntent: AppIntent {
        public static let title: LocalizedStringResource = "Log measurement"
        public static let openAppWhenRun = true
        @Parameter(title: "Child") public var child: CareChild
        @Parameter(title: "Measurement", default: .weight) public var measure: GrowthMeasure
        @Parameter(title: "Value") public var value: Double
        @Parameter(title: "Unit") public var unit: MeasurementUnit
        public init() {}
        public func perform() async throws -> some IntentResult & ProvidesDialog {
            try SharedStorage.application.record(.measurement(value, measure.recordValue, unit.recordValue), childID: child.id)
            WidgetCenter.shared.reloadAllTimelines()
            return .result(dialog: "Saved \(child.name)'s \(measure.recordValue.lowercased()).")
        }
    }

    public struct LogTemperatureIntent: AppIntent {
        public static let title: LocalizedStringResource = "Log temperature"
        public static let openAppWhenRun = true
        @Parameter(title: "Child") public var child: CareChild
        @Parameter(title: "Temperature") public var value: Double
        @Parameter(title: "Unit", requestValueDialog: "Fahrenheit or Celsius?") public var unit: TemperatureUnit
        public init() {}
        public func perform() async throws -> some IntentResult & ProvidesDialog {
            try SharedStorage.application.record(.temperature(value, unit.recordValue), childID: child.id)
            WidgetCenter.shared.reloadAllTimelines()
            return .result(dialog: "Saved \(child.name)'s temperature.")
        }
    }

    public struct LogMedicationIntent: AppIntent {
        public static let title: LocalizedStringResource = "Log medication"
        public static let openAppWhenRun = true
        @Parameter(title: "Child") public var child: CareChild
        @Parameter(title: "Medication") public var name: String
        @Parameter(title: "Dose") public var dose: Double
        @Parameter(title: "Dose unit", requestValueDialog: "What is the dose unit, such as milliliters?") public var unit: String
        public init() {}
        public func perform() async throws -> some IntentResult & ProvidesDialog {
            try SharedStorage.application.record(.medication(name, dose, unit), childID: child.id)
            WidgetCenter.shared.reloadAllTimelines()
            return .result(dialog: "Saved \(name) for \(child.name).")
        }
    }
#endif
