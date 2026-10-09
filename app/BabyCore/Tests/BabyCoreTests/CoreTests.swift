@testable import BabyCore
import XCTest

final class CoreTests: XCTestCase {
    func testCatalogAndSnapshotContract() throws {
        XCTAssertEqual(Catalog.shared.types.count, 18)
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
}
