import BabyCore
import SwiftUI

struct SettingsView: View {
    var body: some View {
        AppList {
            NavigationLink { PreferenceView() } label: { Label("Appearance & units", systemImage: "paintpalette") }
            NavigationLink { NotificationSettingsView() } label: { Label(
                "Notifications & reminders",
                systemImage: "bell"
            ) }
            NavigationLink { ConnectionView() } label: { Label("Connection & sync", systemImage: "network") }
            NavigationLink { AccountView() } label: { Label("Account & data", systemImage: "person.crop.circle") }
        }.appList().navigationTitle("Settings")
    }
}

struct PreferenceView: View {
    @Environment(AppStore.self) private var store
    var body: some View {
        @Bindable var store = store
        AppList {
            Picker("Appearance", selection: $store.appearance) {
                Text("System").tag("system"); Text("Light").tag("light"); Text("Dark").tag("dark")
            }
            .onChange(of: store.appearance) { _, value in store.setPreference(
                "appearance",
                value
            ) }
            Picker("Units", selection: $store.unitSystem) {
                Text("US customary").tag("imperial"); Text("Metric").tag("metric")
            }
            .onChange(of: store.unitSystem) { _, value in store.setPreference(
                "units",
                value
            ) }
        }.appList().navigationTitle("Appearance & units")
    }
}

struct ConnectionView: View {
    @Environment(AppStore.self) private var store
    @State private var draft = ""
    var body: some View {
        AppList {
            Section("Server") {
                TextField("https://server.example", text: $draft).keyboardType(.URL).textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button("Connect") {
                    guard let url = URL(string: draft), ["https", "http"].contains(url.scheme),
                          url.host != nil else { store.error = "Enter a valid server URL."; return }
                    guard !store.signedIn || draft == store.backendURL
                    else { store.error = "Sign out before changing servers."; return }
                    store.backendURL = draft
                    Task { await store.prepareSignIn(); await store.sync() }
                }
            }
            Section("Sync") {
                LabeledContent("Pending records", value: String(store.pendingCount))
                if store.state.snapshot.serverTime > 0 {
                    LabeledContent(
                        "Last server snapshot",
                        value: Date(timeIntervalSince1970: store.state.snapshot.serverTime).formatted(
                            date: .abbreviated,
                            time: .shortened
                        )
                    )
                }
                Button("Sync now") { Task { await store.sync() } }.disabled(store.syncing || !store.signedIn)
                ForEach(store.state.outbox) { command in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(command.entity.title); if let error = command
                            .error
                        {
                            Text(error).font(.caption).foregroundStyle(.red); Button(
                                "Discard rejected change",
                                role: .destructive
                            ) { store.discard(command.id) }
                        }
                    }
                }
            }
        }.appList().navigationTitle("Connection & sync").onAppear { draft = store.backendURL }
    }
}

struct NotificationSettingsView: View {
    @Environment(AppStore.self) private var store
    var body: some View {
        @Bindable var store = store
        AppList {
            Toggle("Notifications on this device", isOn: $store.notificationsEnabled)
                .onChange(of: store.notificationsEnabled) { _, enabled in
                    Task { await SleepCoordinator.shared.setNotifications(
                        enabled,
                        store: store
                    ) }
                }
            Section("Family reminders") {
                ForEach(store.entities.filter { $0.type == "reminder" && $0.childID == store.childID }) { reminder in
                    Button { store.detail = reminder } label: { VStack(alignment: .leading, spacing: 4) { RecordRow(entity: reminder, showDate: true); if reminder.fields["done"] == "true" { Text("Done").font(.caption).foregroundStyle(Palette.secondary).accessibilityIdentifier("reminderDoneStatus") } } }.buttonStyle(.plain)
                }
                Button("Add reminder", systemImage: "plus") { store.form = FormRequest(type: "reminder") }
                    .disabled(store.childID.isEmpty)
            }
        }.appList().navigationTitle("Notifications & reminders")
    }
}

struct AccountView: View {
    @State private var showProfile = false
    @Environment(AppStore.self) private var store
    @State private var exportURL: URL?
    var body: some View {
        AppList {
            Section {
                Button { showProfile = true } label: {
                    HStack { ProfileAvatar(photo: store.caregiverPhoto); Text("Caregiver profile"); Spacer(); Text(store.state.snapshot.user.name).foregroundStyle(Palette.secondary) }
                }
                if store.isPreview {
                    Text("Sample family").foregroundStyle(.secondary)
                }
                NavigationLink { NaraImportView() } label: { Label("Import Nara Baby", systemImage: "doc.badge.arrow.up") }
                Button("Export records") {
                    do {
                        let url = FileManager.default.temporaryDirectory
                            .appendingPathComponent("Babytrack-export.json"); try JSONEncoder().encode(store.state)
                            .write(
                                to: url,
                                options: .atomic
                            ); exportURL = url
                    } catch { store.error = error.localizedDescription }
                }
                if let exportURL {
                    ShareLink("Share export", item: exportURL)
                }
                Button("Sign out") {
                    Task { do { try await store.signOut() } catch { store.error = error.localizedDescription } }
                }
            }
            if store.signedIn {
                Section {
                    HStack {
                        Spacer()
                        DestructiveActionButton(title: "Delete account", question: "Delete your account?", message: "Shared records remain for other caregivers. If you are the last caregiver, the family's records are deleted.", identifier: "deleteAccount", enabled: store.pendingCount == 0) {
                            Task { do { let _: [String: Bool] = try await store.request("/v1/account/delete", body: Data("{}".utf8)); try await store.signOut(revoke: false) } catch { store.error = error.localizedDescription } }
                        }
                        Spacer()
                    }.listRowSeparator(.hidden)
                }
            }
        }.appList().navigationTitle("Account & data").sheet(isPresented: $showProfile) { CaregiverProfileView() }
    }
}
