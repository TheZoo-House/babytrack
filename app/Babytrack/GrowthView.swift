import BabyCore
import Charts
import SwiftUI

struct GrowthView: View {
    @Environment(AppStore.self) private var store
    @State private var measure = "Weight"
    private var records: [Entity] {
        store.care.filter { $0.type == "growth" && $0.fields["measure"] == measure }.sorted { $0.at < $1.at }
    }

    private var chartRecords: [Entity] {
        records.filter { Double($0.fields["value"] ?? "") != nil && Catalog.shared.spec("growth").options("unit", measure: measure).contains($0.fields["unit"] ?? "") }
    }

    private var unit: String {
        measure == "Weight" ? (store.unitSystem == "imperial" ? "lb" : "kg") :
            (store.unitSystem == "imperial" ? "in" : "cm")
    }

    private func value(_ entity: Entity) -> Double {
        let value = Double(entity.fields["value"] ?? "") ?? 0
        // Unit conversion is presentation-only. No medical percentiles are inferred.
        let source = entity.fields["unit"] ?? unit
        if source == unit {
            return value
        }
        if unit == "kg" {
            return source == "oz" ? value * 0.028349523125 : value * 0.45359237
        }
        if unit == "lb" {
            return source == "oz" ? value / 16 : value / 0.45359237
        }
        return unit == "cm" ? value * 2.54 : value / 2.54
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                Picker("Measurement", selection: $measure) {
                    Text("Weight").tag("Weight"); Text("Height").tag("Height"); Text("Head").tag("Head circumference")
                }
                .pickerStyle(.segmented)
                if let last = chartRecords.last {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("\(value(last).formatted(.number.precision(.fractionLength(1)))) \(unit)").font(.system(
                            size: 36,
                            weight: .medium,
                            design: .rounded
                        )); Text(last.date, format: .dateTime.month().day().year()).font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    if chartRecords.count > 1 {
                    Chart(chartRecords) { entity in
                        LineMark(x: .value("Date", entity.date), y: .value(unit, value(entity)))
                            .interpolationMethod(.monotone).foregroundStyle(Palette.accent)
                        PointMark(x: .value("Date", entity.date), y: .value(unit, value(entity)))
                            .foregroundStyle(Palette.accent)
                    }.chartYScale(domain: .automatic(includesZero: false)).frame(height: 240)
                        .accessibilityLabel("\(measure) measurements in \(unit)")
                    }
                } else {
                    ContentUnavailableView(records.isEmpty ? "No measurements" : "No measurements with a recorded unit", systemImage: "ruler")
                }
                VStack(spacing: 0) { ForEach(records.reversed()) { entity in
                    Button { store.detail = entity } label: { RecordRow(entity: entity, showTypeTitle: false, showDate: true) }
                        .buttonStyle(.plain); if entity.id != records.first?.id { Divider() }
                } }
            }.padding(24).frame(maxWidth: 900).frame(maxWidth: .infinity)
        }.background(Palette.paper).navigationTitle("Growth")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    AddRecordButton(type: "growth")
                }
            }
    }
}
