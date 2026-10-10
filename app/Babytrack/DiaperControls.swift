import BabyCore
import SwiftUI

struct DiaperControls: View {
    @Binding var fields: [String: String]
    @Binding var expanded: Bool
    @Environment(\.dynamicTypeSize) private var dynamicType
    @ScaledMetric(relativeTo: .body) private var circleSize = 68.0
    private let textures = ["Runny", "Mucous", "Mushy", "Solid", "Pebbles"]
    private let colors = ["Black", "Green", "Yellow", "Brown", "Red", "Gray"]
    @State private var more = false
    private var dirty: Bool {
        DiaperFields.selected("Dirty", in: fields)
    }

    var body: some View {
        VStack(spacing: 0) {
            CenteredSelectionLayout(horizontalSpacing: 20, verticalSpacing: 12, fullWidth: dynamicType.isAccessibilitySize) {
                ForEach(["Wet", "Dirty", "Dry"], id: \.self) { option in
                    let selected = DiaperFields.selected(option, in: fields)
                    Button { DiaperFields.toggleContents(option, in: &fields) } label: {
                        if dynamicType.isAccessibilitySize {
                            HStack {
                                Text(option); Spacer(); if selected {
                                    Image(systemName: "checkmark")
                                }
                            }
                            .font(.body.weight(.semibold)).padding(12).frame(maxWidth: .infinity, minHeight: 44)
                            .foregroundStyle(selected ? Palette.buttonInk : Palette.ink)
                            .background(selected ? Palette.fill("mint") : Palette.tint("mint").opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
                        } else {
                            ZStack {
                                Circle().fill(selected ? Palette.fill("mint") : Palette.paper)
                                Circle().strokeBorder(Palette.tint("mint").opacity(selected ? 0 : 0.5), lineWidth: 1.5)
                                Text(option).font(.body.weight(.semibold)).foregroundStyle(selected ? Palette.buttonInk : Palette.ink)
                                if selected {
                                    Image(systemName: "checkmark").font(.caption2.weight(.bold)).offset(y: circleSize * 0.3).foregroundStyle(Palette.buttonInk)
                                }
                            }.frame(width: circleSize, height: circleSize)
                        }
                    }.buttonStyle(.plain).accessibilityIdentifier("diaper-\(option)")
                        .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }.padding(.horizontal, 24).padding(.vertical, 16)
            Divider()
            if dirty {
                Button { expanded.toggle() } label: {
                    HStack { Text("Texture & color").font(.body.weight(.medium)); Spacer(); Image(systemName: expanded ? "chevron.up" : "chevron.down").font(.caption.weight(.semibold)) }
                        .foregroundStyle(Palette.ink).frame(minHeight: 48).padding(.horizontal, 20)
                }.buttonStyle(.plain).accessibilityIdentifier("diaperDetails")
                    .accessibilityValue(expanded ? "Expanded" : "Collapsed")
                if expanded {
                    palette(textures, key: "consistency")
                    palette(colors, key: "color")
                    let spec = Catalog.shared.spec("diaper")
                    let extras = spec.fields.filter { ["color", "consistency"].contains($0.key) }
                    Button(more ? "Fewer choices" : "More choices") { more.toggle() }
                        .font(.caption).foregroundStyle(Palette.tint("mint"))
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .trailing).padding(.horizontal, 20)
                    ForEach(extras) { field in
                        let primary = field.key == "color" ? colors : textures
                        let values = field.options.filter { !primary.contains($0) } + DiaperFields.tokens(field.key, in: fields).filter { !field.options.contains($0) }
                        let visible = more ? values : values.filter { DiaperFields.tokens(field.key, in: fields).contains($0) }
                        if !visible.isEmpty {
                            palette(visible, key: field.key)
                        }
                    }
                }
                Divider()
            }
            EntryRow(title: "Blowout") {
                Toggle("Blowout", isOn: Binding(get: { DiaperFields.hasBlowout(fields) }, set: { DiaperFields.setBlowout($0, in: &fields) }))
                    .labelsHidden().fixedSize().accessibilityIdentifier("diaperBlowout")
            }
            Divider()
            EntryRow(title: "Diaper rash") {
                Toggle("Diaper rash", isOn: Binding(get: { fields["rash"] == "true" }, set: { fields["rash"] = String($0) }))
                    .labelsHidden().fixedSize().accessibilityIdentifier("diaperRash")
            }
            Divider()
            if let detail = fields["detail"], !detail.isEmpty, detail.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() != "blowout" {
                EntryRow(title: "Detail") { TextField("Add", text: Binding(get: { fields["detail"] ?? "" }, set: { fields["detail"] = $0 })).multilineTextAlignment(.trailing) }
                Divider()
            }
        }.tint(Palette.tint("mint"))
    }

    private func palette(_ values: [String], key: String) -> some View {
        CenteredSelectionLayout(verticalSpacing: 10, fullWidth: dynamicType.isAccessibilitySize) {
            ForEach(values, id: \.self) { value in
                let selected = DiaperFields.tokens(key, in: fields).contains(value)
                Button { DiaperFields.toggle(value, key: key, in: &fields) } label: {
                    if dynamicType.isAccessibilitySize {
                        HStack(spacing: 12) {
                            mark(value, key: key, selected: selected).frame(width: 36, height: 36)
                            Text(value == "Mucous" ? "Mucousy" : value).font(.body).foregroundStyle(Palette.ink)
                            Spacer()
                            if selected {
                                Image(systemName: "checkmark").font(.caption.weight(.bold)).foregroundStyle(Palette.tint("mint"))
                            }
                        }.frame(minWidth: key == "color" ? 44 : 55, maxWidth: .infinity, minHeight: 64).contentShape(Rectangle())
                    } else {
                        VStack(spacing: 5) {
                            ZStack(alignment: .topTrailing) {
                                mark(value, key: key, selected: selected).frame(width: 36, height: 36)
                                if selected {
                                    Image(systemName: "checkmark.circle.fill").font(.caption).foregroundStyle(Palette.tint("mint")).background(Palette.paper, in: Circle()).offset(x: 5, y: -3)
                                }
                            }
                            Text(value == "Mucous" ? "Mucousy" : value).font(.caption).foregroundStyle(Palette.ink).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                        }.frame(minWidth: key == "color" ? 44 : 55, maxWidth: .infinity, minHeight: 64).contentShape(Rectangle())
                    }
                }.buttonStyle(.plain).accessibilityIdentifier("diaper-\(key)-\(value)")
                    .accessibilityLabel(value + (key == "color" ? " color" : " texture"))
                    .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }.padding(.horizontal, 20).padding(.vertical, 10)
    }

    @ViewBuilder private func mark(_ value: String, key: String, selected: Bool) -> some View {
        if key == "color" {
            Circle().fill(swatch(value)).overlay(Circle().strokeBorder(Palette.secondary.opacity(0.35), lineWidth: 1))
        } else {
            TextureMark(value: value).foregroundStyle(selected ? Palette.tint("mint") : Palette.secondary)
        }
    }

    private func swatch(_ value: String) -> Color {
        let hex: UInt32 = switch value {
        case "Black": 0x34281F
        case "Green": 0x7DA33A
        case "Yellow": 0xE8C24E
        case "Brown": 0x885A20
        case "Red": 0xC94337
        case "Gray": 0xB5B5B9
        case "White": 0xF2EEE5
        default: 0x85858A
        }
        return Color(red: Double((hex >> 16) & 255) / 255, green: Double((hex >> 8) & 255) / 255, blue: Double(hex & 255) / 255)
    }
}

private struct TextureMark: View {
    var value: String
    var body: some View {
        ZStack {
            switch value {
            case "Solid":
                Ellipse().frame(width: 34, height: 13).offset(y: 10)
                Ellipse().frame(width: 26, height: 14).offset(y: 2)
                Ellipse().frame(width: 16, height: 12).offset(y: -7)
            case "Pebbles", "Seedy":
                ForEach(0 ..< 5) { i in Circle().frame(width: CGFloat(8 + i % 3 * 3), height: CGFloat(8 + i % 3 * 3)).offset(x: CGFloat([-11, 4, 12, -6, 5][i]), y: CGFloat([-8, -9, 3, 8, 13][i])) }
            default:
                TextureBlob(lobes: value == "Mushy" ? 5 : 8).frame(width: 31, height: 29).offset(y: -3)
                if ["Runny", "Mucous", "Watery", "Loose"].contains(value) {
                    Capsule().frame(width: 5, height: value == "Mucous" ? 17 : 10).offset(x: -4, y: 10)
                    Capsule().frame(width: 4, height: 9).offset(x: 7, y: 9)
                }
            }
        }
    }
}

private struct TextureBlob: Shape {
    var lobes: Int
    func path(in rect: CGRect) -> Path {
        Path { path in
            for step in 0 ... 80 {
                let angle = Double(step) / 80 * 2 * .pi
                let radius = 0.43 + 0.06 * sin(angle * Double(lobes))
                let point = CGPoint(x: rect.midX + CGFloat(cos(angle) * radius) * rect.width, y: rect.midY + CGFloat(sin(angle) * radius) * rect.height)
                if step == 0 {
                    path.move(to: point)
                } else {
                    path.addLine(to: point)
                }
            }
            path.closeSubpath()
        }
    }
}
