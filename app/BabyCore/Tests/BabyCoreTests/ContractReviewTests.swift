import XCTest
@testable import BabyCore

final class ContractReviewTests: XCTestCase {
    func testAllLocalDetailsMatchServerContracts() throws {
        struct Case: Decodable { var name: String; var entity: Entity; var records: [Entity]; var now: Double; var expected: String }
        let data = try Data(contentsOf: Bundle.module.url(forResource: "detail-cases", withExtension: "json")!)
        for fixture in try JSONDecoder().decode([Case].self, from: data) {
            let index = Dictionary(fixture.records.map { ($0.id, $0) }, uniquingKeysWith: { _, latest in latest })
            XCTAssertEqual(RecordDetails.text(for: fixture.entity, records: index, now: Date(timeIntervalSince1970: fixture.now)), fixture.expected, fixture.name)
        }
    }

    func testEditedDetailsNeverUseStaleCachedText() throws {
        var state = DiskState(); state.snapshot = try Snapshot.sample(); state.localPreview = true
        var bottle = try XCTUnwrap(state.visibleEntities.first { $0.type == "feeding" })
        bottle.fields["amount"] = "6"; bottle.detail = "4 oz · Formula"
        state.enqueue(Command(entity: bottle))
        XCTAssertTrue(try XCTUnwrap(state.visibleEntities.first { $0.id == bottle.id }).displayDetail.hasPrefix("6 oz"))
        XCTAssertEqual(state.snapshot.entities.first { $0.id == bottle.id }?.detail, "")
    }

    func testCatalogDefinesScopeUnitsAndLabels() {
        XCTAssertTrue(Catalog.shared.spec("formula").isInventory)
        XCTAssertFalse(Catalog.shared.spec("formula").requiresChild)
        XCTAssertEqual(Catalog.shared.spec("growth").options("unit", measure: "Height"), ["in", "cm"])
        XCTAssertEqual(Catalog.shared.spec("diaper").displayValue("consistency", "Mucous Mushy"), "Mucousy, Mushy")
        XCTAssertEqual(Catalog.shared.spec("growth").displayValue("measure", "Head circumference"), "Head size")
        XCTAssertEqual(Set(Catalog.shared.types.filter(\.canSchedule).map(\.id)), ["appointment", "reminder"])
    }

    func testActivityPayloadKeepsTheSharedAttributesAndStateNames() throws {
        let data = try Data(contentsOf: Bundle.module.url(forResource: "activity-payload", withExtension: "json")!)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: [String: Any]])
        let start = try XCTUnwrap(json["start"]), end = try XCTUnwrap(json["end"])
        XCTAssertEqual(start["attributes-type"] as? String, "SleepAttributes")
        let attributes = try JSONDecoder().decode(SleepAttributes.self, from: JSONSerialization.data(withJSONObject: start["attributes"]!))
        XCTAssertEqual(attributes.sessionID, "synthetic-session"); XCTAssertEqual(attributes.childID, "synthetic-child")
        let state = try JSONDecoder().decode(SleepAttributes.ContentState.self, from: JSONSerialization.data(withJSONObject: end["content-state"]!))
        XCTAssertTrue(state.ended); XCTAssertEqual(state.startedAt, 1791588600)
    }
}
