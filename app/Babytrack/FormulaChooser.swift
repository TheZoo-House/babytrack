import BabyCore
import SwiftUI

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
            CareSheetBody {
            EntryRow(title: "Name") { TextField("Required", text: $name).textInputAutocapitalization(.words).multilineTextAlignment(.trailing).accessibilityLabel("Formula name").accessibilityIdentifier("customFormulaName") }
            }
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
