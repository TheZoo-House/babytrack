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
    @State private var choosingFormula = false
    @FocusState private var focusedField: String?
    @State private var amountWasEdited = false
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
        (request.type == "feeding" && amountWasEdited && (fields["amount"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) ||
        (needsTitle && title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) ||
            (request.entity?.imported == nil && spec.fields.contains { $0.required && (fields[$0.key] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
    }

    @Environment(\.dynamicTypeSize) private var dynamicType
    private static let compactDetent = PresentationDetent.height(460)
    private static let timeDetent = PresentationDetent.height(660)
    @State private var detent = RecordForm.compactDetent
    @State private var dateTarget: String?
    @State private var diaperExpanded = false
    private var baseDetent: PresentationDetent { request.type == "diaper" ? .height(560) : Self.compactDetent }

    var body: some View {
        VStack(spacing: 0) {
            LogSheetHeader(title: spec.title, color: spec.color,
                           actionTitle: "Save", actionEnabled: !requiredMissing, close: { dismiss() }, action: save)
            ScrollView {
                VStack(spacing: 0) {
                    if !inventory {
                        timeRow(request.type == "child" ? "Birthday" : request.type == "diaper" ? "Time" : "Start time", target: "start", value: date)
                        if request.type == "sleep" {
                            timeRow("End time", target: "end", value: end)
                        }
                    }
                    if needsTitle {
                        EntryRow(title: titleLabel) { TextField("Required", text: $title).multilineTextAlignment(.trailing).accessibilityLabel(titleLabel).accessibilityIdentifier("recordTitle") }
                        Divider()
                    }
                    if request.type == "diaper" {
                        DiaperControls(fields: $fields, expanded: $diaperExpanded)
                    } else {
                        ForEach(entryFields) { field in control(field); Divider() }
                    }
                    if let notes = spec.fields.first(where: { $0.key == "notes" }) {
                        EntryRow(title: "Notes") { TextField("Add", text: binding(notes), axis: .vertical).lineLimit(1 ... 4).multilineTextAlignment(.trailing).accessibilityLabel("Notes").accessibilityIdentifier("notes") }
                        Divider()
                    }
                    if !["location", "formula"].contains(request.type) {
                        let photoLabel = fields["photo"] == nil ? (request.type == "child" ? "Add profile photo" : "Add photo") : "Replace photo"
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
            }.scrollDismissesKeyboard(.interactively).defaultScrollAnchor(.top)
        }.background(Palette.paper).tint(tint).foregroundStyle(Palette.ink)
            .presentationDetents([baseDetent, Self.timeDetent, .large], selection: $detent)
            .careSheetStyle()
            .onAppear {
                load()
                diaperExpanded = request.type == "diaper" && DiaperFields.selected("Dirty", in: fields)
                updateDetent()
            }
            .onChange(of: diaperExpanded) { _, _ in updateDetent() }
            .onChange(of: fields["contents"]) { _, _ in
                if request.type == "diaper" { diaperExpanded = DiaperFields.selected("Dirty", in: fields) }
            }
            .onChange(of: date) {
                _, value in if end < value {
                    end = value
                }
            }
            .onChange(of: focusedField) { _, field in
                if request.type == "feeding", field == "amount" { amountWasEdited = true; fields["amount"] = "" }
            }
            .onChange(of: photo) { _, item in Task { await loadPhoto(item) } }
            .sheet(isPresented: $scanning) { BarcodeScanner { code in fields["isbn"] = code; scanning = false; Task { await lookup() } } }
            .sheet(isPresented: $choosingFormula) { FormulaChooser(current: fields["brand"] ?? "") { fields["brand"] = $0 } }
    }

    private func timeRow(_ label: String, target: String, value: Date) -> some View {
        VStack(spacing: 0) {
            EntryRow(title: label) {
                Button {
                    withAnimation {
                        dateTarget = dateTarget == target ? nil : target
                        updateDetent()
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
        VStack(spacing: 0) {
            EntryRow(title: field.label) {
                HStack(spacing: 8) {
                    TextField("0", text: binding(field)).keyboardType(.decimalPad)
                        .focused($focusedField, equals: field.key)
                        .font(.title3.weight(.medium)).monospacedDigit().multilineTextAlignment(.trailing)
                        .frame(width: 80).accessibilityLabel(field.label).accessibilityIdentifier(field.key)
                    if let unit = spec.fields.first(where: { $0.key == "unit" }) {
                        if request.type == "feeding" {
                            Text(fields["unit"] ?? "").font(.subheadline).foregroundStyle(Palette.secondary).accessibilityIdentifier("bottleUnit")
                        } else { unitChoices(unit) }
                    } else if field.key == "minutes" { Text("min").foregroundStyle(Palette.secondary) }
                }.fixedSize(horizontal: true, vertical: false)
            }
            if request.type == "feeding", let last = lastBottleAmount {
                HStack {
                    Spacer()
                    Button("Use last amount: \(last.value) \(last.unit)") {
                        focusedField = nil; fields["amount"] = last.value; fields["unit"] = last.unit; amountWasEdited = true
                    }.font(.caption).buttonStyle(.plain).foregroundStyle(tint).frame(minHeight: 44).accessibilityIdentifier("reuseBottleAmount")
                }.padding(.horizontal, 20)
            }
        }
    }

    private var lastBottleAmount: BottleAmount? {
        BottleAmount.latest(in: store.entities, childID: request.entity?.childID ?? store.childID, excluding: request.entity?.id)
    }

    private func unitChoices(_ field: FieldSpec) -> some View {
        let values = options(field)
        let buttonWidth = CGFloat(values.count) * ChoiceButtons.compactWidth
        let spacing = max(0, values.count - 1) * 4
        let width: CGFloat = dynamicType.isAccessibilitySize ? 132 : buttonWidth + CGFloat(spacing)
        return ChoiceButtons(options: values, selection: binding(field), color: spec.color,
                             identifier: "unit", minimumWidth: 44, horizontal: true).frame(width: width)
    }

    @ViewBuilder private func control(_ field: FieldSpec) -> some View {
        switch field.kind {
        case "formula":
            EntryRow(title: field.label) {
                Button { choosingFormula = true } label: { choiceLabel(fields[field.key]) }
                    .buttonStyle(.plain).accessibilityLabel(field.label).accessibilityIdentifier("formulaPicker").accessibilityValue(fields[field.key] ?? "Not recorded")
            }
        case "choice":
            VStack(alignment: .leading, spacing: 10) {
                Text(field.label).font(.body.weight(.medium)).foregroundStyle(Palette.ink)
                ChoiceButtons(options: options(field), selection: binding(field), color: spec.color, identifier: field.key, optional: !field.required || request.entity?.imported != nil)
            }.padding(.horizontal, 20).padding(.vertical, 12)
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

    private func updateDetent() {
        detent = dynamicType.isAccessibilitySize ? .large : dateTarget != nil || diaperExpanded ? Self.timeDetent : baseDetent
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
        if request.type == "diaper" { entity.detail = "" }
        if request.type == "sleep" {
            entity.end = end.timeIntervalSince1970
        }
        if store.save(entity) {
            dismiss()
        }
    }

    private func loadPhoto(_ item: PhotosPickerItem?) async {
        guard let data = try? await item?.loadTransferable(type: Data.self), photo == item,
              let encoded = PhotoEncoding.encode(data, longestSide: request.type == "child" ? 256 : 1000) else { return }
        fields["photo"] = encoded
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
        }.background(Palette.paper).presentationDetents([.height(230), .large]).careSheetStyle()
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

struct FormulaChooser: View {
    var current: String
    var selected: (String) -> Void
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""
    @State private var custom = false
    var body: some View {
        VStack(spacing: 0) {
            LogSheetHeader(title: "Formula", color: "amber", closeLabel: "Close", close: { dismiss() })
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(Palette.secondary)
                TextField("Search formulas", text: $search).textInputAutocapitalization(.words).accessibilityIdentifier("formulaSearch")
            }.padding(.horizontal, 20).padding(.vertical, 12)
            Divider()
            AppList {
                Button("Custom formula", systemImage: "plus") { custom = true }.accessibilityIdentifier("customFormula")
                Button("Not recorded") { selected(""); dismiss() }
                ForEach(store.state.formulaOptions.filter { search.isEmpty || $0.localizedCaseInsensitiveContains(search) }, id: \.self) { name in
                    Button { selected(name); dismiss() } label: {
                        HStack { Text(name).foregroundStyle(Palette.ink); Spacer(); if name == current { Image(systemName: "checkmark").foregroundStyle(Palette.tint("amber")) } }
                            .frame(minHeight: 44).contentShape(Rectangle())
                    }.accessibilityAddTraits(name == current ? .isSelected : [])
                }
            }
        }.background(Palette.paper).presentationDetents([.medium, .large]).careSheetStyle()
            .sheet(isPresented: $custom) { CustomFormulaView { value in selected(value); dismiss() } }
    }
}
