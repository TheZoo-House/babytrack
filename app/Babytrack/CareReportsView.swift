import BabyCore
import SwiftUI

struct DateRangeReportView: View {
    var childID: String
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var from = Calendar.current.startOfDay(for: Date.now.addingTimeInterval(-86400 * 6))
    @State private var through = Calendar.current.startOfDay(for: Date.now)
    @State private var picker: String?
    @State private var format = "PDF"
    @State private var preparing = false
    @State private var sharing: ShareFile?
    private var rows: [CareReportRow] {
        let end = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: through))!.addingTimeInterval(-0.001)
        return CareReports.records(store.entities, childID: childID, from: Calendar.current.startOfDay(for: from), through: end)
    }
    var body: some View {
        VStack(spacing: 0) {
            LogSheetHeader(title: "Care report", color: "neutral", actionTitle: "Share", actionEnabled: !preparing && !rows.isEmpty, actionID: "shareCareReport", close: { dismiss() }) {
                preparing = true
                do { sharing = ShareFile(url: try ReportFiles.write(child: store.children.first { $0.id == childID }?.title ?? "Child", from: from, through: through, rows: rows, format: format)) }
                catch { store.error = error.localizedDescription }
                preparing = false
            }
            CareSheetBody {
                VStack(spacing: 0) {
                    rangeRow("From", key: "from", date: from)
                    if picker == "from" { CombinedDatePicker(date: $from, dateOnly: true, maximumDate: through).frame(height: 216) }
                    rangeRow("Through", key: "through", date: through)
                    if picker == "through" { CombinedDatePicker(date: $through, dateOnly: true, minimumDate: from, maximumDate: .now).frame(height: 216) }
                    EntryRow(title: "Format") { Picker("Format", selection: $format) { Text("PDF").tag("PDF"); Text("CSV").tag("CSV") }.pickerStyle(.segmented).frame(maxWidth: 180).accessibilityIdentifier("reportFormat") }
                    Divider()
                    Text("\(rows.count) records").font(.caption).foregroundStyle(Palette.secondary).frame(maxWidth: .infinity, alignment: .leading).padding(20).accessibilityIdentifier("reportRecordCount")
                    if preparing { ProgressView() }
                    if rows.isEmpty { Text("No records in this range").foregroundStyle(Palette.secondary).padding(20) }
                    ForEach(Array(rows.suffix(8).reversed()), id: \.entity.id) { row in
                        RecordRow(entity: row.entity, showTypeTitle: true, compact: true, showDate: true).padding(.horizontal, 20)
                        Divider().padding(.horizontal, 20)
                    }
                }
            }
        }.careSheetStyle().sheet(item: $sharing) { ShareSheet(items: [$0.url]) }
    }
    private func rangeRow(_ title: String, key: String, date: Date) -> some View {
        EntryRow(title: title) { Button(date.formatted(date: .abbreviated, time: .omitted)) { picker = picker == key ? nil : key }.accessibilityIdentifier("report-" + key) }
    }
}

struct HandoffView: View {
    var childID: String
    var select: (Entity) -> Void
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var since = Date.now.timeIntervalSince1970 - 86400
    @State private var checkedThrough = Date.now.timeIntervalSince1970
    private var records: [Entity] { store.state.caregiverChanges(childID: childID, since: since) }
    private var shareText: String { CareReports.text(child: store.children.first { $0.id == childID }?.title ?? "Child", rows: records.map { CareReportRow(entity: $0, detail: $0.displayDetail) }) }
    var body: some View {
        VStack(spacing: 0) {
            LogSheetHeader(title: "Caregiver handoff", color: "neutral", closeLabel: "Close", actionTitle: "Done", actionID: "markHandoffSeen", close: { dismiss() }) {
                do { try store.storage.update { $0.markHandoffSeen(childID: childID, through: checkedThrough) }; store.reload(); dismiss() }
                catch { store.error = error.localizedDescription }
            }
            AppList {
                Text("Since " + Date(timeIntervalSince1970: since).formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(Palette.secondary)
                if records.isEmpty { Text("No new caregiver activity").foregroundStyle(Palette.secondary) }
                ForEach(records) { entity in
                    Button { select(entity) } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            RecordRow(entity: entity, compact: true, showDate: true)
                            Text("Updated by \(entity.updatedBy ?? entity.actor) · \(Date(timeIntervalSince1970: entity.updatedAt).formatted(date: .abbreviated, time: .shortened))").font(.caption).foregroundStyle(Palette.secondary)
                        }
                    }.buttonStyle(.plain)
                }
                if !records.isEmpty { ShareLink(item: shareText) { Label("Share handoff", systemImage: "square.and.arrow.up") }.accessibilityIdentifier("shareHandoff") }
            }
        }.careSheetStyle().task {
            await store.sync()
            checkedThrough = max(store.state.snapshot.serverTime, Date.now.timeIntervalSince1970)
            since = store.state.handoffSeenAt?[childID] ?? checkedThrough - 86400
        }
    }
}
