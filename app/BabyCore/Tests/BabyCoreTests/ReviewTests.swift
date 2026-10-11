import XCTest
@testable import BabyCore

final class ReviewTests: XCTestCase {
    func testSampleEditsPreserveTheRecordingCaregiver() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storage = SharedStorage(directory: directory)
        var state = DiskState(); state.snapshot = try Snapshot.sample(); state.localPreview = true
        var record = Entity(type: "note", childID: "sample-child", title: "Imported note"); record.actor = "Original caregiver"
        state.snapshot.entities.append(record); try storage.update { $0 = state }
        record.fields["notes"] = "Edited"; try storage.enqueue(Command(action: "upsert", entity: record))
        let edited = try XCTUnwrap(storage.read().visibleEntities.first { $0.id == record.id })
        XCTAssertEqual(edited.actor, "Original caregiver"); XCTAssertEqual(edited.updatedByID, state.snapshot.user.id)
        XCTAssertGreaterThan(edited.updatedAt, 0)
    }
    func testSleepOpeningAndEndingAreSeparateLinks() {
        XCTAssertEqual(DeepLink(url: URL(string: "babytrack://sleep?session=synthetic")!), .openSleep("synthetic"))
        XCTAssertEqual(DeepLink(url: DeepLink.endSleep("synthetic").url), .endSleep("synthetic"))
        for link in [DeepLink.log("temperature"), .record("synthetic-record"), .join("safe-invitation"), .openSleep("synthetic")] { XCTAssertEqual(DeepLink(url: link.url), link) }
        XCTAssertNil(DeepLink(url: URL(string: "https://untrusted.example/sleep?session=synthetic")!))
        XCTAssertNil(DeepLink(url: URL(string: "babytrack://record?type=missing")!))
    }

    func testChildResolutionIsStableAndRepairsMissingSelections() throws {
        var state = DiskState(); state.snapshot = try Snapshot.sample()
        let newer = Entity(id: "second-child", type: "child", title: "Second", date: .now)
        state.snapshot.entities.append(newer); state.selectedChildID = "removed-child"
        XCTAssertEqual(state.resolvedChild?.id, newer.id)
        state.repairChildSelection(); XCTAssertEqual(state.selectedChildID, newer.id)
        state.snapshot.entities.reverse(); XCTAssertEqual(state.resolvedChild?.id, newer.id)
    }

    func testLateSnapshotDoesNotReplaceANewerSession() throws {
        var state = DiskState(); let original = try Snapshot.sample(); state.snapshot = original
        var newer = original; newer.familyID = "new-family"; try state.accept(newer)
        XCTAssertFalse(try state.refresh(original, familyID: original.familyID, userID: original.user.id))
        XCTAssertEqual(state.snapshot.familyID, newer.familyID)
        let record = Entity(type: "note", childID: "new-child", title: "Pending in new family")
        let pending = Command(action: "upsert", entity: record); state.outbox = [pending]
        _ = state.merge(SyncResponse(results: [CommandResult(id: pending.id, status: "accepted", message: "", entityID: record.id)], snapshot: original), familyID: original.familyID, userID: original.user.id)
        XCTAssertEqual(state.snapshot.familyID, newer.familyID)
        XCTAssertEqual(state.outbox.first?.id, pending.id)
    }

    func testStartConflictRepointsAStopWaitingInAnotherBatch() throws {
        var state = DiskState(); state.snapshot = try Snapshot.sample()
        let local = Entity(id: "offline-sleep", type: "sleep", childID: "sample-child", title: "Sleep", date: Date(timeIntervalSince1970: 1000))
        let start = Command(action: "sleepStart", entity: local)
        var stopped = local; stopped.end = 1600; let stop = Command(action: "sleepStop", entity: stopped)
        state.outbox = [start, stop]
        var snapshot = state.snapshot; var shared = local; shared.id = "shared-sleep"; shared.at = 900; shared.version = 2; snapshot.entities.append(shared)
        let result = CommandResult(id: start.id, status: "conflict", message: "Shared timer loaded", entityID: shared.id)
        _ = state.merge(SyncResponse(results: [result], snapshot: snapshot))
        XCTAssertEqual(state.outbox.count, 1); XCTAssertEqual(state.outbox[0].entity.id, shared.id)
        XCTAssertEqual(state.outbox[0].entity.at, shared.at); XCTAssertEqual(state.outbox[0].entity.end, stopped.end)
        XCTAssertEqual(state.outbox[0].baseVersion, shared.version)
    }

    func testOverlappingSleepCountsEachMinuteOnce() throws {
        var state = DiskState(); state.localPreview = true
        let start = Date(timeIntervalSince1970: 1791594000)
        state.snapshot.entities = [
            Entity(type: "sleep", childID: "child", title: "Sleep", date: start, end: start.addingTimeInterval(7200)),
            Entity(type: "sleep", childID: "child", title: "Sleep", date: start.addingTimeInterval(3600), end: start.addingTimeInterval(10800))
        ]
        XCTAssertEqual(state.careSummary(for: "child", now: start.addingTimeInterval(14400), timeZone: TimeZone(secondsFromGMT: 0)!)?.sleepMinutes, 180)
    }
}
