import BabyCore
import PhotosUI
import SwiftUI

struct RecordForm: View {
    var request: FormRequest
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var date = Date.now
    @State private var end = Date.now
    @State private var fields: [String: String] = [:]
    @State private var photo: PhotosPickerItem?
    @State private var scanning = false
    @State private var lookingUp = false
    @State private var lookupNote: String?
    private var spec: TypeSpec {
        Catalog.shared.spec(request.type)
    }

    private var needsTitle: Bool {
        [
            "book",
            "toy",
            "clothing",
            "location",
            "child",
            "medication",
            "vaccine",
            "illness",
            "milestone",
            "appointment",
            "note",
            "reminder",
        ].contains(request.type)
    }

    private var requiredMissing: Bool {
        (needsTitle && title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) || spec.fields
            .contains { $0.required && (fields[$0.key] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if needsTitle {
                        TextField(request.type == "child" ? "Name" : "Title", text: $title)
                            .accessibilityIdentifier("recordTitle")
                    }
                    if !["book", "toy", "clothing", "location"].contains(request.type) {
                        DatePicker(
                            request.type == "child" ? "Birthday" : request.type == "sleep" ? "Started" : "Date",
                            selection: $date,
                            displayedComponents: request.type == "child" ? [.date] : [.date, .hourAndMinute]
                        )
                    }
                    if request.type == "sleep" {
                        DatePicker(
                            "Ended",
                            selection: $end,
                            in: date...,
                            displayedComponents: [.date, .hourAndMinute]
                        )
                    }
                }
                Section {
                    ForEach(spec.fields) { field in control(field) }
                }
                if request.type != "child", request.type != "location" {
                    Section {
                        let photoLabel = fields["photo"] == nil ? "Add photo" : "Replace photo"
                        PhotosPicker(selection: $photo, matching: .images) { Label(photoLabel, systemImage: "photo") }
                        if let raw = fields["photo"], let data = Data(base64Encoded: raw),
                           let image = UIImage(data: data)
                        {
                            Image(uiImage: image).resizable().scaledToFit().frame(maxHeight: 220)
                            Button("Remove photo", role: .destructive) { fields.removeValue(forKey: "photo") }
                        }
                    }
                }
                if let lookupNote {
                    Section { Text(lookupNote).font(.subheadline).foregroundStyle(.secondary) }
                }
            }
            .navigationTitle(request
                .entity == nil ? "Add \(spec.title.lowercased())" : "Edit \(spec.title.lowercased())")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.fontWeight(.semibold).disabled(requiredMissing)
                        .accessibilityIdentifier("saveRecord")
                }
            }
            .onAppear(perform: load)
            .onChange(of: photo) { _, item in
                Task {
                    if let data = try? await item?.loadTransferable(type: Data.self),
                       let image = UIImage(data: data)
                    {
                        let ratio = min(1, 1000 / max(image.size.width, image.size.height))
                        let size = CGSize(width: image.size.width * ratio, height: image.size.height * ratio)
                        let jpeg = UIGraphicsImageRenderer(size: size).image { _ in image.draw(in: CGRect(
                            origin: .zero,
                            size: size
                        )) }.jpegData(compressionQuality: 0.65)
                        fields["photo"] = jpeg?.base64EncodedString()
                    }
                }
            }
            .sheet(isPresented: $scanning) { BarcodeScanner { code in
                fields["isbn"] = code; scanning = false; Task { await lookup() }
            } }
        }
    }

    @ViewBuilder private func control(_ field: FieldSpec) -> some View {
        let binding = Binding<String>(get: { fields[field.key] ?? "" }, set: { value in
            fields[field.key] = value
            if request.type == "growth",
               field
               .key ==
               "measure"
            {
                fields["unit"] = value == "Weight" ? (store.unitSystem == "imperial" ? "lb" : "kg") :
                    (store.unitSystem == "imperial" ? "in" : "cm")
            }
        })
        switch field.kind {
        case "choice":
            Picker(field.label, selection: binding) {
                if !field.required {
                    Text("Not recorded").tag("")
                }
                ForEach(options(field), id: \.self) { Text($0).tag($0) }
            }.accessibilityIdentifier(field.key)
        case "toggle": Toggle(
                field.label,
                isOn: Binding(get: { fields[field.key] == "true" }, set: { fields[field.key] = String($0) })
            )
        case "number": HStack {
                Text(field.label); Spacer(); TextField(field.label, text: binding).keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing).frame(maxWidth: 150).accessibilityIdentifier(field.key)
            }
        case "multiline": TextField(field.label, text: binding, axis: .vertical).lineLimit(3 ... 7)
            .accessibilityIdentifier(field.key)
        case "location", "book":
            let items = store.entities
                .filter { $0.type == (field.kind == "book" ? "book" : "location") && $0.id != request.entity?.id }
            Picker(field.label, selection: binding) {
                Text(field.required ? "Choose" : "None").tag(""); ForEach(items) { Text($0.title).tag($0.id) }
            }
        case "barcode":
            TextField(field.label, text: binding).keyboardType(.numberPad).accessibilityIdentifier("isbn")
            HStack {
                Button { scanning = true } label: { Label("Scan barcode", systemImage: "barcode.viewfinder") }
                Spacer()
                if lookingUp {
                    ProgressView()
                } else {
                    Button("Look up") { Task { await lookup() } }.disabled((fields["isbn"] ?? "").isEmpty)
                }
            }
        default: TextField(field.label, text: binding).accessibilityIdentifier(field.key)
        }
    }

    private func options(_ field: FieldSpec) -> [String] {
        if request.type == "growth", field.key == "unit" {
            return fields["measure"] == "Weight" ? ["lb", "oz", "kg"] : [
                "in",
                "cm",
            ]
        }
        return field.options
    }

    private func load() {
        if let entity = request
            .entity
        {
            title = entity.title; date = entity
                .date; end = Date(timeIntervalSince1970: entity.end ?? entity.at + 3600); fields = entity.fields
        } else {
            for field in spec.fields
                where field.kind == "choice"
            {
                fields[field.key] = field.required ? field.options.first : ""
            }
            if request
                .type ==
                "feeding"
            {
                fields["unit"] = store.unitSystem == "imperial" ? "oz" : "mL"; fields["amount"] = store
                    .unitSystem == "imperial" ? "4" : "120"
            }
            if request.type == "growth" {
                fields["unit"] = store.unitSystem == "imperial" ? "lb" : "kg"
            }
            if request.type == "temperature" {
                fields["unit"] = store.unitSystem == "imperial" ? "°F" : "°C"
            }
            if ["book", "toy", "clothing"]
                .contains(request.type)
            {
                fields["status"] = "Owned"; fields["quantity"] = "1"
            }
            if ["reminder", "appointment"].contains(request.type) {
                date = .now.addingTimeInterval(3600)
            }
            end = date.addingTimeInterval(3600)
        }
    }

    private func save() {
        var entity = request.entity ?? Entity(
            type: request.type,
            childID: ["child", "location", "book", "toy", "clothing"].contains(request.type) ? "" : store.childID,
            title: spec.title
        )
        entity.title = needsTitle ? title.trimmingCharacters(in: .whitespacesAndNewlines) : spec.title
        entity.at = date.timeIntervalSince1970; entity.fields = fields
        if request.type == "sleep" {
            entity.end = end.timeIntervalSince1970
        }
        if request.type == "growth" {
            let allowed = fields["measure"] == "Weight" ? ["lb", "oz", "kg"] : [
                "in",
                "cm",
            ]; if !allowed.contains(fields["unit"] ?? "") {
                store.error = "Choose a matching measurement unit."; return
            }
        }
        for field in spec.fields
            where field
            .kind ==
            "number"
        {
            if let value = fields[field.key], !value.isEmpty,
               Double(value) == nil || (Double(value) ?? 0) <
               0
            {
                store.error = "Enter a valid \(field.label.lowercased())."; return
            }
        }
        store.save(entity); dismiss()
    }

    private func lookup() async {
        lookingUp = true; defer { lookingUp = false }
        do {
            struct Book: Decodable { var title: String; var author: String; var isbn: String; var imageURL: String }
            let isbn = (fields["isbn"] ?? "").addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
            let result: Book = try await store.request("/v1/books/lookup?isbn=\(isbn)")
            title = result.title; fields["author"] = result.author; fields["isbn"] = result
                .isbn; fields["imageURL"] = result.imageURL; lookupNote = nil
        } catch {
            lookupNote = error is APIError ? error
                .localizedDescription : "Book lookup unavailable. Enter the title and author manually."
        }
    }
}
