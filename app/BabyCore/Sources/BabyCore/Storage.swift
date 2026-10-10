import Foundation
#if canImport(Darwin)
    import Darwin
#else
    import Glibc
#endif

public enum StorageError: Error, LocalizedError {
    case lockFailed, corrupt
    public var errorDescription: String? {
        self == .corrupt ? "Saved data could not be read. It has been preserved for recovery." :
            "Storage is busy. Try again."
    }
}

/// Every app and widget write uses the same cross-process lock and atomic replace.
public struct SharedStorage: Sendable {
    public static let didChange = Notification.Name("house.thezoo.babytrack.stateChanged")
    public let directory: URL
    public init(directory: URL) {
        self.directory = directory
    }

    public static var application: SharedStorage {
        #if os(iOS)
            let group = Bundle.main.object(forInfoDictionaryKey: "AppGroup") as? String ?? "group.house.thezoo.babytrack"
            let folder = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group)
                ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("Babytrack")
        #else
            let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("Babytrack")
        #endif
        return SharedStorage(directory: folder)
    }

    private func locked<T>(_ body: () throws -> T) throws -> T {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let fd = open(directory.appendingPathComponent("state.lock").path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard fd >= 0 else { throw StorageError.lockFailed }
        defer { close(fd) }
        guard flock(fd, LOCK_EX) == 0 else { throw StorageError.lockFailed }
        defer { flock(fd, LOCK_UN) }
        return try body()
    }

    private func readUnlocked() throws -> DiskState {
        let file = directory.appendingPathComponent("state.json")
        guard FileManager.default.fileExists(atPath: file.path) else { return DiskState() }
        do { return try JSONDecoder().decode(DiskState.self, from: Data(contentsOf: file)) }
        catch { throw StorageError.corrupt }
    }

    public func read() throws -> DiskState {
        try locked { try readUnlocked() }
    }

    @discardableResult public func update<T>(_ body: (inout DiskState) throws -> T) throws -> T {
        let result = try locked {
            var state = try readUnlocked()
            let result = try body(&state)
            let file = directory.appendingPathComponent("state.json")
            let data = try JSONEncoder().encode(state)
            #if os(iOS)
                try data.write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            #else
                try data.write(to: file, options: .atomic)
            #endif
            return result
        }
        NotificationCenter.default.post(name: Self.didChange, object: nil)
        return result
    }

    public func enqueue(_ command: Command) throws {
        try update { $0.enqueue(command) }
    }
}

extension DiskState {
    mutating func enqueue(_ original: Command) {
        var command = original
        command.entity.detail = ""
        command.entity.updatedBy = snapshot.user.name
        command.entity.updatedByID = snapshot.user.id
        if command.entity.createdAt == nil { command.entity.createdAt = Date.now.timeIntervalSince1970 }
        if command.entity.type == "reminder", command.entity.fields["recipients"] == "Only me", command.entity.recipientUserID == nil { command.entity.recipientUserID = snapshot.user.id }
        if command.entity.actor.isEmpty { command.entity.actor = snapshot.user.name }
        if command.entity.type == "feeding", command.action == "upsert", !command.entity.deleted {
            let explicit = command.entity.fields["brand"]?.trimmingCharacters(in: .whitespacesAndNewlines)
            if explicit == nil {
                command.entity.fields["brand"] = preferredFormula(for: command.entity.childID)
            }
            if let brand = command.entity.fields["brand"], !brand.isEmpty {
                if draftFormulaSelections == nil {
                    draftFormulaSelections = [:]
                }
                draftFormulaSelections?[command.entity.childID] = brand
            }
        }
        if localPreview {
            snapshot.entities.removeAll { $0.id == command.entity.id }
            if command
                .action !=
                "delete"
            {
                var e = command.entity; e.version += 1; e.updatedAt = Date.now.timeIntervalSince1970; snapshot.entities.append(e)
            }
        } else {
            outbox.append(command)
        }
    }
}
