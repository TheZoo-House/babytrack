import BabyCore
import SwiftUI

struct TodayView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.dynamicTypeSize) private var dynamicType
    @ScaledMetric(relativeTo: .largeTitle) private var childTitleSize = 38
    @ScaledMetric(relativeTo: .largeTitle) private var timerSize = 48
    @State private var showActions = false
    @State private var showJournal = false
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                header
                if store.state.localPreview {
                    Text("Sample totals").font(.caption).foregroundStyle(.secondary)
                }
                if store.children.isEmpty {
                    ContentUnavailableView { Label("Add a child", systemImage: "face.smiling") } actions: {
                        Button("Add child") { store.form = FormRequest(type: "child") }.buttonStyle(.borderedProminent)
                    }
                } else {
                    if sizeClass == .regular {
                        HStack(alignment: .top, spacing: 48) {
                            VStack(alignment: .leading, spacing: 28) { sleep; careSections }
                                .frame(maxWidth: .infinity)
                            VStack(alignment: .leading, spacing: 12) { recent; upcoming }.frame(maxWidth: .infinity)
                        }
                    } else {
                        sleep; careSections; recent; upcoming
                    }
                }
                if let notice = store.notice,
                   notice.hasPrefix("Offline")
                {
                    Text(notice).font(.caption).foregroundStyle(.secondary)
                }
            }.padding(sizeClass == .regular ? 36 : 24).frame(maxWidth: 1250).frame(maxWidth: .infinity)
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
                        .accessibilityLabel("Add record").accessibilityIdentifier("addRecord")
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
                    Text(Date.now, format: .dateTime.weekday(.abbreviated).month(.abbreviated).day()).font(.subheadline).foregroundStyle(.secondary)
                    status
                }
            } else {
                HStack {
                    Text(Date.now, format: .dateTime.weekday(.wide).month(.wide).day()).font(.subheadline).foregroundStyle(.secondary)
                    Spacer()
                    status
                }
            }
            Menu {
                ForEach(store.children) { child in Button(child.title) { store.selectChild(child.id) } }
                Button("Add child", systemImage: "plus") { store.form = FormRequest(type: "child") }
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(store.child?.title ?? "Today").font(.system(size: childTitleSize, weight: .bold, design: .rounded))
                    if store.children.count > 1 {
                        Image(systemName: "chevron.down").font(.caption.weight(.bold))
                    }
                }.foregroundStyle(Palette.ink)
            }
            if let child = store.child,
               !child.detail.isEmpty
            {
                Text(child.detail).font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder private var status: some View {
        if store.isPreview, sizeClass != .regular {
            Text("Sample family").font(.caption.weight(.medium)).foregroundStyle(Palette.tint("indigo"))
        }
        if store.syncing {
            ProgressView().controlSize(.small)
        } else if store.pendingCount > 0 {
            Image(systemName: "icloud.and.arrow.up").accessibilityLabel("\(store.pendingCount) records waiting to sync")
        }
    }

    private var sleep: some View {
        VStack(alignment: .leading, spacing: 18) {
            Divider()
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 10) {
                    Label(
                        store.activeSleep == nil ? "Awake" : "Sleeping",
                        systemImage: store.activeSleep == nil ? "sun.max" : "moon.zzz.fill"
                    )
                    .font(.headline).foregroundStyle(Palette.tint("indigo"))
                    if let active = store.activeSleep {
                        Text(timerInterval: active.date ... Date.distantFuture, countsDown: false).font(.system(
                            size: timerSize,
                            weight: .light,
                            design: .rounded
                        )).monospacedDigit().accessibilityIdentifier("sleepTimer")
                        Text("Since \(active.date.formatted(date: .omitted, time: .shortened))").font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        if let last = store.entities.first(where: { $0.id == store.summary?.lastSleepID }), let end = last.end {
                            Text("Awake since \(Date(timeIntervalSince1970: end).formatted(date: .omitted, time: .shortened))").font(.system(.title2, design: .rounded, weight: .medium))
                            Text("Last sleep · " + last.detail).font(.subheadline).foregroundStyle(.secondary)
                        } else {
                            Text("Sleep timer").font(.system(.title2, design: .rounded, weight: .medium))
                        }
                    }
                }
                Spacer()
                if !dynamicType.isAccessibilitySize {
                    Image(systemName: store.activeSleep == nil ? "moon" : "moon.stars.fill").font(.system(
                        size: 42,
                        weight: .ultraLight
                    )).foregroundStyle(Palette.tint("indigo").opacity(0.45)).accessibilityHidden(true)
                }
            }.padding(.top, 8)
            HStack {
                Button { store.toggleSleep() } label: {
                    Label(
                        store.activeSleep == nil ? "Start sleep" : "End sleep",
                        systemImage: store.activeSleep == nil ? "play.fill" : "stop.fill"
                    )
                    .font(.body.weight(.semibold)).lineLimit(1).fixedSize(horizontal: true, vertical: false)
                    .padding(
                        .horizontal,
                        18
                    ).padding(.vertical, 13)
                    .background(Palette.tint("indigo").opacity(0.12), in: Capsule())
                    .foregroundStyle(Palette.tint("indigo"))
                }.accessibilityIdentifier("toggleSleep")
                Spacer()
                Button("Add past sleep") { store.form = FormRequest(type: "sleep") }.font(.subheadline)
            }
            if let summary = store.summary {
                Text("\(summary.sleepMinutes / 60)h \(summary.sleepMinutes % 60)m sleep today").font(.subheadline).foregroundStyle(.secondary)
            }
            Divider()
        }
    }

    private var careSections: some View {
        VStack(alignment: .leading, spacing: 28) {
            activity(type: "feeding", identifier: "quickBottle", latestID: store.summary?.lastFeedingID,
                     total: store.summary.map { store.unitSystem == "imperial" ? String(format: "%.1f oz", Double($0.feedingML) / 29.5735295625) : "\($0.feedingML) mL" },
                     count: store.summary.map { "\($0.feedingCount) bottle\($0.feedingCount == 1 ? "" : "s") today" })
            Divider()
            activity(type: "diaper", identifier: "quickDiaper", latestID: store.summary?.lastDiaperID,
                     total: store.summary.map { "\($0.diaperCount) diaper\($0.diaperCount == 1 ? "" : "s") today" }, count: nil)
            Divider()
        }
    }

    private func activity(type: String, identifier: String, latestID: String?, total: String?, count: String?) -> some View {
        let spec = Catalog.shared.spec(type)
        let latest = store.entities.first { $0.id == latestID }
        return VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                RecordSymbol(type: type)
                Text(spec.title).font(.title3.weight(.semibold)).foregroundStyle(Palette.tint(spec.color))
                Spacer()
                Button { store.form = FormRequest(type: type) } label: { Label("Log", systemImage: "plus") }
                    .font(.body.weight(.semibold)).foregroundStyle(Palette.tint(spec.color)).accessibilityIdentifier(identifier)
            }
            if let latest {
                Button { store.detail = latest } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(latest.detail).font(.system(.title2, design: .rounded, weight: .medium)).foregroundStyle(Palette.ink)
                        Text(latest.date, format: .dateTime.month().day().hour().minute()).font(.subheadline).foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }.buttonStyle(.plain)
            } else {
                Text("No records yet").foregroundStyle(.secondary)
            }
            if let total {
                HStack {
                    Text(total).font(.subheadline.weight(.semibold)).monospacedDigit()
                    if let count {
                        Text("· " + count).font(.subheadline).foregroundStyle(.secondary)
                    }
                }.accessibilityElement(children: .combine)
            }
            if store.pendingCount > 0 {
                Text("Totals update after sync").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var recent: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionTitle(title: "Recent") { Button("See all") { showJournal = true }.font(.subheadline) }
            if store.care.isEmpty {
                Text("No records yet").foregroundStyle(.secondary).padding(.vertical, 20)
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
                                ).font(.subheadline).foregroundStyle(.secondary)
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
        NavigationStack {
            AppList {
                Section("Care") { ForEach(Catalog.shared.types.filter { [
                    "feeding",
                    "diaper",
                    "sleep",
                    "reading",
                    "growth",
                ].contains($0.id) }) { type in entry(type) } }
                Section("Health & memories") { ForEach(Catalog.shared.types.filter { [
                    "medication",
                    "temperature",
                    "illness",
                    "vaccine",
                    "appointment",
                    "milestone",
                    "note",
                    "reminder",
                ].contains($0.id) }) { type in entry(type) } }
            }.appList().navigationTitle("Add record").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
        }
    }

    private func entry(_ type: TypeSpec) -> some View {
        Button {
            dismiss(); Task { try? await Task.sleep(for: .milliseconds(250)); store.form = FormRequest(type: type.id) }
        } label: {
            HStack(spacing: 14) { RecordSymbol(type: type.id); Text(type.title).foregroundStyle(Palette.ink) }.padding(
                .vertical,
                4
            )
        }.accessibilityIdentifier("add-\(type.id)")
    }
}

struct JournalView: View {
    @Environment(AppStore.self) private var store
    @State private var filter = "All"
    @State private var search = ""
    private var rows: [Entity] {
        store.care
            .filter {
                (filter == "All" || $0.type == filter) &&
                    (search.isEmpty || $0.title.localizedCaseInsensitiveContains(search) || $0.detail
                        .localizedCaseInsensitiveContains(search))
            }
    }

    private var days: [Date] {
        Array(Set(rows.map { Calendar.current.startOfDay(for: $0.date) })).sorted(by: >)
    }

    var body: some View {
        AppList {
            ForEach(days, id: \.self) { day in
                Section { ForEach(rows.filter { Calendar.current.isDate($0.date, inSameDayAs: day) }) { entity in
                    Button { store.detail = entity } label: { RecordRow(entity: entity) }.buttonStyle(.plain)
                }
                } header: { Text(
                    day,
                    format: .dateTime.weekday(.wide).month().day()
                ) }
            }
        }.appList()
            .navigationTitle("Journal").searchable(text: $search, prompt: "Search records")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
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
            .overlay {
                if rows.isEmpty {
                    ContentUnavailableView("No records", systemImage: "clock")
                }
            }
    }
}
