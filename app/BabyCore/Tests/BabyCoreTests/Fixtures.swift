import Foundation
import BabyCore

extension Snapshot {
    static func summaryContractCases() throws -> Data { try Data(contentsOf: Bundle.module.url(forResource: "summary-cases", withExtension: "json")!) }
    static func sampleNaraImport() throws -> Snapshot { try JSONDecoder().decode(Snapshot.self, from: Data(contentsOf: Bundle.module.url(forResource: "nara-import-sample", withExtension: "json")!)) }
}
