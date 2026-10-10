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

    @Environment(\.dynamicTypeSize) private var dynamicType
    private static let compactDetent = PresentationDetent.height(420)
    private static let timeDetent = PresentationDetent.height(660)
    @State private var detent = RecordForm.compactDetent
    @State private var dateTarget: String?

    var body: some View {
        VStack(spacing: 0) {
            LogSheetHeader(title: request.entity == nil ? spec.title : "Edit " + spec.title.lowercased(), color: spec.color,
                           actionTitle: "Save", actionEnabled: !requiredMissing, close: { dismiss() }, action: save)
            ScrollView {
                VStack(spacing: 0) {
                    if !inventory {
                        timeRow(request.type == "child" ? "Birthday" : "Start time", target: "start", value: date)
                        if request.type == "sleep" {
                            timeRow("End time", target: "end", value: end)
                        }
                    }
                    if needsTitle {
                        EntryRow(title: titleLabel) { TextField("Required", text: $title).multilineTextAlignment(.trailing).accessibilityLabel(titleLabel).accessibilityIdentifier("recordTitle") }
                        Divider()
                    }
                    ForEach(entryFields) { field in
                        if request.type != "diaper" || !["color", "consistency", "detail"].contains(field.key) || ["Dirty", "Both"].contains(fields["contents"] ?? "") {
                            control(field)
                            Divider()
                        }
                    }
                    if let notes = spec.fields.first(where: { $0.key == "notes" }) {
                        EntryRow(title: "Notes") { TextField("Add", text: binding(notes), axis: .vertical).lineLimit(1 ... 4).multilineTextAlignment(.trailing).accessibilityLabel("Notes").accessibilityIdentifier("notes") }
                        Divider()
                    }
                    if !["child", "location", "formula"].contains(request.type) {
                        let photoLabel = fields["photo"] == nil ? "Add photo" : "Replace photo"
                        HStack {
                            Spacer()
                            PhotosPicker(selection: $photo, matching: .images) { Label(photoLabel, systemImage: "photo") }
                                .buttonStyle(CareActionStyle(color: spec.color))
                        }.padding(.horizontal, 20).padding(.vertical, 12)
                        if let raw = fields["photo"], let data = Data(base64Encoded: raw), let image = UIImage(data: data) {
                            Image(uiImage: image).resizable().scaledToFit().frame(maxHeight: 180)
                            HStack { Spacer(); Button("Remove photo", role: .destructive) { fields.removeValue(forKey: "photo") } }.padding(20)
                        }
                    }
                    if let validation {
                        Text(validation).foregroundStyle(.red).padding(20).accessibilityIdentifier("formError")
                    }
                    if let lookupNote {
                        Text(lookupNote).font(.subheadline).foregroundStyle(.secondary).padding(20)
                    }
                }.padding(.bottom, 12)
            }.scrollDismissesKeyboard(.interactively)
        }.background(Palette.paper).tint(tint).foregroundStyle(Palette.ink)
            .presentationDetents([Self.compactDetent, Self.timeDetent, .large], selection: $detent)
            .presentationSizing(.page).presentationDragIndicator(.visible).presentationCornerRadius(24).presentationBackground(Palette.paper)
            .onAppear {
                load(); if dynamicType.isAccessibilitySize {
                    detent = .large
                }
            }
            .onChange(of: date) {
                _, value in if end < value {
                    end = value
                }
            }
            .onChange(of: photo) { _, item in Task { await loadPhoto(item) } }
            .sheet(isPresented: $scanning) { BarcodeScanner { code in fields["isbn"] = code; scanning = false; Task { await lookup() } } }
            .sheet(isPresented: $customFormula) { CustomFormulaView { fields["brand"] = $0 } }
    }

    private func timeRow(_ label: String, target: String, value: Date) -> some View {
        VStack(spacing: 0) {
            EntryRow(title: label) {
                Button {
                    withAnimation {
                        dateTarget = dateTarget == target ? nil : target
                        detent = dynamicType.isAccessibilitySize ? .large : dateTarget == nil ? Self.compactDetent : Self.timeDetent
                    }
                } label: {
                    if dateTarget == target {
                        Text("Done").fontWeight(.semibold)
                    } else {
                        HStack(spacing: 6) {
                            Text(value, format: request.type == "child" ? .dateTime.month().day().year() : .dateTime.month().day().hour().minute())
                            Image(systemName: "chevron.right").font(.caption)
                        }
                    }
                }.buttonStyle(.plain).accessibilityIdentifier("\(target)Time")
                    .accessibilityLabel(dateTarget == target ? "Done editing " + label.lowercased() : label)
                    .accessibilityValue(value.formatted(request.type == "child" ? .dateTime.month().day().year() : .dateTime.month().day().hour().minute()))
            }
            if dateTarget == target {
                CombinedDatePicker(date: target == "start" ? $date : $end, dateOnly: request.type == "child", minimumDate: target == "end" ? date : nil)
                    .frame(height: 216).padding(.horizontal, 12)
            }
            Divider()
        }
    }

    private var entryFields: [FieldSpec] {
        let fields = spec.fields.filter { $0.key != "notes" && ($0.key != "unit" || primaryField == nil) }
        if request.type == "feeding" {
            return fields.sorted { ($0.key == "brand" ? 0 : 1) < ($1.key == "brand" ? 0 : 1) }
        }
        return fields
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
        EntryRow(title: field.label) {
            HStack(spacing: 8) {
                TextField("0", text: binding(field)).keyboardType(.decimalPad)
                    .font(.title3.weight(.medium)).monospacedDigit().multilineTextAlignment(.trailing)
                    .frame(width: 80).accessibilityLabel(field.label).accessibilityIdentifier(field.key)
                if let unit = spec.fields.first(where: { $0.key == "unit" }) {
                    Picker("Unit", selection: binding(unit)) {
                        ForEach(options(unit), id: \.self) { Text($0).tag($0) }
                    }.labelsHidden().pickerStyle(.menu).accessibilityIdentifier("unit")
                } else if field.key == "minutes" {
                    Text("min").foregroundStyle(.secondary)
                }
            }.fixedSize(horizontal: true, vertical: false)
        }
    }

    @ViewBuilder private func control(_ field: FieldSpec) -> some View {
        switch field.kind {
        case "formula":
            EntryRow(title: field.label) {
                Menu {
                    Button("Not recorded") { fields[field.key] = "" }
                    ForEach(store.state.formulaOptions, id: \.self) { brand in Button(brand) { fields[field.key] = brand } }
                    Divider(); Button("Custom…", systemImage: "plus") { customFormula = true }
                } label: { choiceLabel(fields[field.key]) }
                    .accessibilityLabel(field.label).accessibilityIdentifier("formulaPicker").accessibilityValue(fields[field.key] ?? "Not recorded")
            }
        case "choice":
            EntryRow(title: field.label) {
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
                    } label: { choiceLabel(fields[field.key]) }
                        .accessibilityLabel(field.label).accessibilityIdentifier(field.key).accessibilityValue(fields[field.key] ?? "Not recorded")
                } else {
                    Picker(field.label, selection: binding(field)) {
                        if !field.required || request.entity?.imported != nil {
                            Text("Not recorded").tag("")
                        }
                        ForEach(options(field), id: \.self) { Text($0).tag($0) }
                    }.labelsHidden().pickerStyle(.menu).accessibilityIdentifier(field.key)
                }
            }
        case "toggle":
            EntryRow(title: field.label) { Toggle(field.label, isOn: Binding(get: { fields[field.key] == "true" }, set: { fields[field.key] = String($0) })).labelsHidden().fixedSize() }
        case "number":
            if field.key == primaryField {
                quantity(field)
            } else {
                EntryRow(title: field.label) { TextField("Add", text: binding(field)).keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(maxWidth: 140).accessibilityLabel(field.label).accessibilityIdentifier(field.key) }
            }
        case "location", "book":
            EntryRow(title: field.label) {
                Picker(field.label, selection: binding(field)) {
                    Text(field.required ? "Choose" : "None").tag("")
                    ForEach(store.entities.filter { $0.type == (field.kind == "book" ? "book" : "location") && $0.id != request.entity?.id }) { Text($0.title).tag($0.id) }
                }.labelsHidden().pickerStyle(.menu)
            }
        case "barcode":
            EntryRow(title: field.label) { TextField("Add", text: binding(field)).keyboardType(.numberPad).multilineTextAlignment(.trailing).accessibilityLabel(field.label).accessibilityIdentifier("isbn") }
            HStack {
                Spacer()
                Button("Scan", systemImage: "barcode.viewfinder") { scanning = true }
                Button(lookingUp ? "Looking up…" : "Look up") { Task { await lookup() } }.disabled((fields["isbn"] ?? "").isEmpty || lookingUp)
            }.buttonStyle(CareActionStyle(color: spec.color)).padding(.horizontal, 20).padding(.bottom, 8)
        default:
            EntryRow(title: field.label) { TextField("Add", text: binding(field), axis: field.kind == "multiline" ? .vertical : .horizontal).multilineTextAlignment(.trailing).accessibilityLabel(field.label).accessibilityIdentifier(field.key) }
        }
    }

    private func choiceLabel(_ value: String?) -> some View {
        HStack(spacing: 6) {
            Text(value?.isEmpty == false ? value! : "Not recorded").multilineTextAlignment(.trailing)
            Image(systemName: "chevron.right").font(.caption)
        }.foregroundStyle(Palette.ink)
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
        VStack(spacing: 0) {
            LogSheetHeader(title: "Custom formula", color: "amber", actionTitle: "Add",
                           actionEnabled: !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && name.count <= 80,
                           actionID: "addCustomFormula", close: { dismiss() }, action: add)
            EntryRow(title: "Name") { TextField("Required", text: $name).textInputAutocapitalization(.words).multilineTextAlignment(.trailing).accessibilityLabel("Formula name").accessibilityIdentifier("customFormulaName") }
            Spacer(minLength: 0)
        }.background(Palette.paper).presentationDetents([.height(230), .large]).presentationDragIndicator(.visible)
    }

    private func add() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if let existing = store.state.formulaOptions.first(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame }) {
            selected(existing); dismiss()
        } else if store.save(Entity(type: "formula", title: trimmed)) {
            selected(trimmed); dismiss()
        }
    }
}
