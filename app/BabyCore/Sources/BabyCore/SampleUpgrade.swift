import Foundation

public extension DiskState {
    /// Replaces starter care history, preserving additions, edited inventory and queued work.
    @discardableResult mutating func installOwnerSample(_ sample: Snapshot) throws -> Bool {
        guard snapshot.user.preview || (snapshot.familyID.isEmpty && snapshot.entities.isEmpty) else { return false }
        guard snapshot.familyID != sample.familyID || snapshot.entities.contains(where: { $0.id == "sample-child" }) else { return false }
        let starter = try Snapshot.sample()
        let starterIDs = Set(starter.entities.map(\.id))
        guard let child = sample.entities.first(where: { $0.type == "child" }) else { return false }
        var retained = snapshot.entities.filter {
            !starterIDs.contains($0.id) || Catalog.shared.spec($0.type).isInventory || ($0.id != "sample-child" && $0.version > 1)
        }
        for command in outbox {
            retained.removeAll { $0.id == command.entity.id }
            if command.action != "delete" {
                retained.append(command.entity)
            }
        }
        let oldPhoto = outbox.last(where: { $0.entity.id == "sample-child" })?.entity.fields["photo"]
            ?? snapshot.entities.first(where: { $0.id == "sample-child" })?.fields["photo"]
        let profilePhoto = caregiverPhotoDraft != nil ? caregiverPhotoDraft?.photo : snapshot.user.photo
        snapshot = sample
        if let oldPhoto, let index = snapshot.entities.firstIndex(where: { $0.id == child.id }) {
            snapshot.entities[index].fields["photo"] = oldPhoto
        }
        for var entity in retained {
            if entity.id == "sample-child" {
                continue
            }
            if entity.childID == "sample-child" {
                entity.childID = child.id
            }
            if !snapshot.entities.contains(where: { $0.id == entity.id }) {
                snapshot.entities.append(entity)
            }
        }
        outbox = []; caregiverPhotoDraft = nil
        if let profilePhoto {
            snapshot.user.photo = profilePhoto
            if let index = snapshot.members.firstIndex(where: { $0.id == snapshot.user.id }) {
                snapshot.members[index].photo = profilePhoto
            }
        }
        if let formula = draftFormulaSelections?.removeValue(forKey: "sample-child") {
            draftFormulaSelections?[child.id] = formula
        }
        selectedChildID = child.id; localPreview = true
        return true
    }

    mutating func acknowledgeCaregiverPhoto(_ id: String, snapshot newSnapshot: Snapshot) throws {
        guard snapshot.familyID == newSnapshot.familyID, snapshot.user.id == newSnapshot.user.id else { throw SessionChangeError.pendingChanges }
        snapshot = newSnapshot
        if caregiverPhotoDraft?.id == id {
            caregiverPhotoDraft = nil
        }
    }

    mutating func setCaregiverPhoto(_ photo: String?) {
        if localPreview {
            snapshot.user.photo = photo
            if let index = snapshot.members.firstIndex(where: { $0.id == snapshot.user.id }) {
                snapshot.members[index].photo = photo
            }
        } else {
            caregiverPhotoDraft = CaregiverPhotoDraft(userID: snapshot.user.id, photo: photo)
        }
    }
}
