import BabyCore
import CryptoKit
import Foundation
import Security
import SwiftUI
import WidgetKit

struct APIError: LocalizedError {
    var message: String
    var status: Int?
    var errorDescription: String? {
        message
    }
}

enum SessionKeychain {
    private static let service = "house.thezoo.babytrack.session"
    static func read() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnData as String: true,
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func write(_ token: String?) throws {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service]
        SecItemDelete(query as CFDictionary)
        guard let token else { return }
        var item = query
        item[kSecValueData as String] = Data(token.utf8)
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess
        else { throw APIError(message: "Could not securely save your session.") }
    }
}

@MainActor @Observable final class AppStore {
    var state = DiskState()
    var error: String?
    var notice: String?
    var syncing = false
    var showWelcome = true
    var reauthenticationRequired = false
    var nonce: String?
    var selectedSection: AppSection = .today
    var form: FormRequest?
    var detail: Entity?
    var notificationsEnabled = UserDefaults.standard.bool(forKey: "notificationsEnabled")
    var unitSystem = UserDefaults.standard.string(forKey: "units") ?? "imperial"
    var appearance = UserDefaults.standard.string(forKey: "appearance") ?? "system"
    var backendURL: String {
        didSet { UserDefaults.standard.set(backendURL, forKey: "backendURL") }
    }

    let storage: SharedStorage
    let testing: Bool
    private var token: String?
    var entities: [Entity] {
        state.visibleEntities
    }

    var children: [Entity] {
        entities.filter { $0.type == "child" }
    }

    var child: Entity? {
        let profiles = children
        return profiles.first { $0.id == state.selectedChildID } ?? profiles.first
    }

    var childID: String {
        child?.id ?? ""
    }

    var activeSleep: Entity? {
        let selectedChildID = childID
        return entities.first { $0.type == "sleep" && $0.childID == selectedChildID && $0.end == nil }
    }

    func summary(at date: Date) -> DaySummary? { state.careSummary(for: childID, now: date) }

    var signedIn: Bool {
        token != nil
    }

    var isPreview: Bool {
        state.localPreview || state.snapshot.user.preview
    }

    var pendingCount: Int {
        state.outbox.count + (state.caregiverPhotoDraft == nil ? 0 : 1)
    }

    var care: [Entity] {
        // Resolve the child once; doing it inside the filter scans all records for every row.
        let selectedChildID = childID
        return entities.filter { $0.childID == selectedChildID && !["child", "reminder"].contains($0.type) && $0.scheduled != true }
            .sorted { $0.at > $1.at }
    }

    init() {
        #if DEBUG
            testing = ProcessInfo.processInfo.arguments.contains("--ui-testing") || ProcessInfo.processInfo.arguments
                .contains("--ui-http-test") || ProcessInfo.processInfo.arguments.contains("--owner-preview-testing")
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
            unitSystem = "imperial"; notificationsEnabled = false
        }
        #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--ui-http-test") {
                backendURL = "http://127.0.0.1:18792"
            }
        #endif
        do { state = try storage.read() } catch { self.error = error.localizedDescription }
        #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--ui-testing") {
                // UI tests explicitly opt into synthetic state and never use personal sessions.
                token = nil
                do {
                    var fresh = DiskState(); fresh.snapshot = try Snapshot.sample()
                    if ProcessInfo.processInfo.arguments.contains("--history-stress-testing") {
                        let templates = fresh.snapshot.entities.filter { ["feeding", "diaper", "sleep"].contains($0.type) }
                        for index in 0 ..< 1700 {
                            var record = templates[index % templates.count]
                            record.id = "stress-\(index)"
                            let offset = Double(index * 3600); record.at -= offset
                            if let end = record.end { record.end = end - offset }
                            fresh.snapshot.entities.append(record)
                        }
                    }
                    fresh.localPreview = true; fresh
                        .selectedChildID = fresh.snapshot.entities.first { $0.type == "child" }?
                        .id ?? ""; state = fresh; try storage.update { $0 = fresh }
                } catch { self.error = error.localizedDescription }
            }
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
            let args = ProcessInfo.processInfo.arguments
            if args.contains("--owner-preview-testing"), let index = args.firstIndex(of: "--owner-form"), args.indices.contains(index + 1), Catalog.shared.types.contains(where: { $0.id == args[index + 1] }) {
                let type = args[index + 1]
                let existing = args.contains("--owner-form-existing") ? entities.first { $0.type == type && (type != "diaper" || $0.fields["contents"] == "Both") } : nil
                form = FormRequest(type: type, entity: existing)
            }
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
        guard let base = URL(string: backendURL), ["http", "https"].contains(base.scheme), base.host != nil,
              let url = URL(string: backendURL.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + path)
        else { throw APIError(message: "Enter a valid server URL in Connection settings.") }
        var req = URLRequest(url: url); req.timeoutInterval = 15
        if let body {
            req.httpMethod = "POST"; req.httpBody = body; req.setValue(
                "application/json",
                forHTTPHeaderField: "Content-Type"
            )
        }
        if authenticated, let token {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, (200 ..< 300).contains(http.statusCode) else {
            let value = try? JSONDecoder().decode([String: String].self, from: data)
            let status = (response as? HTTPURLResponse)?.statusCode
            if authenticated, status == 401 {
                reauthenticationRequired = true
            }
            throw APIError(
                message: value?["error"] ?? "Server unavailable. Your offline records are saved.",
                status: status
            )
        }
        return try JSONDecoder().decode(T.self, from: data)
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
                try storage.update { $0.snapshot = snap }
            } else {
                struct Payload: Encodable { var commands: [Command]; var timeZone: String }
                let response: SyncResponse = try await request(
                    "/v1/sync",
                    body: JSONEncoder().encode(Payload(commands: commands, timeZone: TimeZone.current.identifier))
                )
                let messages = try storage.update { $0.merge(response) }
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
        guard var sleep = entities.first(where: { $0.id == sessionID && $0.type == "sleep" }),
              sleep.end == nil else { return }
        sleep.end = Date.now.timeIntervalSince1970
        save(sleep, action: "sleepStop")
        await SleepCoordinator.shared.reconcile(store: self)
    }

    func quickDiaper() {
        do { try storage.record(.diaper("Wet"), childID: childID); reload(); Task { await sync() } } catch { self.error = error.localizedDescription }
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
