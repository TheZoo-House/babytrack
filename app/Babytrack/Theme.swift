import BabyCore
import SwiftUI

enum Palette {
    static let ink = Color(
        light: UIColor(red: 0.16, green: 0.21, blue: 0.24, alpha: 1),
        dark: .init(red: 0.92, green: 0.92, blue: 0.9, alpha: 1)
    )
    static let paper = Color(
        light: .init(red: 0.98, green: 0.97, blue: 0.94, alpha: 1),
        dark: .init(red: 0.08, green: 0.1, blue: 0.12, alpha: 1)
    )
    static let accent = Color(
        light: .init(red: 0.24, green: 0.38, blue: 0.34, alpha: 1),
        dark: .init(red: 0.55, green: 0.77, blue: 0.67, alpha: 1)
    )
    static func tint(_ key: String) -> Color {
        switch key {
        case "amber": Color(
                light: .init(red: 0.62, green: 0.37, blue: 0.13, alpha: 1),
                dark: .init(red: 0.92, green: 0.69, blue: 0.4, alpha: 1)
            )
        case "indigo": Color(
                light: .init(red: 0.39, green: 0.38, blue: 0.61, alpha: 1),
                dark: .init(red: 0.68, green: 0.67, blue: 0.91, alpha: 1)
            )
        case "rose": Color(
                light: .init(red: 0.64, green: 0.36, blue: 0.39, alpha: 1),
                dark: .init(red: 0.9, green: 0.62, blue: 0.65, alpha: 1)
            )
        default: accent
        }
    }
}

extension Color {
    init(light: UIColor, dark: UIColor) {
        self.init(uiColor: UIColor { $0.userInterfaceStyle == .dark ? dark : light })
    }
}

struct RecordSymbol: View {
    var type: String
    var size: CGFloat = 38
    var body: some View {
        let spec = Catalog.shared.spec(type)
        Image(systemName: spec.symbol).font(.system(size: size * 0.42, weight: .medium))
            .foregroundStyle(Palette.tint(spec.color)).frame(width: size, height: size)
            .background(Palette.tint(spec.color).opacity(0.11), in: Circle()).accessibilityHidden(true)
    }
}

struct SectionTitle<Trailing: View>: View {
    var title: String
    @ViewBuilder var trailing: () -> Trailing
    var body: some View {
        HStack { Text(title).font(.title3.bold()); Spacer(); trailing() }.padding(.vertical, 8)
    }
}

struct RecordRow: View {
    var entity: Entity
    var pending = false
    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            RecordSymbol(type: entity.type)
            VStack(alignment: .leading, spacing: 4) {
                Text(entity.title).font(.body.weight(.semibold)).foregroundStyle(Palette.ink)
                if !entity.detail
                    .isEmpty
                {
                    Text(entity.detail).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                }
                if pending {
                    Text("Waiting to sync").font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            if !["book", "toy", "clothing", "location", "child"].contains(entity.type) {
                VStack(alignment: .trailing, spacing: 4) {
                    Text(entity.date, format: .dateTime.hour().minute()).font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                    if !entity.actor.isEmpty {
                        Text(entity.actor).font(.caption).foregroundStyle(.tertiary)
                    }
                }
            }
            Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
        }.padding(.vertical, 14).contentShape(Rectangle())
    }
}
