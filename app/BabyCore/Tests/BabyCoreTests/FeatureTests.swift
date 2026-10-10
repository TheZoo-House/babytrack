import XCTest
@testable import BabyCore

final class FeatureTests: XCTestCase {
    func testLegacyImportDoesNotPretendItsOriginalCaregiverEditedItAtImportTime() throws {
        var state = DiskState(); state.snapshot = try Snapshot.sampleNaraImport()
        var record = try XCTUnwrap(state.snapshot.entities.first { $0.type == "feeding" })
        record.updatedAt = 100; record.actor = "Original caregiver"; record.updatedByID = nil
        state.snapshot.entities = [record]
        XCTAssertTrue(state.caregiverChanges(childID: record.childID, since: 50).isEmpty)
    }
    func testReportScopeEscapingAndPhotosExcluded() {
        let start = Date(timeIntervalSince1970: 1791580000)
        let note = Entity(type: "note", childID: "child", title: "Note", date: start, fields: ["notes": "=quoted \"note\",\nUnicode 😀", "photo": "private-image"])
        let other = Entity(type: "note", childID: "other", title: "Other", date: start)
        let rows = CareReports.records([note, other], childID: "child", from: start, through: start.addingTimeInterval(10))
        XCTAssertEqual(rows.count, 1)
        let csv = CareReports.csv(child: "Synthetic child", rows: rows)
        XCTAssertTrue(csv.contains("'=")); XCTAssertTrue(csv.contains("\"\"note\"\"")); XCTAssertTrue(csv.contains("Unicode 😀"))
        XCTAssertFalse(csv.contains("private-image")); XCTAssertFalse(csv.contains("Other"))
    }

    func testHandoffUsesEditorIdentityAndPersistsItsCursor() throws {
        var state = DiskState(); state.snapshot = try Snapshot.sample()
        var edited = Entity(type: "feeding", childID: "sample-child", title: "Bottle", fields: ["amount": "4", "unit": "oz"], updatedAt: 100, actor: state.snapshot.user.name)
        edited.updatedByID = "other-caregiver"; edited.updatedBy = "Other"
        state.snapshot.entities = [edited]
        XCTAssertEqual(state.caregiverChanges(childID: "sample-child", since: 50).count, 1)
        XCTAssertTrue(state.caregiverChanges(childID: "other-child", since: 50).isEmpty)
        state.markHandoffSeen(childID: "sample-child", through: 100)
        let stored = try JSONDecoder().decode(DiskState.self, from: JSONEncoder().encode(state))
        XCTAssertEqual(stored.handoffSeenAt?["sample-child"], 100)
        XCTAssertTrue(stored.caregiverChanges(childID: "sample-child", since: 100).isEmpty)
    }

    func testReminderNotificationActionsAndOfflineQueueAreDistinct() throws {
        XCTAssertEqual(CareNotification(recordID: "reminder", action: "default"), .open("reminder"))
        XCTAssertEqual(CareNotification(recordID: "reminder", action: "reminder-done"), .done("reminder"))
        XCTAssertEqual(CareNotification(recordID: "reminder", action: "reminder-snooze"), .snooze("reminder"))
        XCTAssertNil(CareNotification(recordID: "", action: "default"))
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storage = SharedStorage(directory: directory)
        try storage.update { state in
            state.snapshot = try Snapshot.sample(); state.snapshot.entities.append(Entity(id: "reminder", type: "reminder", childID: "sample-child", title: "Check bottle", fields: ["kind": "feeding"]))
        }
        let now = Date(timeIntervalSince1970: 1791589500)
        _ = try storage.record(.reminderSnooze("reminder", 15), now: now)
        let queued = try storage.read().outbox
        XCTAssertEqual(queued[0].action, "reminderSnooze"); XCTAssertEqual(queued[0].entity.at, now.timeIntervalSince1970 + 900)
    }

    func testRelativeReminderUsesNameChildAndSnoozeBoundary() {
        var reminder = Entity(type: "reminder", childID: "child", title: "Check", date: Date(timeIntervalSince1970: 1000), fields: ["trigger": "After last log", "kind": "medication", "anchorTitle": "Example", "afterHours": "1"])
        reminder.createdAt = 500
        let medicine = Entity(type: "medication", childID: "child", title: "example", date: Date(timeIntervalSince1970: 800))
        let other = Entity(type: "medication", childID: "other", title: "Example", date: Date(timeIntervalSince1970: 950))
        XCTAssertEqual(ReminderTiming.due(reminder, records: [medicine, other], now: Date(timeIntervalSince1970: 1000)), 4400)
        reminder.snoozedUntil = 5000
        XCTAssertEqual(ReminderTiming.due(reminder, records: [medicine], now: Date(timeIntervalSince1970: 1000)), 5000)
        reminder.fields["done"] = "true"; XCTAssertNil(ReminderTiming.due(reminder, records: [medicine]))
    }

    func testConciseTimesAndVolumesDoNotPretendPastLogsAreToday() {
        let now = Date(timeIntervalSince1970: 1791589500)
        XCTAssertEqual(CareTime.relative(now.addingTimeInterval(-7260), now: now), "2h 1m ago")
        XCTAssertEqual(CareTime.volume(0, imperial: true), "0 oz")
        XCTAssertEqual(CareTime.sleep(0), "0m"); XCTAssertEqual(CareTime.sleep(61), "1h 1m")
    }
}
