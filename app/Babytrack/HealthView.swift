import BabyCore
import Charts
import SwiftUI

struct HealthView: View {
    @Environment(AppStore.self) private var store
    private let types = ["medication", "temperature", "illness", "vaccine", "appointment", "milestone", "note"]
    var body: some View {
        List {
            Section { NavigationLink { GrowthView() } label: { Label("Growth", systemImage: "chart.xyaxis.line") } }
            Section {
                ForEach(types, id: \.self) { type in
                    NavigationLink { HealthRecords(type: type) } label: {
                        HStack(spacing: 14) {
                            RecordSymbol(type: type); Text(type == "note" ? "Notes & photos" : Catalog.shared.spec(type)
                                .title); Spacer()
                        }.padding(
                            .vertical,
                            8
                        )
                    }
                }
            }
        }.listStyle(.plain).scrollContentBackground(.hidden).background(Palette.paper).navigationTitle("Health")
    }
}

struct HealthRecords: View {
    var type: String
    @Environment(AppStore.self) private var store
    private var records: [Entity] {
        store.entities.filter { $0.childID == store.childID && $0.type == type }.sorted { $0.at > $1.at }
    }

    var body: some View {
        List { ForEach(records) { entity in
            Button { store.detail = entity } label: { RecordRow(entity: entity) }.buttonStyle(.plain)
        } }
        .listStyle(.plain).scrollContentBackground(.hidden).background(Palette.paper)
        .navigationTitle(Catalog.shared.spec(type).title)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { store.form = FormRequest(type: type) } label: { Image(systemName: "plus") }
                    .accessibilityLabel("Add \(Catalog.shared.spec(type).title.lowercased())")
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

struct GrowthView: View {
    @Environment(AppStore.self) private var store
    @State private var measure = "Weight"
    private var records: [Entity] {
        store.care.filter { $0.type == "growth" && $0.fields["measure"] == measure }.sorted { $0.at < $1.at }
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
                if let last = records.last {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("\(value(last).formatted(.number.precision(.fractionLength(1)))) \(unit)").font(.system(
                            size: 44,
                            weight: .medium,
                            design: .rounded
                        )); Text(last.date, format: .dateTime.month().day().year()).font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Chart(records) { entity in
                        LineMark(x: .value("Date", entity.date), y: .value(unit, value(entity)))
                            .interpolationMethod(.monotone).foregroundStyle(Palette.accent)
                        PointMark(x: .value("Date", entity.date), y: .value(unit, value(entity)))
                            .foregroundStyle(Palette.accent)
                    }.chartYScale(domain: .automatic(includesZero: false)).frame(height: 240)
                        .accessibilityLabel("\(measure) measurements in \(unit)")
                } else {
                    ContentUnavailableView("No measurements", systemImage: "ruler")
                }
                VStack(spacing: 0) { ForEach(records.reversed()) { entity in
                    Button { store.detail = entity } label: { RecordRow(entity: entity) }
                        .buttonStyle(.plain); Divider()
                } }
            }.padding(24).frame(maxWidth: 900).frame(maxWidth: .infinity)
        }.background(Palette.paper).navigationTitle("Growth")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { store.form = FormRequest(type: "growth") } label: { Image(systemName: "plus") }
                        .accessibilityLabel("Add measurement")
                }
            }
    }
}
