import Foundation

public extension DiskState {
    var resolvedChild: Entity? {
        let children = currentEntities.filter { $0.type == "child" }
        return children.first { $0.id == selectedChildID } ?? children.max { $0.at == $1.at ? $0.id > $1.id : $0.at < $1.at }
    }

    func latestRecord(_ type: String, for childID: String) -> Entity? {
        currentEntities.filter { $0.type == type && $0.childID == childID }.max { $0.at == $1.at ? $0.id > $1.id : $0.at < $1.at }
    }

    func activeSleep(for childID: String) -> Entity? {
        currentEntities.filter { $0.type == "sleep" && $0.childID == childID && $0.end == nil }.max { $0.at < $1.at }
    }

    mutating func repairChildSelection() { selectedChildID = resolvedChild?.id ?? "" }

    /// Discard an old response when a different family/session became active during the request.
    @discardableResult mutating func refresh(_ newSnapshot: Snapshot, familyID: String, userID: String) throws -> Bool {
        guard snapshot.familyID == familyID, snapshot.user.id == userID else { return false }
        try accept(newSnapshot)
        return true
    }
}
