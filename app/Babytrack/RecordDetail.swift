import BabyCore
import SwiftUI

struct RecordDetail: View {
    var entity: Entity
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var originalSource: ImportSource?
    @State private var sourceExpanded = false
    @State private var loadingSource = false
    private var current: Entity {
        store.entities.first { $0.id == entity.id } ?? entity
    }

    var body: some View {
        VStack(spacing: 0) {
            LogSheetHeader(title: Catalog.shared.spec(current.type).title, color: Catalog.shared.spec(current.type).color,
                           closeLabel: "Close", actionTitle: "Edit", actionEnabled: !store.state.outbox.contains { $0.entity.id == current.id }, actionID: "editRecord", close: { dismiss() }) {
                store.formAfterDetail(FormRequest(type: current.type, entity: current))
            }
            AppList {
                Section {
                    if current.type == "book" {
                        HStack { Spacer(); BookCover(entity: current).frame(
                            width: 140,
                            height: 190
                        ); Spacer() }.listRowBackground(Color.clear)
                    }
                    if let child = store.children.first(where: { $0.id == current.childID }) {
                        Text(child.title).font(.subheadline).foregroundStyle(Palette.secondary).listRowSeparator(.hidden)
                    }
                    if current.title != Catalog.shared.spec(current.type).title {
                        Text(current.title).font(.system(.title2, design: .rounded, weight: .semibold)).listRowSeparator(.hidden)
                    }
                    if !Catalog.shared.spec(current.type).isInventory {
                        LabeledContent(
                            current.type == "child" ? "Birthday" : "Date",
                            value: current.type == "child" && current.at == 0 && current.imported != nil ? "Not recorded" : current.date.formatted(
                                date: .abbreviated,
                                time: current.type == "child" ? .omitted : .shortened
                            )
                        )
                    }
                    if let end = current.end {
                        LabeledContent(
                            "Ended",
                            value: Date(timeIntervalSince1970: end).formatted(date: .abbreviated, time: .shortened)
                        )
                    }
                    if !current.actor.isEmpty {
                        LabeledContent("Recorded by", value: current.actor)
                    }
                }
                Section {
                    ForEach(Catalog.shared.spec(current.type).fields) { field in
                        let value = current.type == "diaper" && field.key == "blowout" && DiaperFields.hasBlowout(current.fields) ? "true" : current.fields[field.key]
                        let legacyBlowout = current.type == "diaper" && field.key == "detail" && value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "blowout"
                        if let value, !value.isEmpty, !legacyBlowout, field.key != "done" || value == "true" {
                            LabeledContent(field.label) {
                                if ["location", "book"]
                                    .contains(field.kind)
                                {
                                    Text(store.entities.first { $0.id == value }?.title ?? value)
                                } else {
                                    Text(value == "true" ? "Yes" : value == "false" ? "No" : field.displayValue(value))
                                        .multilineTextAlignment(.trailing)
                                }
                            }
                        }
                    }
                    if let raw = current.fields["photo"], let data = Data(base64Encoded: raw),
                       let image = UIImage(data: data)
                    {
                        Image(uiImage: image).resizable().scaledToFit().frame(maxHeight: 360)
                    }
                }
                if let source = originalSource ?? current.imported {
                    Section("Nara Baby") {
                        if !source.timeZone.isEmpty {
                            LabeledContent("Original time zone", value: source.timeZone)
                        }
                        if !source.updatedBy.isEmpty {
                            LabeledContent("Last updated by", value: source.updatedBy)
                        }
                        DisclosureGroup("Original export values", isExpanded: $sourceExpanded) {
                            if loadingSource { ProgressView() }
                            ForEach(source.raw.keys.sorted(), id: \.self) { key in
                                if let value = source.raw[key], !value.isEmpty, !key.hasPrefix("_") {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(key).font(.caption).foregroundStyle(.secondary)
                                        Text(value).font(.subheadline).textSelection(.enabled)
                                    }.padding(.vertical, 4)
                                }
                            }
                        }
                    }
                }
                if current.type == "book" {
                    Section { Button { var form = FormRequest(type: "reading"); form.entity = Entity(
                        type: "reading",
                        childID: store.childID,
                        title: "Reading",
                        fields: ["itemID": current.id]
                    ); store.formAfterDetail(form) } label: {
                        Label(
                            "Log reading",
                            systemImage: "book"
                        )
                    }.disabled(store.childID.isEmpty) }
                }
                if current.type == "medication" {
                    Button("Log again", systemImage: "plus") {
                        store.formAfterDetail(FormRequest(type: "medication", childID: current.childID, template: current))
                    }.accessibilityIdentifier("logMedicationAgain")
                }
                if current.type == "reminder", current.fields["done"] != "true" {
                    HStack {
                        Button("Done", systemImage: "checkmark") { store.reminder(current.id, snooze: false); dismiss() }.accessibilityIdentifier("completeReminder")
                        Spacer()
                        Button("Snooze 15 min", systemImage: "clock") { store.reminder(current.id, snooze: true); dismiss() }.accessibilityIdentifier("snoozeReminder")
                    }
                }
                Section {
                    HStack {
                        Spacer()
                        DestructiveActionButton(title: "Delete record", question: "Delete this record?", message: current.title + " · " + current.date.formatted(date: .abbreviated, time: .shortened), identifier: "deleteRecord", enabled: !store.state.outbox.contains { $0.entity.id == current.id }) {
                            if store.save(current, action: "delete") { dismiss() }
                        }
                        Spacer()
                    }.listRowSeparator(.hidden)
                }
            }.appList()
        }.careSheetStyle()
            .onChange(of: sourceExpanded) { _, expanded in
                guard expanded, originalSource == nil, current.imported?.raw.isEmpty == true, store.signedIn else { return }
                Task {
                    loadingSource = true; defer { loadingSource = false }
                    do { originalSource = try await store.request("/v1/import-source/" + current.id) }
                    catch { store.error = error.localizedDescription }
                }
            }
    }
}
