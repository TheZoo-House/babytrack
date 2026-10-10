import BabyCore
import SwiftUI

struct TodayView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.dynamicTypeSize) private var dynamicType
    @ScaledMetric(relativeTo: .largeTitle) private var childTitleSize = 38
    @State private var showActions = false
    @State private var showJournal = false
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                if store.children.isEmpty {
                    ContentUnavailableView { Label("Add a child", systemImage: "face.smiling") } actions: {
                        Button("Add child") { store.form = FormRequest(type: "child") }.buttonStyle(.borderedProminent)
                    }
                } else {
                    if sizeClass == .regular && !dynamicType.isAccessibilitySize {
                        HStack(alignment: .top, spacing: 48) {
                            VStack(alignment: .leading, spacing: 20) { careSections }
                                .frame(maxWidth: .infinity)
                            VStack(alignment: .leading, spacing: 12) { recent; upcoming }.frame(maxWidth: .infinity)
                        }
                    } else {
                        careSections; recent; upcoming
                    }
                }
                if let notice = store.notice,
                   notice.hasPrefix("Offline")
                {
                    Text(notice).font(.caption).foregroundStyle(Palette.secondary)
                }
            }.padding(sizeClass == .regular ? 32 : 20).frame(maxWidth: 1250).frame(maxWidth: .infinity)
        }.background(Palette.paper).navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    if sizeClass !=
                        .regular
                    {
                        Text(store.branding).font(.subheadline.weight(.semibold)).foregroundStyle(Palette.accent)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showActions = true } label: { Image(systemName: "plus").font(.body.weight(.semibold)) }
                        .buttonStyle(CareActionStyle(color: "mint")).accessibilityLabel("Add record").accessibilityIdentifier("addRecord")
                }
            }
            .sheet(isPresented: $showActions) { AddRecordMenu() }
            .navigationDestination(isPresented: $showJournal) { JournalView() }
            .refreshable { await store.sync() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            if dynamicType.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 8) {
                    Text(Date.now, format: .dateTime.weekday(.abbreviated).month(.abbreviated).day()).font(.subheadline).foregroundStyle(Palette.secondary)
                    status
                }
            } else {
                HStack {
                    Text(Date.now, format: .dateTime.weekday(.abbreviated).month(.abbreviated).day()).font(.subheadline).foregroundStyle(Palette.secondary)
                    Spacer()
                    status
                }
            }
            Menu {
                ForEach(store.children) { child in Button(child.title) { store.selectChild(child.id) } }
                Button("Add child", systemImage: "plus") { store.form = FormRequest(type: "child") }
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(store.child?.title ?? "Today").font(.system(size: childTitleSize, weight: .medium, design: .serif))
                    if store.children.count > 1 {
                        Image(systemName: "chevron.down").font(.caption.weight(.bold))
                    }
                }.foregroundStyle(Palette.ink)
            }
            if let child = store.child,
               !child.detail.isEmpty
            {
                Text(child.detail).font(.subheadline).foregroundStyle(Palette.secondary)
            }
        }
    }

    @ViewBuilder private var status: some View {
        if store.isPreview, sizeClass != .regular {
            Text("Sample family").font(.caption.weight(.medium)).foregroundStyle(Palette.ochre)
        }
        if store.syncing {
            ProgressView().controlSize(.small)
        } else if store.pendingCount > 0 {
            Image(systemName: "icloud.and.arrow.up").accessibilityLabel("\(store.pendingCount) records waiting to sync")
        }
    }

    private var careSections: some View {
        VStack(spacing: 0) {
            activity(type: "feeding", identifier: "quickBottle", latestID: store.summary?.lastFeedingID,
                     total: store.summary.map { store.unitSystem == "imperial" ? String(format: "%.1f oz today", Double($0.feedingML) / 29.5735295625) : "\($0.feedingML) mL today" })
            Divider()
            activity(type: "diaper", identifier: "quickDiaper", latestID: store.summary?.lastDiaperID,
                     total: store.summary.map { "\($0.diaperCount) diaper\($0.diaperCount == 1 ? "" : "s") today" })
            Divider()
            activity(type: "sleep", identifier: "sleepTimeline", latestID: store.summary?.lastSleepID,
                     total: store.summary.map { "\($0.sleepMinutes / 60)h \($0.sleepMinutes % 60)m today" })
            Divider()
        }
    }

    private func activity(type: String, identifier: String, latestID: String?, total: String?) -> some View {
        let latest = (type == "sleep" ? store.activeSleep : nil) ?? store.entities.first { $0.id == latestID }
        return NavigationLink { JournalView(type: type) } label: {
            HStack(spacing: 14) {
                RecordSymbol(type: type, size: 42)
                VStack(alignment: .leading, spacing: 4) {
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(Catalog.shared.spec(type).title).font(.headline).foregroundStyle(Palette.ink).fixedSize()
                            Spacer(minLength: 8)
                            totalLabel(type: type, total: total).fixedSize()
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            Text(Catalog.shared.spec(type).title).font(.headline).foregroundStyle(Palette.ink)
                            totalLabel(type: type, total: total)
                        }
                    }
                    if type == "sleep", let active = store.activeSleep {
                        Text(timerInterval: active.date ... Date.distantFuture, countsDown: false)
                            .monospacedDigit().accessibilityIdentifier("sleepTimer")
                    } else {
                        Text(latest?.displayDetail ?? "No records yet").lineLimit(dynamicType.isAccessibilitySize ? 3 : 1)
                    }
                    if let latest {
                        Text(latest.date, format: .dateTime.month(.abbreviated).day().hour().minute())
                            .font(.caption).foregroundStyle(Palette.secondary)
                    }
                }.font(.subheadline).foregroundStyle(Palette.secondary)
                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(Palette.secondary)
            }.foregroundStyle(Palette.ink).padding(.vertical, 14).contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityIdentifier(identifier)
    }

    @ViewBuilder private func totalLabel(type: String, total: String?) -> some View {
        if let total {
            Text(total).font(.caption.weight(.medium)).monospacedDigit()
                .foregroundStyle(Palette.accent).accessibilityIdentifier("total-\(type)")
        }
    }

    private var recent: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionTitle(title: "Recent") { Button("See all") { showJournal = true }.font(.subheadline) }
            if store.care.isEmpty {
                Text("No records yet").foregroundStyle(Palette.secondary).padding(.vertical, 20)
            }
            ForEach(Array(store.care.prefix(6))) { entity in
                Button { store.detail = entity } label: { RecordRow(
                    entity: entity,
                    pending: store.state.outbox.contains { $0.entity.id == entity.id }
                ) }.buttonStyle(.plain)
                Divider()
            }
        }
    }

    private var upcoming: some View {
        let entries = store.entities
            .filter {
                ["reminder", "appointment"].contains($0.type) && $0.childID == store.childID && $0.scheduled == true
            }
            .sorted { $0.at < $1.at }
        return VStack(alignment: .leading, spacing: 0) {
            if !entries.isEmpty {
                SectionTitle(title: "Upcoming") { EmptyView() }
                ForEach(Array(entries.prefix(3))) { entity in
                    Button { store.detail = entity } label: {
                        HStack(spacing: 14) {
                            RecordSymbol(type: entity.type); VStack(alignment: .leading, spacing: 4) {
                                Text(entity.title).fontWeight(.semibold); Text(
                                    entity.date,
                                    format: .dateTime.month().day().hour().minute()
                                ).font(.subheadline).foregroundStyle(Palette.secondary)
                            }; Spacer()
                        }.padding(.vertical, 14)
                    }.buttonStyle(.plain)
                    Divider()
                }
            }
        }
    }
}

struct AddRecordMenu: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(spacing: 0) {
            LogSheetHeader(title: "Add record", color: "mint", closeLabel: "Close", close: { dismiss() })
            AppList {
                Section("Care") { ForEach(["feeding", "diaper", "sleep", "reading", "growth"], id: \.self) { type in entry(Catalog.shared.spec(type)) } }
                Section("Health & memories") { ForEach(Catalog.shared.types.filter { ["medication", "temperature", "illness", "vaccine", "appointment", "milestone", "note", "reminder"].contains($0.id) }) { type in entry(type) } }
            }
        }.presentationDetents([.medium, .large]).presentationSizing(.page).presentationDragIndicator(.visible).presentationCornerRadius(24)
    }

    private func entry(_ type: TypeSpec) -> some View {
        Button {
            dismiss(); Task { try? await Task.sleep(for: .milliseconds(250)); store.form = FormRequest(type: type.id) }
        } label: {
            HStack(spacing: 14) { RecordSymbol(type: type.id); Text(type.title).foregroundStyle(Palette.ink); Spacer(); Image(systemName: "plus").foregroundStyle(Palette.tint(type.color)) }.padding(
                .vertical,
                4
            )
        }.accessibilityIdentifier("add-\(type.id)")
    }
}

struct JournalView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dynamicTypeSize) private var dynamicType
    var type: String? = nil
    @State private var filter = "All"
    @State private var search = ""
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
            .buttonStyle(CareActionStyle(color: "mint")).accessibilityIdentifier("toggleSleep")
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
                } header: { Text(
                    day,
                    format: .dateTime.weekday(.wide).month().day()
                ) }
            }
        }.appList()
            .navigationTitle(type.map { Catalog.shared.spec($0).title } ?? "Journal").searchable(text: $search, prompt: "Search records")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if let type {
                        Button("Log", systemImage: "plus") { store.form = FormRequest(type: type) }
                            .buttonStyle(CareActionStyle(color: "mint"))
                            .accessibilityLabel("Log " + Catalog.shared.spec(type).title).accessibilityIdentifier("logRecord")
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
            }
            .overlay {
                if rows.isEmpty && type != "sleep" {
                    ContentUnavailableView("No records", systemImage: "clock")
                }
            }
    }
}
