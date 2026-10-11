#if DEBUG
import BabyCore
import Foundation

extension AppStore {
    static var testingRequested: Bool {
        let args = ProcessInfo.processInfo.arguments
        return ["--ui-testing", "--ui-http-test", "--owner-preview-testing"].contains(where: args.contains)
    }

    func installSyntheticTestingState() throws {
        let args = ProcessInfo.processInfo.arguments
        guard args.contains("--ui-testing") else { return }
        var fresh = DiskState(); fresh.snapshot = try Snapshot.sample()
        if args.contains("--history-stress-testing") {
            let templates = fresh.snapshot.entities.filter { ["feeding", "diaper", "sleep"].contains($0.type) }
            let count = args.contains("--small-history") ? 24 : 1700
            for index in 0 ..< count {
                var record = templates[index % templates.count]; record.id = "stress-\(index)"
                let offset = Double(index * 3600); record.at -= offset
                if let end = record.end { record.end = end - offset }
                fresh.snapshot.entities.append(record)
            }
        }
        fresh.localPreview = true; fresh.repairChildSelection()
        state = fresh; try storage.update { $0 = fresh }
    }

    func ownerTestingForm() -> FormRequest? {
        let args = ProcessInfo.processInfo.arguments
        guard args.contains("--owner-preview-testing"), let index = args.firstIndex(of: "--owner-form"),
              args.indices.contains(index + 1), Catalog.shared.types.contains(where: { $0.id == args[index + 1] }) else { return nil }
        let type = args[index + 1]
        let existing = args.contains("--owner-form-existing") ? entities.first { $0.type == type && (type != "diaper" || $0.fields["contents"] == "Both") } : nil
        return FormRequest(type: type, entity: existing)
    }
}
#endif
