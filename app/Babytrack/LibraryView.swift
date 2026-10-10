import BabyCore
import SwiftUI

struct LibraryView: View {
    @Environment(AppStore.self) private var store
    @State private var kind = "book"
    @State private var search = ""
    private var records: [Entity] {
        store.entities
            .filter {
                $0
                    .type == kind &&
                    (search.isEmpty || $0.title.localizedCaseInsensitiveContains(search) || $0.detail
                        .localizedCaseInsensitiveContains(search) || ($0.fields["giftGiver"] ?? "")
                        .localizedCaseInsensitiveContains(search))
            }
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("Inventory", selection: $kind) {
                Text("Books").tag("book"); Text("Toys").tag("toy"); Text("Clothes").tag("clothing"); Text("Places")
                    .tag("location")
            }.pickerStyle(.segmented).padding(
                .horizontal,
                20
            ).padding(.vertical, 12)
            List {
                ForEach(records) { entity in
                    Button { store.detail = entity } label: {
                        HStack(alignment: .center, spacing: 18) {
                            if kind == "book" {
                                BookCover(entity: entity).frame(width: 58, height: 82)
                            } else {
                                RecordSymbol(type: kind, size: 46)
                            }
                            VStack(alignment: .leading, spacing: 6) {
                                Text(entity.title).font(.headline).foregroundStyle(Palette.ink)
                                if !entity.detail
                                    .isEmpty
                                {
                                    Text(entity.detail).font(.subheadline).foregroundStyle(.secondary)
                                }
                                if let giver = entity.fields["giftGiver"],
                                   !giver
                                   .isEmpty
                                {
                                    Text("From \(giver)").font(.caption).foregroundStyle(Palette.tint("rose"))
                                }
                            }
                            Spacer(minLength: 8)
                            Image(systemName: "chevron.right").font(.caption.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }.padding(.vertical, 12).contentShape(Rectangle())
                    }.buttonStyle(.plain).listRowBackground(Palette.paper)
                }
            }.listStyle(.plain).scrollContentBackground(.hidden)
                .overlay {
                    if records.isEmpty {
                        ContentUnavailableView { Label(
                            "No \(kind == "book" ? "books" : kind == "toy" ? "toys" : kind == "clothing" ? "clothes" : "locations")",
                            systemImage: Catalog.shared.spec(kind).symbol
                        ) } actions: {
                            Button("Add \(Catalog.shared.spec(kind).title.lowercased())") {
                                store.form = FormRequest(type: kind)
                            }
                        }
                    }
                }
        }.background(Palette.paper).navigationTitle("Library").searchable(text: $search, prompt: "Search your library")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { store.form = FormRequest(type: kind) } label: { Image(systemName: "plus") }
                        .accessibilityLabel("Add \(Catalog.shared.spec(kind).title.lowercased())")
                        .accessibilityIdentifier("addItem")
                }
            }
    }
}

struct BookCover: View {
    var entity: Entity
    var body: some View {
        GeometryReader { geometry in
            AsyncImage(url: URL(string: entity.fields["imageURL"] ?? "")) { image in
                image.resizable().scaledToFit().frame(
                    width: geometry.size.width,
                    height: geometry.size.height
                )
            } placeholder: {
                ZStack(alignment: .bottomLeading) {
                    Palette.tint("rose").opacity(0.16)
                    VStack(alignment: .leading, spacing: 8) {
                        Image(systemName: "book.closed").font(.title3); Text(entity.title).font(.system(
                            size: 10,
                            weight: .semibold,
                            design: .serif
                        )).lineLimit(3)
                    }.foregroundStyle(Palette.tint("rose")).padding(8)
                }
            }.clipShape(RoundedRectangle(cornerRadius: 3))
        }.accessibilityHidden(true)
    }
}

struct RecordDetail: View {
    var entity: Entity
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var confirmDelete = false
    private var current: Entity {
        store.entities.first { $0.id == entity.id } ?? entity
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if current.type == "book" {
                        HStack { Spacer(); BookCover(entity: current).frame(
                            width: 140,
                            height: 190
                        ); Spacer() }.listRowBackground(Color.clear)
                    }
                    Text(current.title).font(.title2.bold())
                    if !current.detail.isEmpty {
                        Text(current.detail).foregroundStyle(.secondary)
                    }
                    if !["book", "toy", "clothing", "location"].contains(current.type) {
                        LabeledContent(
                            current.type == "child" ? "Birthday" : "Date",
                            value: current.date.formatted(
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
                        if let value = current.fields[field.key], !value.isEmpty {
                            LabeledContent(field.label) {
                                if ["location", "book"]
                                    .contains(field.kind)
                                {
                                    Text(store.entities.first { $0.id == value }?.title ?? value)
                                } else {
                                    Text(value == "true" ? "Yes" : value == "false" ? "No" : value)
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
                if current.type == "book" {
                    Section { Button { var form = FormRequest(type: "reading"); form.entity = Entity(
                        type: "reading",
                        childID: store.childID,
                        title: "Reading",
                        fields: ["itemID": current.id]
                    ); dismiss(); Task { try? await Task.sleep(for: .milliseconds(250)); store.form = form } } label: {
                        Label(
                            "Log reading",
                            systemImage: "book"
                        )
                    }.disabled(store.childID.isEmpty) }
                }
                Section {
                    Button("Delete record", role: .destructive) { confirmDelete = true }
                        .disabled(store.state.outbox.contains { $0.entity.id == current.id })
                }
            }.listStyle(.plain).navigationTitle(Catalog.shared.spec(current.type).title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Edit") {
                            dismiss(); Task { try? await Task.sleep(for: .milliseconds(250)); store.form = FormRequest(
                                type: current.type,
                                entity: current
                            ) }
                        }.disabled(store.state.outbox.contains { $0.entity.id == current.id })
                    }
                }
                .confirmationDialog("Delete this record?", isPresented: $confirmDelete, titleVisibility: .visible) {
                    Button(
                        "Delete",
                        role: .destructive
                    ) { store.save(current, action: "delete"); dismiss() }
                }
        }
    }
}
