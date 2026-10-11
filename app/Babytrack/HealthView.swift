import BabyCore
import Charts
import SwiftUI

struct HealthView: View {
    private let types = ["medication", "temperature", "illness", "vaccine", "appointment", "milestone", "note"]
    var body: some View {
        AppList {
            Section {
                NavigationLink { GrowthView() } label: { category("growth", title: "Growth") }
                ForEach(types, id: \.self) { type in
                    NavigationLink { HealthRecords(type: type) } label: {
                        category(type, title: type == "note" ? "Notes & photos" : Catalog.shared.spec(type).title)
                    }
                }
            }
        }.appList().navigationTitle("Health")
    }

    private func category(_ type: String, title: String) -> some View {
        HStack(spacing: 14) {
            RecordSymbol(type: type); Text(title); Spacer()
        }.padding(.vertical, 8)
    }
}

struct HealthRecords: View {
    var type: String
    @Environment(AppStore.self) private var store
    private var records: [Entity] {
        store.entities.filter { $0.childID == store.childID && $0.type == type }.sorted { $0.at > $1.at }
    }

    var body: some View {
        AppList { ForEach(records) { entity in
            Button { store.detail = entity } label: { RecordRow(entity: entity, showDate: true) }.buttonStyle(.plain)
        } }
        .appList()
        .navigationTitle(Catalog.shared.spec(type).title)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                AddRecordButton(type: type)
            }
        }
        .overlay {
            if records.isEmpty {
                ContentUnavailableView(
                    "No records",
                    systemImage: Catalog.shared.spec(type).symbol
                )
            }
        }
    }
}
