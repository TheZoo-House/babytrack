import BabyCore
import CryptoKit
import Foundation
import Security
import SwiftUI
import WidgetKit

@MainActor @Observable final class AppStore {
    private struct ViewState {
        var minute: Int
        var records: [Entity]
        var children: [Entity]
        var child: Entity?
        var activeSleep: Entity?
        var care: [Entity]
    }
    var state = DiskState() { didSet { viewCache = nil; summaryCache = nil } }
    @ObservationIgnored private var viewCache: ViewState?
    @ObservationIgnored private var summaryCache: (minute: Int, zone: String, childID: String, value: DaySummary?)?
    var error: String?
    var notice: String?
    var syncing = false
    var showWelcome = true
    var reauthenticationRequired = false
    var nonce: String?
    var selectedSection: AppSection = .today
    var form: FormRequest?
    private var pendingForm: FormRequest?
    var detail: Entity?
    func formAfterDetail(_ request: FormRequest) { pendingForm = request; detail = nil }
    func detailDismissed() { if let request = pendingForm { pendingForm = nil; form = request } }
    var notificationsEnabled = UserDefaults.standard.bool(forKey: "notificationsEnabled")
    var unitSystem = UserDefaults.standard.string(forKey: "units") ?? "imperial"
    var appearance = UserDefaults.standard.string(forKey: "appearance") ?? "system"
    var backendURL: String {
        didSet { UserDefaults.standard.set(backendURL, forKey: "backendURL") }
    }

    let storage: SharedStorage
    let testing: Bool
    private var token: String?
    private var projected: ViewState {
        // Read observable state even on a cache hit so screens react to incoming changes.
        let disk = state
        let minute = Int(Date.now.timeIntervalSince1970 / 60)
        if let cached = viewCache, cached.minute == minute { return cached }
        let records = disk.visibleEntities
        let profiles = records.filter { $0.type == "child" }
        let chosenID = disk.resolvedChild?.id ?? ""
        let activeID = disk.activeSleep(for: chosenID)?.id
        let care = records.filter { $0.childID == chosenID && Catalog.shared.spec($0.type).scope == "care" && $0.scheduled != true }.sorted { $0.at > $1.at }
        let result = ViewState(minute: minute, records: records, children: profiles,
                               child: profiles.first { $0.id == chosenID },
                               activeSleep: records.first { $0.id == activeID }, care: care)
        viewCache = result
        return result
    }

    var entities: [Entity] { projected.records }
    var children: [Entity] { projected.children }
    var child: Entity? { projected.child }

    var childID: String {
        child?.id ?? ""
    }

    var activeSleep: Entity? { projected.activeSleep }

    func summary(at date: Date) -> DaySummary? {
        let disk = state, id = childID, zone = TimeZone.current
        let minute = Int(date.timeIntervalSince1970 / 60)
        if let cached = summaryCache, cached.minute == minute, cached.zone == zone.identifier, cached.childID == id { return cached.value }
        let result = disk.careSummary(for: id, now: date, timeZone: zone)
        summaryCache = (minute, zone.identifier, id, result)
        return result
    }

    var signedIn: Bool {
        token != nil
    }

    var isPreview: Bool {
        state.localPreview || state.snapshot.user.preview
    }

    var pendingCount: Int {
        state.outbox.count + (state.caregiverPhotoDraft == nil ? 0 : 1)
    }

    var care: [Entity] { projected.care }

    init() {
        #if DEBUG
            testing = Self.testingRequested
        #else
            testing = false
        #endif
        storage = testing ?
            SharedStorage(directory: FileManager.default.temporaryDirectory
                .appendingPathComponent("synthetic-ui-state-" + UUID().uuidString)) : .application
        backendURL = UserDefaults.standard.string(forKey: "backendURL") ?? Bundle.main
            .object(forInfoDictionaryKey: "BackendURL") as? String ?? "http://127.0.0.1:8792"
        token = testing ? nil : SessionKeychain.read()
        if testing {
            assert(IntentCatalog.valid, "Siri options must match the shared catalog")
            unitSystem = "imperial"; notificationsEnabled = false
        }
        #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--ui-http-test") {
                backendURL = "http://127.0.0.1:18792"
            }
        #endif
        do { state = try storage.read() } catch { self.error = error.localizedDescription }
        #if DEBUG
            do { try installSyntheticTestingState() } catch { self.error = error.localizedDescription }
        #endif
        do {
            #if DEBUG
                let ownerRender = ProcessInfo.processInfo.arguments.contains("--owner-preview-testing")
            #else
                let ownerRender = false
            #endif
            if !testing || ownerRender, state.snapshot.user.preview || token == nil, let url = Bundle.main.url(forResource: "OwnerPreview", withExtension: "json") {
                let sample = try JSONDecoder().decode(Snapshot.self, from: Data(contentsOf: url))
                let upgraded = try storage.update { try $0.installOwnerSample(sample) }
                if upgraded {
                    if !testing {
                        try SessionKeychain.write(nil)
                    }; token = nil; state = try storage.read()
                }
            }
        } catch { self.error = error.localizedDescription }
        showWelcome = children.isEmpty && token == nil
        #if DEBUG
            form = ownerTestingForm()
        #endif
    }

    func reload() {
        do { state = try storage.read() } catch { self.error = error.localizedDescription }
        showWelcome = children.isEmpty && token == nil
        WidgetCenter.shared.reloadAllTimelines()
        BabytrackShortcuts.updateAppShortcutParameters()
    }

    func selectChild(_ id: String) {
        do { try storage.update { $0.selectedChildID = id }; reload() } catch { self.error = error.localizedDescription
        }
    }

    func request<T: Decodable>(_ path: String, body: Data? = nil, authenticated: Bool = true) async throws -> T {
        do { return try await APIClient(baseURL: backendURL).request(path, body: body, token: authenticated ? token : nil) }
        catch let error as APIError {
            if authenticated, error.status == 401 { reauthenticationRequired = true }
            throw error
        }
    }

    func body(_ object: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: object)
    }

    func prepareSignIn() async {
        guard !testing else { return }
        do { let result: [String: String] = try await request(
            "/v1/auth/challenge",
            body: Data("{}".utf8),
            authenticated: false
        ); nonce = result["nonce"] } catch { nonce = nil }
    }

    func signIn(identityToken: String, name: String) async {
        do {
            guard let nonce else { throw APIError(message: "Reconnect to the server and try sign-in again.") }
            let login: LoginResponse = try await request(
                "/v1/auth/apple",
                body: body([
                    "identityToken": identityToken,
                    "nonce": nonce,
                    "name": name,
                    "timeZone": TimeZone.current.identifier,
                ]),
                authenticated: false
            )
            try accept(login); await prepareSignIn()
        } catch { self.error = error.localizedDescription }
    }

    func preview() async {
        guard pendingCount == 0,
              !reauthenticationRequired else { error = "Sign in again to sync your saved records first."; return }
        do {
            if !testing, let url = Bundle.main.url(forResource: "OwnerPreview", withExtension: "json") {
                var fresh = DiskState(); fresh.snapshot = try JSONDecoder().decode(Snapshot.self, from: Data(contentsOf: url)); fresh.localPreview = true
                fresh.selectedChildID = fresh.snapshot.entities.first { $0.type == "child" }?.id ?? ""
                try storage.update { $0 = fresh }; reload(); notice = "Sample family is stored on this device."; return
            }
            let login: LoginResponse = try await request(
                "/v1/auth/preview",
                body: Data("{}".utf8),
                authenticated: false
            )
            try accept(login)
        } catch {
            do {
                var fresh = DiskState(); fresh.snapshot = try Snapshot.sample(); fresh.localPreview = true
                fresh.selectedChildID = fresh.snapshot.entities.first { $0.type == "child" }?.id ?? ""
                try storage.update { $0 = fresh }; reload(); notice = "Sample family is stored on this device."
            } catch { self.error = error.localizedDescription }
        }
    }

    private func accept(_ login: LoginResponse) throws {
        try storage.update { current in
            try current.accept(login.snapshot)
            if !testing {
                try SessionKeychain.write(login.token)
            }
        }
        token = login.token
        reauthenticationRequired = false
        reload(); showWelcome = false
    }

    @discardableResult func save(_ entity: Entity, action: String = "upsert") -> Bool {
        do {
            try storage.enqueue(Command(action: action, entity: entity)); reload()
            notice = state.localPreview ? "Saved on this device" : "Saved"
            Task { await sync() }
            return true
        } catch { self.error = error.localizedDescription; return false }
    }

    func discard(_ id: String) {
        do { try storage.update { $0.outbox.removeAll { $0.id == id } }; reload() } catch {
            self.error = error.localizedDescription
        }
    }

    func sync() async {
        guard !syncing, signedIn, !state.localPreview, !reauthenticationRequired else { return }
        syncing = true; defer { syncing = false }
        do {
            let disk = try storage.read()
            if let draft = disk.caregiverPhotoDraft, draft.userID == disk.snapshot.user.id {
                let snap: Snapshot = try await request("/v1/caregiver/profile", body: body(["photo": draft.photo as Any? ?? NSNull(), "timeZone": TimeZone.current.identifier]))
                try storage.update { try $0.acknowledgeCaregiverPhoto(draft.id, snapshot: snap) }
            }
            let commands = Array(disk.outbox.filter { $0.error == nil }.prefix(50))
            if commands.isEmpty {
                let snap: Snapshot =
                    try await request(
                        "/v1/snapshot?timeZone=\(TimeZone.current.identifier.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "UTC")"
                    )
                try storage.update { try $0.refresh(snap, familyID: disk.snapshot.familyID, userID: disk.snapshot.user.id) }
            } else {
                struct Payload: Encodable { var commands: [Command]; var timeZone: String; var familyID: String }
                let response: SyncResponse = try await request(
                    "/v1/sync",
                    body: JSONEncoder().encode(Payload(commands: commands, timeZone: TimeZone.current.identifier, familyID: disk.snapshot.familyID))
                )
                let messages = try storage.update { $0.merge(response, familyID: disk.snapshot.familyID, userID: disk.snapshot.user.id) }
                if let message = messages.first {
                    error = message
                }
            }
            reload(); await SleepCoordinator.shared.reconcile(store: self)
        } catch {
            notice = pendingCount > 0 ? "Offline · \(pendingCount) waiting to sync" : "Offline · showing saved records"
        }
    }

    var caregiverPhoto: String? {
        if let draft = state.caregiverPhotoDraft, draft.userID == state.snapshot.user.id {
            return draft.photo
        }
        return state.snapshot.user.photo
    }

    func caregiverPhoto(for member: Member) -> String? {
        member.id == state.snapshot.user.id ? caregiverPhoto : member.photo
    }

    @discardableResult func setCaregiverPhoto(_ photo: String?) -> Bool {
        do { try storage.update { $0.setCaregiverPhoto(photo) }; reload(); Task { await sync() }; return true }
        catch { self.error = error.localizedDescription; return false }
    }

    func toggleSleep() {
        guard child != nil else { form = FormRequest(type: "child"); return }
        do { try storage.record(activeSleep == nil ? .startSleep : .endSleep, childID: childID); reload(); Task { await sync() } }
        catch { self.error = error.localizedDescription }
        Task { await SleepCoordinator.shared.reconcile(store: self) }
    }

    func endSleep(_ sessionID: String) async {
        if !entities.contains(where: { $0.id == sessionID }) {
            await sync()
        }
        guard let sleep = entities.first(where: { $0.id == sessionID && $0.type == "sleep" }),
              sleep.end == nil else { return }
        do { try storage.record(.endSleepSession(sessionID), childID: sleep.childID); reload(); await sync() }
        catch { self.error = error.localizedDescription }
        await SleepCoordinator.shared.reconcile(store: self)
    }

    func quickDiaper() {
        do { try storage.record(.diaper("Wet"), childID: childID); reload(); Task { await sync() } } catch { self.error = error.localizedDescription }
    }
    func reminder(_ id: String, snooze: Bool) {
        guard entities.contains(where: { $0.id == id }) else {
            Task {
                await sync()
                guard entities.contains(where: { $0.id == id }) else { error = "This reminder is no longer available."; return }
                reminder(id, snooze: snooze)
            }
            return
        }
        // Persist before a notification delegate returns and the app can be suspended.
        do { try storage.record(snooze ? .reminderSnooze(id, 15) : .reminderDone(id)); reload(); Task { await sync() } }
        catch { self.error = error.localizedDescription }
    }

    func handle(_ link: DeepLink) {
        switch link {
        case let .log(type): form = FormRequest(type: type, childID: childID)
        case let .endSleep(id): Task { await endSleep(id) }
        case let .openSleep(id):
            if let sleep = entities.first(where: { $0.id == id && $0.type == "sleep" }) { selectChild(sleep.childID) }
            selectedSection = .today
        case let .record(id):
            Task {
                if !entities.contains(where: { $0.id == id }) { await sync() }
                if let record = entities.first(where: { $0.id == id }) { if !record.childID.isEmpty { selectChild(record.childID) }; detail = record }
                else { error = "This record is no longer available." }
            }
        case let .join(code): Task { do { try await join(code) } catch { self.error = error.localizedDescription } }
        }
    }

    func signOut(revoke: Bool = true) async throws {
        guard pendingCount == 0 else { throw APIError(message: "Sync or discard pending records before signing out.") }
        if signedIn, revoke {
            let _: [String: Bool] = try await request(
                "/v1/devices",
                body: body(["id": SleepCoordinator.shared.deviceID, "enabled": false])
            )
            let _: [String: Bool] = try await request("/v1/auth/logout", body: Data("{}".utf8))
        }
        try SessionKeychain.write(nil); token = nil
        try storage.update { $0 = DiskState() }; reload()
        Task { await SleepCoordinator.shared.reconcile(store: self) }
    }

    func invite() async throws
        -> String
    {
        struct Invite: Decodable { var code: String }; let invite: Invite = try await request(
            "/v1/invites",
            body: Data("{}".utf8)
        ); return invite.code
    }

    func join(_ code: String) async throws {
        guard pendingCount == 0 else { throw APIError(message: "Sync pending records before joining a family.") }
        struct Result: Decodable { var snapshot: Snapshot }
        let result: Result = try await request(
            "/v1/invites/join",
            body: body([
                "code": code.trimmingCharacters(in: .whitespacesAndNewlines),
                "timeZone": TimeZone.current.identifier,
            ])
        )
        try storage
            .update {
                $0.snapshot = result.snapshot; $0.selectedChildID = result.snapshot.entities
                    .first { $0.type == "child" }?
                    .id ?? ""
            }; reload()
    }

    func setPreference(_ key: String, _ value: String) {
        UserDefaults.standard.set(value, forKey: key)
    }

    var branding: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? "Babytrack"
    }
}

struct FormRequest: Identifiable {
    var id = UUID()
    var type: String
    var entity: Entity?
    var childID: String?
    var template: Entity?
}

enum AppSection: String, CaseIterable, Identifiable {
    case today = "Today", journal = "Journal", library = "Library", growth = "Growth", health = "Health",
         family = "Family",
         settings = "Settings"
    var id: String {
        rawValue
    }

    var symbol: String {
        switch self {
        case .today: "sun.max"; case .journal: "clock"; case .library: "books.vertical"; case .growth: "chart.xyaxis.line"; case .health: "heart"; case .family: "person.2"; case .settings: "gearshape"
        }
    }
}
