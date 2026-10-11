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
            AppList {
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
                    AddRecordButton(type: kind)
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
                            design: .rounded
                        )).lineLimit(3)
                    }.foregroundStyle(Palette.tint("rose")).padding(8)
                }
            }.clipShape(RoundedRectangle(cornerRadius: 3))
        }.accessibilityHidden(true)
    }
}
