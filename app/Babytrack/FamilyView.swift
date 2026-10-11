import BabyCore
import SwiftUI

struct FamilyView: View {
    @State private var showProfile = false
    @Environment(AppStore.self) private var store
    @State private var invitation: String?
    @State private var joinCode = ""
    @State private var handoff = false
    @State private var handoffRecord: Entity?
    var body: some View {
        AppList {
            Section("Children") {
                ForEach(store.children) { child in
                    Button { store.detail = child } label: {
                        HStack(spacing: 14) {
                            ProfileAvatar(photo: child.fields["photo"], child: true); VStack(alignment: .leading, spacing: 4) {
                                Text(child.title).foregroundStyle(Palette.ink); if !child.detail
                                    .isEmpty
                                {
                                    Text(child.detail).font(.caption).foregroundStyle(.secondary)
                                }
                            }; Spacer(); if child.id == store
                                .childID
                            {
                                Image(systemName: "checkmark").foregroundStyle(Palette.accent)
                            }
                        }.contentShape(Rectangle())
                    }
                }
                Button("Add child", systemImage: "plus") { store.form = FormRequest(type: "child") }
            }
            Section("Caregivers") {
                Button("Caregiver handoff", systemImage: "clock.arrow.circlepath") { handoff = true }.disabled(store.childID.isEmpty).accessibilityIdentifier("openHandoff")
                ForEach(store.state.snapshot.members) { member in
                    if member.id == store.state.snapshot.user.id {
                        Button { showProfile = true } label: {
                            HStack { ProfileAvatar(photo: store.caregiverPhoto(for: member)); Text(member.name); Spacer(); Image(systemName: "pencil").font(.caption) }.contentShape(Rectangle())
                        }.buttonStyle(.plain).accessibilityLabel("Edit caregiver profile")
                    } else {
                        HStack { ProfileAvatar(photo: store.caregiverPhoto(for: member)); Text(member.name) }
                    }
                }
                if store.signedIn {
                    Button("Create invitation", systemImage: "person.badge.plus") {
                        Task {
                            do { invitation = try await store.invite() } catch {
                                store.error = error.localizedDescription
                            }
                        }
                    }
                    if let invitation {
                        ShareLink(item: DeepLink.join(invitation).url) { Label(
                            "Share invitation",
                            systemImage: "square.and.arrow.up"
                        ) }
                        Text(invitation).font(.caption.monospaced()).textSelection(.enabled)
                        Text("One use. Expires after 7 days.").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            if store.signedIn {
                Section("Join a family") {
                    Text("Joining leaves this family. If you are its last caregiver, its records are removed. Export them first if you want to keep a copy.").font(.caption).foregroundStyle(Palette.secondary)
                    TextField("Invitation code", text: $joinCode).textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button("Join") {
                        Task {
                            do { try await store.join(joinCode); joinCode = "" } catch {
                                store.error = error.localizedDescription
                            }
                        }
                    }.disabled(joinCode.isEmpty)
                }
            }
        }.appList().navigationTitle("Family").sheet(isPresented: $showProfile) { CaregiverProfileView() }
            .sheet(isPresented: $handoff, onDismiss: {
                if let record = handoffRecord { store.detail = record; handoffRecord = nil }
            }) { HandoffView(childID: store.childID) { handoffRecord = $0; handoff = false } }
    }
}
