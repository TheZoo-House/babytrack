import BabyCore
import SwiftUI

struct JournalView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dynamicTypeSize) private var dynamicType
    var type: String? = nil
    @State private var filter = "All"
    @State private var search = ""
    @State private var report = false
    private var rows: [Entity] {
        store.care
            .filter {
                (type == nil ? (filter == "All" || $0.type == filter) : $0.type == type) &&
                    (search.isEmpty || $0.title.localizedCaseInsensitiveContains(search) || $0.detail
                        .localizedCaseInsensitiveContains(search))
            }
    }

    private var days: [Date] {
        Array(Set(rows.map { Calendar.current.startOfDay(for: $0.date) })).sorted(by: >)
    }

    @ViewBuilder private var sleepStatus: some View {
        if let active = store.activeSleep {
            Text(timerInterval: active.date ... Date.distantFuture, countsDown: false)
                .font(.title2.monospacedDigit()).accessibilityIdentifier("sleepTimer")
        } else {
            Text("Ready for sleep").foregroundStyle(Palette.secondary)
        }
    }

    private var sleepAction: some View {
        Button(store.activeSleep == nil ? "Start sleep" : "End sleep") { store.toggleSleep() }
            .buttonStyle(CareActionStyle(color: "indigo")).accessibilityIdentifier("toggleSleep")
    }

    var body: some View {
        AppList {
            if type == "sleep" {
                Section {
                    if dynamicType.isAccessibilitySize {
                        VStack(alignment: .leading, spacing: 12) {
                            sleepStatus
                            HStack { Spacer(); sleepAction }
                        }.padding(.vertical, 4)
                    } else {
                        HStack { sleepStatus; Spacer(); sleepAction }.padding(.vertical, 4)
                    }
                }
            }
            ForEach(days, id: \.self) { day in
                Section { ForEach(rows.filter { Calendar.current.isDate($0.date, inSameDayAs: day) }) { entity in
                    Button { store.detail = entity } label: { RecordRow(entity: entity, showTypeTitle: type == nil) }.buttonStyle(.plain).accessibilityIdentifier("timeline-\(entity.type)")
                }
                } header: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(day, format: .dateTime.weekday(.wide).month().day())
                        if let summary = store.state.summary(forDay: day, childID: store.childID) { Text(CareTime.totals(summary, imperial: store.unitSystem == "imperial")).font(.caption).accessibilityIdentifier("journalDayTotals") }
                    }
                }
            }
        }.appList()
            .navigationTitle(type.map { Catalog.shared.spec($0).title } ?? "Journal").searchable(text: $search, prompt: "Search records")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button { report = true } label: { Image(systemName: "square.and.arrow.up") }.accessibilityLabel("Care report").accessibilityIdentifier("openCareReport") }
                ToolbarItem(placement: .topBarTrailing) {
                    if let type {
                        AddRecordButton(type: type, label: "Log " + Catalog.shared.spec(type).title)
                            .accessibilityIdentifier("logRecord")
                    } else {
                        Menu { Button("All") { filter = "All" }; ForEach(Catalog.shared.types.filter { ![
                            "child",
                            "book",
                            "toy",
                            "clothing",
                            "location",
                            "reminder", "formula",
                        ].contains($0.id) }) { type in Button(type.title) { filter = type.id } } } label: {
                            Image(systemName: "line.3.horizontal.decrease")
                        }.accessibilityLabel("Filter records")
                    }
                }
            }.sheet(isPresented: $report) { DateRangeReportView(childID: store.childID) }
            .overlay {
                if rows.isEmpty && type != "sleep" {
                    ContentUnavailableView("No records", systemImage: "clock")
                }
            }
    }
}
