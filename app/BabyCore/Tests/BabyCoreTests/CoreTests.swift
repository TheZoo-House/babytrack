@testable import BabyCore
import XCTest

final class CoreTests: XCTestCase {
    func testCatalogAndSnapshotContract() throws {
        XCTAssertEqual(Catalog.shared.types.count, 19)
        let snapshot = try Snapshot.sample()
        XCTAssertEqual(snapshot.version, 1)
        XCTAssertTrue(snapshot.entities.contains { $0.type == "book" && $0.fields["giftGiver"] != nil })
        XCTAssertTrue(snapshot.entities.contains { $0.type == "child" })
        XCTAssertFalse(snapshot.summaries.isEmpty)
    }

    func testQueueSurvivesRestartAndRetainsNewEditsDuringSync() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let storage = SharedStorage(directory: dir)
        let first = Command(entity: Entity(
            type: "feeding",
            childID: "synthetic-child",
            title: "Bottle",
            fields: ["amount": "4", "unit": "oz"]
        ))
        let second = Command(entity: Entity(
            type: "diaper",
            childID: "synthetic-child",
            title: "Diaper",
            fields: ["contents": "Wet"]
        ))
        try storage.enqueue(first); try storage.enqueue(second)
        XCTAssertEqual(try SharedStorage(directory: dir).read().outbox.count, 2)
        var snapshot = Snapshot.empty; snapshot.entities = [first.entity]
        let response = SyncResponse(
            results: [.init(id: first.id, status: "accepted", message: nil, entityID: first.entity.id)],
            snapshot: snapshot
        )
        _ = try storage.update { $0.merge(response) }
        let after = try storage.read()
        XCTAssertEqual(after.outbox.map(\.id), [second.id]); XCTAssertEqual(after.visibleEntities.count, 2)
    }

    func testConflictRemovesOptimisticDuplicateButRetainsRejectedData() {
        var state = DiskState()
        let duplicate = Command(action: "sleepStart", entity: Entity(type: "sleep", title: "Sleep"))
        let rejected = Command(entity: Entity(type: "feeding", title: "Bottle"))
        state.outbox = [duplicate, rejected]
        let messages = state.merge(.init(
            results: [.init(id: duplicate.id, status: "conflict", message: "Shared timer loaded", entityID: nil), .init(
                id: rejected.id,
                status: "rejected",
                message: "Choose a child",
                entityID: nil
            )],
            snapshot: .empty
        ))
        XCTAssertEqual(state.outbox.count, 1); XCTAssertEqual(state.outbox[0].error, "Choose a child")
        XCTAssertTrue(state.visibleEntities.isEmpty); XCTAssertEqual(messages.count, 2)
    }

    func testCorruptDataIsPreserved() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let bytes = Data("broken".utf8); let file = dir.appendingPathComponent("state.json"); try bytes.write(to: file)
        let storage = SharedStorage(directory: dir)
        XCTAssertThrowsError(try storage.enqueue(Command(entity: Entity(type: "note", title: "Note"))))
        XCTAssertEqual(try Data(contentsOf: file), bytes)
    }

    func testReauthenticationPreservesQueueAndRejectsFamilySwitch() throws {
        var state = DiskState()
        state.snapshot = try Snapshot.sample()
        state.selectedChildID = "sample-child"
        let command = Command(entity: Entity(
            type: "diaper",
            childID: "sample-child",
            title: "Diaper",
            fields: ["contents": "Wet"]
        ))
        state.outbox = [command]
        var refreshed = state.snapshot
        refreshed.serverTime += 100
        try state.accept(refreshed)
        XCTAssertEqual(state.outbox.map(\.id), [command.id])
        XCTAssertEqual(state.selectedChildID, "sample-child")
        var other = Snapshot.empty
        other.familyID = "other-synthetic-family"
        XCTAssertThrowsError(try state.accept(other))
        XCTAssertEqual(state.snapshot.familyID, refreshed.familyID)
        XCTAssertEqual(state.outbox.count, 1)
    }

    func testCareActionsAreDurableValidateChildAndDoNotToggleSleep() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let storage = SharedStorage(directory: dir)
        try storage.update { state in state.snapshot = try Snapshot.sample(); state.selectedChildID = "sample-child" }
        let first = try storage.record(.startSleep)
        let second = try storage.record(.startSleep)
        XCTAssertEqual(first.id, second.id)
        XCTAssertEqual(try storage.read().outbox.count, 1)
        _ = try storage.record(.endSleep, now: first.date.addingTimeInterval(61))
        XCTAssertThrowsError(try storage.record(.endSleep))
        XCTAssertThrowsError(try storage.record(.bottle(0, "oz")))
        XCTAssertThrowsError(try storage.record(.diaper("Wet"), childID: "removed-child"))
        _ = try storage.record(.bottle(4.5, "oz"))
        XCTAssertEqual(try SharedStorage(directory: dir).read().outbox.last?.entity.fields["amount"], "4.5")
    }

    func testFormulaDraftAndCustomChoicesSurviveRestartAndServerAcknowledgement() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let storage = SharedStorage(directory: dir)
        try storage.update { $0.snapshot = try Snapshot.sample(); $0.selectedChildID = "sample-child" }
        try storage.enqueue(Command(entity: Entity(type: "formula", title: "Example custom")))
        XCTAssertTrue(try SharedStorage(directory: dir).read().formulaOptions.contains("Example custom"))
        let feed = Command(entity: Entity(type: "feeding", childID: "sample-child", title: "Bottle", fields: ["amount": "5", "unit": "oz", "brand": "Example custom"]))
        try storage.enqueue(feed)
        _ = try storage.record(.bottle(3, "oz"))
        XCTAssertEqual(try storage.read().outbox.last?.entity.fields["brand"], "Example custom")
        XCTAssertNil(try storage.read().preferredFormula(for: "different-child"))
        let state = try storage.read()
        var snapshot = state.snapshot
        snapshot.feedingDefaults = [.init(childID: "sample-child", formula: "Server choice")]
        snapshot.formulaBrands = ["Example custom", "Server choice"]
        _ = try storage.update { $0.merge(.init(results: state.outbox.map { .init(id: $0.id, status: "accepted", message: nil, entityID: $0.entity.id) }, snapshot: snapshot)) }
        XCTAssertEqual(try SharedStorage(directory: dir).read().preferredFormula(for: "sample-child"), "Server choice")
    }

    func testImportedSnapshotDecodesUnknownsAndSourceAttribution() throws {
        let snapshot = try Snapshot.sampleNaraImport()
        XCTAssertEqual(snapshot.entities.count, 11)
        let feeds = snapshot.entities.filter { $0.type == "feeding" }
        XCTAssertTrue(feeds.contains { $0.fields["amount"] == nil })
        XCTAssertTrue(feeds.contains { $0.imported?.raw["Note"]?.contains("emoji") == true })
        XCTAssertEqual(snapshot.entities.first { $0.type == "medication" }?.imported?.updatedBy, "Editor")
        XCTAssertEqual(snapshot.summaries[0].feedingML, 148)
    }

    func testStorageChangePublishesAfterReleasingItsLock() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let storage = SharedStorage(directory: dir)
        let published = expectation(description: "Saved state can be read from the change observer")
        let observer = NotificationCenter.default.addObserver(forName: SharedStorage.didChange, object: nil, queue: nil) { _ in
            XCTAssertEqual(try? storage.read().outbox.count, 1)
            published.fulfill()
        }
        defer { NotificationCenter.default.removeObserver(observer) }
        try storage.enqueue(Command(entity: Entity(type: "note", title: "Synthetic note")))
        wait(for: [published], timeout: 1)
    }

    func testOwnerSampleUpgradePreservesAddedRecordsAndDoesNotOverwriteRealFamilies() throws {
        var sample = try Snapshot.sampleNaraImport()
        sample.user = User(id: "owner-synthetic", name: "Owner", preview: true)
        let childID = try XCTUnwrap(sample.entities.first { $0.type == "child" }?.id)
        var state = DiskState(); state.snapshot = try Snapshot.sample()
        let added = Entity(id: "added-log", type: "note", childID: "sample-child", title: "Keep this", fields: ["notes": "Offline note"])
        state.outbox = [Command(entity: added)]
        XCTAssertTrue(try state.installOwnerSample(sample))
        XCTAssertFalse(state.snapshot.entities.contains { $0.id == "sample-child" })
        XCTAssertEqual(state.snapshot.entities.first { $0.id == added.id }?.childID, childID)
        XCTAssertTrue(state.outbox.isEmpty)
        state.snapshot.entities[0].fields["notes"] = "Later edit"
        XCTAssertFalse(try state.installOwnerSample(sample))
        XCTAssertEqual(state.snapshot.entities[0].fields["notes"], "Later edit")
        state.snapshot.user.preview = false; state.snapshot.familyID = "real-family"; state.snapshot.entities = []
        XCTAssertFalse(try state.installOwnerSample(sample))
    }

    func testCaregiverPhotoDraftSurvivesRestartAndBlocksAccountSwitch() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let storage = SharedStorage(directory: dir)
        try storage.update { $0.snapshot = try Snapshot.sample(); $0.setCaregiverPhoto("synthetic-photo") }
        XCTAssertEqual(try storage.read().caregiverPhotoDraft?.photo, "synthetic-photo")
        var changed = try Snapshot.sample(); changed.user.id = "other-user"
        XCTAssertThrowsError(try storage.update { try $0.accept(changed) })
        try storage.update { $0.setCaregiverPhoto(nil) }
        XCTAssertNotNil(try storage.read().caregiverPhotoDraft)
        XCTAssertNil(try storage.read().caregiverPhotoDraft?.photo)
        let removal = try XCTUnwrap(storage.read().caregiverPhotoDraft)
        try storage.update { $0.setCaregiverPhoto("newer-photo") }
        try storage.update { try $0.acknowledgeCaregiverPhoto(removal.id, snapshot: $0.snapshot) }
        XCTAssertEqual(try storage.read().caregiverPhotoDraft?.photo, "newer-photo")
    }
}
