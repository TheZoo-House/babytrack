import BabyCore
import PhotosUI
import SwiftUI

struct RecordForm: View {
    var request: FormRequest
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var loaded = false
    @State private var title = ""
    @State private var date = Date.now
    @State private var end = Date.now
    @State private var fields: [String: String] = [:]
    @State private var photo: PhotosPickerItem?
    @State private var scanning = false
    @State private var lookingUp = false
    @State private var lookupNote: String?
    @State private var validation: String?
    @State private var customFormula = false
    private var spec: TypeSpec {
        Catalog.shared.spec(request.type)
    }

    private var tint: Color {
        Palette.tint(spec.color)
    }

    private var inventory: Bool {
        ["book", "toy", "clothing", "location", "formula"].contains(request.type)
    }

    private var needsTitle: Bool {
        !["feeding", "diaper", "sleep", "reading", "growth", "temperature"].contains(request.type)
    }

    private var primaryField: String? {
        switch request.type { case "feeding": "amount"; case "growth", "temperature": "value"; case "reading": "minutes"; default: nil }
    }

    private var titleLabel: String {
        switch request.type { case "child": "Name"; case "medication": "Medication name"; case "vaccine": "Vaccine name"; case "book": "Book title"; default: "Name" }
    }

    private var requiredMissing: Bool {
        (needsTitle && title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) ||
            (request.entity?.imported == nil && spec.fields.contains { $0.required && (fields[$0.key] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
    }

    var body: some View {
        NavigationStack {
            AppList {
                Section {
                    EntryHeading(type: request.type, child: inventory || request.type == "child" ? nil : store.child?.title)
                        .listRowSeparator(.hidden)
                    if needsTitle {
                        TextField(titleLabel, text: $title).font(.title3.weight(.medium)).accessibilityIdentifier("recordTitle")
                    }
                    if let key = primaryField, let field = spec.fields.first(where: { $0.key == key }) {
                        quantity(field).listRowSeparator(.hidden)
                    }
                    ForEach(spec.fields.filter { $0.key != primaryField && $0.key != "notes" && $0.kind != "barcode" }) { field in
                        if request.type != "diaper" || !["color", "consistency", "detail"].contains(field.key) || ["Dirty", "Both"].contains(fields["contents"] ?? "") {
                            control(field)
                        }
                    }
                    ForEach(spec.fields.filter { $0.kind == "barcode" }) { field in control(field) }
                }
                if !inventory {
                    Section(request.type == "child" ? "Birthday" : "When") {
                        DatePicker(request.type == "child" ? "Date" : request.type == "sleep" ? "Started" : "Date & time", selection: $date, displayedComponents: request.type == "child" ? [.date] : [.date, .hourAndMinute])
                        if request.type == "sleep" {
                            DatePicker("Ended", selection: $end, in: date..., displayedComponents: [.date, .hourAndMinute])
                        }
                    }
                }
                if let notes = spec.fields.first(where: { $0.key == "notes" }) {
                    Section("Notes") { control(notes) }
                }
                if !["child", "location", "formula"].contains(request.type) {
                    Section {
                        let photoLabel = fields["photo"] == nil ? "Add photo" : "Replace photo"
                        PhotosPicker(selection: $photo, matching: .images) { Label(photoLabel, systemImage: "photo") }
                        if let raw = fields["photo"], let data = Data(base64Encoded: raw), let image = UIImage(data: data) {
                            Image(uiImage: image).resizable().scaledToFit().frame(maxHeight: 220)
                            Button("Remove photo", role: .destructive) { fields.removeValue(forKey: "photo") }
                        }
                    }
                }
                if let validation {
                    Text(validation).foregroundStyle(.red).accessibilityIdentifier("formError")
                }
                if let lookupNote {
                    Text(lookupNote).font(.subheadline).foregroundStyle(.secondary)
                }
            }.appList().tint(tint).navigationTitle(request.entity == nil ? "Add \(spec.title.lowercased())" : "Edit \(spec.title.lowercased())")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { Button("Save") { save() }.fontWeight(.semibold).disabled(requiredMissing).accessibilityIdentifier("saveRecord") }
                }
                .onAppear(perform: load)
                .onChange(of: date) {
                    _, value in if end < value {
                        end = value
                    }
                }
                .onChange(of: photo) { _, item in Task { await loadPhoto(item) } }
                .sheet(isPresented: $scanning) { BarcodeScanner { code in fields["isbn"] = code; scanning = false; Task { await lookup() } } }
                .sheet(isPresented: $customFormula) { CustomFormulaView { fields["brand"] = $0 } }
        }
    }

    private func binding(_ field: FieldSpec) -> Binding<String> {
        Binding(get: { fields[field.key] ?? "" }, set: { value in
            fields[field.key] = value
            if request.type == "growth", field.key == "measure" {
                fields["unit"] = value == "Weight" ? (store.unitSystem == "imperial" ? "lb" : "kg") : (store.unitSystem == "imperial" ? "in" : "cm")
            }
        })
    }

    private func quantity(_ field: FieldSpec) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(field.label).font(.subheadline).foregroundStyle(tint)
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                TextField("0", text: binding(field)).keyboardType(.decimalPad).font(.system(.largeTitle, design: .rounded, weight: .medium)).monospacedDigit().accessibilityLabel(field.label).accessibilityIdentifier(field.key)
                if spec.fields.contains(where: { $0.key == "unit" }) {
                    Text(fields["unit"] ?? "").font(.title3).foregroundStyle(.secondary)
                } else if field.key == "minutes" {
                    Text("min").foregroundStyle(.secondary)
                }
            }
        }.padding(.vertical, 14)
    }

    @ViewBuilder private func control(_ field: FieldSpec) -> some View {
        switch field.kind {
        case "formula":
            Menu {
                Button("Not recorded") { fields[field.key] = "" }
                ForEach(store.state.formulaOptions, id: \.self) { brand in Button(brand) { fields[field.key] = brand } }
                Divider(); Button("Custom…", systemImage: "plus") { customFormula = true }
            } label: { LabeledContent(field.label, value: fields[field.key]?.isEmpty == false ? fields[field.key]! : "Not recorded") }
                .accessibilityIdentifier("formulaPicker").accessibilityValue(fields[field.key]?.isEmpty == false ? fields[field.key]! : "Not recorded")
        case "choice":
            if request.type == "diaper" && ["color", "consistency"].contains(field.key) {
                Menu {
                    Button("Not recorded") { fields[field.key] = "" }
                    ForEach(multiOptions(field), id: \.self) { option in
                        Toggle(option, isOn: Binding(get: { (fields[field.key] ?? "").split(separator: " ").map(String.init).contains(option) }, set: { selected in
                            var values = (fields[field.key] ?? "").split(separator: " ").map(String.init)
                            values.removeAll { $0 == option }; if selected {
                                values.append(option)
                            }; fields[field.key] = values.joined(separator: " ")
                        }))
                    }
                } label: { LabeledContent(field.label, value: fields[field.key]?.isEmpty == false ? fields[field.key]! : "Not recorded") }
                    .accessibilityIdentifier(field.key).accessibilityValue(fields[field.key] ?? "Not recorded")
            } else {
                Picker(field.label, selection: binding(field)) {
                    if !field.required || request.entity?.imported != nil {
                        Text("Not recorded").tag("")
                    }
                    ForEach(options(field), id: \.self) { Text($0).tag($0) }
                }.accessibilityIdentifier(field.key)
            }
        case "toggle": Toggle(field.label, isOn: Binding(get: { fields[field.key] == "true" }, set: { fields[field.key] = String($0) }))
        case "number": HStack { Text(field.label); Spacer(); TextField(field.label, text: binding(field)).keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(maxWidth: 140).accessibilityIdentifier(field.key) }
        case "multiline": TextField("Add notes", text: binding(field), axis: .vertical).lineLimit(3 ... 8).accessibilityIdentifier(field.key)
        case "location", "book": Picker(field.label, selection: binding(field)) {
                Text(field.required ? "Choose" : "None").tag("")
                ForEach(store.entities.filter { $0.type == (field.kind == "book" ? "book" : "location") && $0.id != request.entity?.id }) { Text($0.title).tag($0.id) }
            }
        case "barcode":
            TextField(field.label, text: binding(field)).keyboardType(.numberPad).accessibilityIdentifier("isbn")
            HStack {
                Button { scanning = true } label: { Label("Scan", systemImage: "barcode.viewfinder") }; Spacer()
                if lookingUp {
                    ProgressView()
                } else {
                    Button("Look up ISBN") { Task { await lookup() } }.disabled((fields["isbn"] ?? "").isEmpty)
                }
            }
        default: TextField(field.label, text: binding(field)).accessibilityIdentifier(field.key)
        }
    }

    private func multiOptions(_ field: FieldSpec) -> [String] {
        let tokens = (fields[field.key] ?? "").split(separator: " ").map(String.init)
        return field.options + tokens.filter { !field.options.contains($0) }
    }

    private func options(_ field: FieldSpec) -> [String] {
        if request.type == "growth", field.key == "unit" {
            return fields["measure"] == "Weight" ? ["lb", "oz", "kg"] : ["in", "cm"]
        }
        let current = fields[field.key] ?? ""
        return request.entity?.imported != nil && !current.isEmpty && !field.options.contains(current) ? field.options + [current] : field.options
    }

    private func load() {
        guard !loaded else { return }; loaded = true
        if let entity = request.entity {
            title = entity.title; date = entity.date; end = Date(timeIntervalSince1970: entity.end ?? entity.at + 3600); fields = entity.fields
        } else {
            for field in spec.fields where field.kind == "choice" {
                fields[field.key] = field.required ? field.options.first : ""
            }
            if request.type == "feeding" {
                fields["unit"] = store.unitSystem == "imperial" ? "oz" : "mL"; fields["amount"] = store.unitSystem == "imperial" ? "4" : "120"; fields["brand"] = store.state.preferredFormula(for: store.childID) ?? ""
            }
            if request.type == "growth" {
                fields["unit"] = store.unitSystem == "imperial" ? "lb" : "kg"
            }
            if request.type == "temperature" {
                fields["unit"] = store.unitSystem == "imperial" ? "°F" : "°C"
            }
            if ["book", "toy", "clothing"].contains(request.type) {
                fields["status"] = "Owned"; fields["quantity"] = "1"
            }
            if ["reminder", "appointment"].contains(request.type) {
                date = .now.addingTimeInterval(3600)
            }
            end = date.addingTimeInterval(3600)
        }
    }

    private func save() {
        validation = nil
        for field in spec.fields where field.kind == "number" {
            if let value = fields[field.key], !value.isEmpty, Double(value) == nil || (Double(value) ?? 0) < 0 || (Double(value) ?? 0) > 100_000 {
                validation = "Enter a valid \(field.label.lowercased())."; return
            }
        }
        if request.type == "feeding", let amount = fields["amount"], !amount.isEmpty, (Double(amount) ?? 0) <= 0 {
            validation = "Amount must be greater than zero."; return
        }
        var entity = request.entity ?? Entity(type: request.type, childID: inventory || request.type == "child" ? "" : store.childID, title: spec.title)
        entity.title = needsTitle ? title.trimmingCharacters(in: .whitespacesAndNewlines) : spec.title
        entity.at = date.timeIntervalSince1970; entity.fields = fields
        if request.type == "sleep" {
            entity.end = end.timeIntervalSince1970
        }
        if store.save(entity) {
            dismiss()
        }
    }

    private func loadPhoto(_ item: PhotosPickerItem?) async {
        guard let data = try? await item?.loadTransferable(type: Data.self), let image = UIImage(data: data) else { return }
        let ratio = min(1, 1000 / max(image.size.width, image.size.height))
        let size = CGSize(width: image.size.width * ratio, height: image.size.height * ratio)
        fields["photo"] = UIGraphicsImageRenderer(size: size).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }.jpegData(compressionQuality: 0.65)?.base64EncodedString()
    }

    private func lookup() async {
        lookingUp = true; defer { lookingUp = false }
        do {
            struct Book: Decodable { var title: String; var author: String; var isbn: String; var imageURL: String }
            let isbn = (fields["isbn"] ?? "").addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
            let result: Book = try await store.request("/v1/books/lookup?isbn=\(isbn)")
            title = result.title; fields["author"] = result.author; fields["isbn"] = result.isbn; fields["imageURL"] = result.imageURL; lookupNote = nil
        } catch { lookupNote = error is APIError ? error.localizedDescription : "Book lookup unavailable. Enter the title and author manually." }
    }
}

struct CustomFormulaView: View {
    var selected: (String) -> Void
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    var body: some View {
        NavigationStack {
            AppList { Section("Formula name") { TextField("Name", text: $name).textInputAutocapitalization(.words).accessibilityIdentifier("customFormulaName") } }.appList()
                .navigationTitle("Custom formula").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { Button("Add") {
                        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
                        if let existing = store.state.formulaOptions.first(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame }) {
                            selected(existing); dismiss()
                        } else if store.save(Entity(type: "formula", title: trimmed)) {
                            selected(trimmed); dismiss()
                        }
                    }.disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || name.count > 80).accessibilityIdentifier("addCustomFormula") }
                }
        }
    }
}
