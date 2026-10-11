import BabyCore
import SwiftUI
import UniformTypeIdentifiers

struct NaraReport: Decodable {
    struct Issue: Decodable, Identifiable {
        var row: Int
        var message: String
        var id: String {
            "\(row)-\(message)"
        }
    }

    struct Profile: Decodable, Identifiable {
        var key: String
        var name: String
        var childID: String
        var id: String {
            key
        }
    }

    var sourceRows: Int
    var counts: [String: Int]
    var duplicates: Int
    var skipped: Int
    var issues: [Issue]
    var profiles: [Profile]
    var snapshot: Snapshot?
    var recordCount: Int {
        counts.values.reduce(0, +)
    }
}

struct NaraImportView: View {
    @Environment(AppStore.self) private var store
    @State private var choosingFile = false
    @State private var csv: String?
    @State private var fileName = ""
    @State private var targetChildID = ""
    @State private var report: NaraReport?
    @State private var previewFamilyID = ""
    @State private var busy = false
    @State private var message: String?
    var body: some View {
        AppList {
            Section {
                Button("Choose Nara CSV", systemImage: "doc.badge.arrow.up") {
                    #if DEBUG
                        if store.testing {
                            do { csv = try String(contentsOf: Bundle.main.url(forResource: "nara-ui-sample", withExtension: "csv")!, encoding: .utf8); fileName = "Synthetic Nara sample.csv"; Task { await preview() } } catch { store.error = error.localizedDescription }
                        } else {
                            choosingFile = true
                        }
                    #else
                        choosingFile = true
                    #endif
                }
                .disabled(busy || !store.signedIn || (store.isPreview && !store.testing) || store.pendingCount > 0)
                .accessibilityIdentifier("chooseNaraCSV")
                if !store.signedIn || (store.isPreview && !store.testing) {
                    Text("Sign in with Apple to import into your family.").foregroundStyle(.secondary)
                } else if store.pendingCount > 0 {
                    Text("Sync pending records before importing.").foregroundStyle(.secondary)
                }
                if !fileName.isEmpty {
                    Text(fileName).font(.subheadline).foregroundStyle(.secondary)
                }
                if csv != nil {
                    Picker("Import into", selection: $targetChildID) {
                        Text("New children from export").tag("")
                        ForEach(store.children) { Text($0.title).tag($0.id) }
                    }.onChange(of: targetChildID) { _, _ in Task { await preview() } }.disabled(busy)
                }
            }
            if let report {
                Section("Preview") {
                    ForEach(report.profiles) { profile in LabeledContent("Profile", value: profile.name) }
                    LabeledContent("Source rows", value: String(report.sourceRows))
                    ForEach(report.counts.keys.sorted(), id: \.self) { type in
                        LabeledContent(Catalog.shared.spec(type).title, value: String(report.counts[type] ?? 0))
                    }
                    LabeledContent("Already imported", value: String(report.duplicates))
                    if report.skipped > 0 {
                        LabeledContent("Skipped", value: String(report.skipped))
                    }
                }
                if !report.issues.isEmpty {
                    Section("Review source values") {
                        ForEach(report.issues) { issue in
                            VStack(alignment: .leading, spacing: 4) {
                                if issue.row > 0 {
                                    Text("Row \(issue.row)").font(.caption).foregroundStyle(.secondary)
                                }
                                Text(issue.message).font(.subheadline)
                            }.padding(.vertical, 4)
                        }
                    }
                }
            }
            if busy {
                ProgressView().frame(maxWidth: .infinity)
            }
            if let message {
                Text(message).foregroundStyle(.secondary).accessibilityIdentifier("importResult")
            }
        }.appList().navigationTitle("Import Nara Baby")
            .safeAreaInset(edge: .bottom) {
                if let report, report.recordCount > 0 {
                    Button("Import \(report.recordCount) records") { Task { await commit() } }
                        .buttonStyle(.borderedProminent).foregroundStyle(Palette.paper).controlSize(.large).frame(maxWidth: .infinity)
                        .disabled(busy).accessibilityIdentifier("commitNaraImport")
                        .padding().background(Palette.paper)
                }
            }
            .fileImporter(isPresented: $choosingFile, allowedContentTypes: [.commaSeparatedText, .plainText]) { result in
                do {
                    let url = try result.get()
                    let access = url.startAccessingSecurityScopedResource()
                    defer {
                        if access {
                            url.stopAccessingSecurityScopedResource()
                        }
                    }
                    let data = try Data(contentsOf: url, options: .mappedIfSafe)
                    guard data.count <= Catalog.shared.limits.csvBytes, let text = String(data: data, encoding: .utf8)
                    else { throw APIError(message: "Choose a UTF-8 CSV smaller than 7 MB.") }
                    csv = text; fileName = url.lastPathComponent; message = nil
                    Task { await preview() }
                } catch { store.error = error.localizedDescription }
            }
    }

    private func payload() throws -> Data {
        let body = try store.body(["csv": csv ?? "", "familyID": previewFamilyID, "targetChildID": targetChildID, "timeZone": TimeZone.current.identifier])
        guard body.count <= Catalog.shared.limits.requestBytes else { throw APIError(message: "This export is too large to upload. Export a smaller date range and import each part.") }
        return body
    }

    private func preview() async {
        guard !busy else { return }
        busy = true; report = nil; previewFamilyID = store.state.snapshot.familyID
        defer { busy = false }
        do { report = try await store.request("/v1/import/nara/preview", body: payload()) }
        catch { store.error = error.localizedDescription }
    }

    private func commit() async {
        busy = true; defer { busy = false }
        do {
            let result: NaraReport = try await store.request("/v1/import/nara/commit", body: payload())
            guard let snapshot = result.snapshot else { throw APIError(message: "Import response did not include saved records.") }
            try store.storage.update { state in
                guard state.snapshot.familyID == snapshot.familyID else { throw APIError(message: "The family changed. Reload before importing again.") }
                state.snapshot = snapshot
                if targetChildID.isEmpty, let child = result.profiles.first {
                    state.selectedChildID = child.childID
                }
            }
            store.reload(); report = nil; csv = nil
            message = "Imported \(result.recordCount) records. \(result.duplicates) already present."
        } catch { store.error = error.localizedDescription }
    }
}
