import Foundation

public struct FieldSpec: Codable, Sendable, Identifiable {
    public var key: String
    public var label: String
    public var kind: String
    public var options: [String]
    public var required: Bool
    public var id: String {
        key
    }
}

public struct TypeSpec: Codable, Sendable, Identifiable {
    public var id: String
    public var title: String
    public var symbol: String
    public var color: String
    public var fields: [FieldSpec]
}

public struct Catalog: Codable, Sendable {
    public var version: Int
    public var types: [TypeSpec]
    public static let shared: Catalog = {
        guard let url = Bundle.module.url(forResource: "catalog", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let catalog = try? JSONDecoder().decode(Catalog.self, from: data)
        else {
            preconditionFailure("The bundled product catalog is missing or invalid")
        }
        return catalog
    }()

    public func spec(_ type: String) -> TypeSpec {
        types.first { $0.id == type } ?? types[0]
    }
}

public struct Entity: Codable, Sendable, Identifiable, Equatable {
    public var id: String
    public var type: String
    public var childID: String
    public var title: String
    public var at: Double
    public var end: Double?
    public var fields: [String: String]
    public var version: Int
    public var updatedAt: Double
    public var deleted: Bool
    public var actor: String
    public var detail: String
    public var scheduled: Bool?
    public var date: Date {
        Date(timeIntervalSince1970: at)
    }

    public init(
        id: String = UUID().uuidString,
        type: String,
        childID: String = "",
        title: String,
        date: Date = .now,
        end: Date? = nil,
        fields: [String: String] = [:],
        version: Int = 0,
        updatedAt: Double = 0,
        deleted: Bool = false,
        actor: String = "",
        detail: String = ""
    ) {
        self.id = id; self.type = type; self.childID = childID; self.title = title; at = date.timeIntervalSince1970
        self.end = end?.timeIntervalSince1970; self.fields = fields; self.version = version; self.updatedAt = updatedAt
        self.deleted = deleted; self.actor = actor; self.detail = detail
    }
}

public struct User: Codable, Sendable, Equatable {
    public var id: String
    public var name: String
    public var preview: Bool
    public init(id: String, name: String, preview: Bool = false) {
        self.id = id; self.name = name; self.preview = preview
    }
}

public struct Member: Codable, Sendable, Identifiable {
    public var id: String
    public var name: String
}

public struct DaySummary: Codable, Sendable {
    public var childID: String
    public var feedingCount: Int
    public var feedingML: Int
    public var diaperCount: Int
    public var sleepMinutes: Int
    public var readingCount: Int
    public var day: String
}

public struct Snapshot: Codable, Sendable {
    public var version: Int
    public var familyID: String
    public var serverTime: Double
    public var entities: [Entity]
    public var summaries: [DaySummary]
    public var members: [Member]
    public var user: User
    public static var empty: Snapshot {
        Snapshot(
            version: 1,
            familyID: "",
            serverTime: 0,
            entities: [],
            summaries: [],
            members: [],
            user: User(id: "", name: "Caregiver")
        )
    }

    public static func sample() throws -> Snapshot {
        let url = Bundle.module.url(forResource: "sample", withExtension: "json")!
        return try JSONDecoder().decode(Snapshot.self, from: Data(contentsOf: url))
    }
}

public struct Command: Codable, Sendable, Identifiable {
    public var id: String
    public var action: String
    public var entity: Entity
    public var baseVersion: Int
    public var error: String?
    public init(action: String = "upsert", entity: Entity) {
        id = UUID().uuidString; self.action = action; self.entity = entity; baseVersion = entity.version
    }
}

public struct CommandResult: Codable, Sendable {
    public var id: String
    public var status: String
    public var message: String?
    public var entityID: String?
}

public struct SyncResponse: Codable, Sendable {
    public var results: [CommandResult]
    public var snapshot: Snapshot
}

public struct LoginResponse: Codable, Sendable {
    public var token: String
    public var user: User
    public var snapshot: Snapshot
}

public struct DiskState: Codable, Sendable {
    public var snapshot: Snapshot = .empty
    public var outbox: [Command] = []
    public var selectedChildID: String = ""
    public var localPreview: Bool = false
    public init() {}
    /// This projects only user-entered drafts. Business summaries remain server fields.
    public var visibleEntities: [Entity] {
        var records = snapshot.entities
        for command in outbox where command.error == nil {
            records.removeAll { $0.id == command.entity.id }
            if command.action != "delete" {
                records.append(command.entity)
            }
        }
        return records.filter { !$0.deleted }
    }

    public mutating func merge(_ response: SyncResponse) -> [String] {
        let successful = Set(response.results.filter { ["accepted", "conflict"].contains($0.status) }.map(\.id))
        outbox.removeAll { successful.contains($0.id) }
        for result in response.results where result.status == "rejected" {
            if let index = outbox
                .firstIndex(where: { $0.id == result.id })
            {
                outbox[index].error = result.message ?? "Could not save"
            }
        }
        snapshot = response.snapshot
        return response.results.compactMap { $0.status == "accepted" ? nil : $0.message }
    }
}
