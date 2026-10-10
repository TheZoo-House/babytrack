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
                if !entity.displayDetail
                    .isEmpty
                {
                    Text(entity.displayDetail).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
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

extension View {
    func appList() -> some View {
        listStyle(.plain).scrollContentBackground(.hidden).background(Palette.paper)
            .environment(\.defaultMinListRowHeight, 54)
    }
}

struct EntryHeading: View {
    var type: String
    var child: String?
    var body: some View {
        HStack(spacing: 14) {
            RecordSymbol(type: type, size: 52)
            VStack(alignment: .leading, spacing: 4) {
                Text(Catalog.shared.spec(type).title).font(.system(.title2, design: .rounded, weight: .semibold))
                if let child, !child.isEmpty {
                    Text(child).font(.subheadline).foregroundStyle(.secondary)
                }
            }
        }.padding(.vertical, 12)
    }
}

struct AppList<Content: View>: View {
    @ViewBuilder var content: () -> Content
    var body: some View {
        List { content().listRowBackground(Palette.paper) }.appList().labeledContentStyle(AppValueStyle())
    }
}

struct AppValueStyle: LabeledContentStyle {
    func makeBody(configuration: Configuration) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: 16) {
                configuration.label.fixedSize()
                Spacer(minLength: 16)
                configuration.content.fixedSize()
            }
            VStack(alignment: .leading, spacing: 6) {
                configuration.label.font(.caption).foregroundStyle(.secondary)
                configuration.content.frame(maxWidth: .infinity, alignment: .leading)
            }.padding(.vertical, 6)
        }
    }
}

extension Entity {
    /// Drafts have no server description yet; format only their entered fields.
    var displayDetail: String {
        if !detail.isEmpty {
            return detail
        }
        switch type {
        case "feeding": return [fields["amount"].map { $0 + " " + (fields["unit"] ?? "") } ?? "Amount not recorded", fields["brand"]].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
        case "diaper": return [fields["contents"], fields["color"], fields["consistency"]].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
        case "growth": return [fields["measure"], fields["value"].map { $0 + " " + (fields["unit"] ?? "") }].compactMap { $0 }.joined(separator: " · ")
        default: return fields["notes"] ?? ""
        }
    }
}

extension Palette {
    static let buttonInk = Color(red: 0.12, green: 0.16, blue: 0.2)
    static func fill(_ key: String) -> Color {
        switch key {
        case "amber": Color(red: 1, green: 0.82, blue: 0.31)
        case "indigo": Color(red: 0.66, green: 0.69, blue: 0.96)
        case "rose": Color(red: 0.96, green: 0.68, blue: 0.7)
        default: Color(red: 0.57, green: 0.81, blue: 0.71)
        }
    }
}

struct CareActionStyle: ButtonStyle {
    var color: String
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.subheadline.weight(.semibold))
            .foregroundStyle(Palette.buttonInk)
            .padding(.horizontal, 16).padding(.vertical, 10).frame(minHeight: 44)
            .background(Palette.fill(color), in: Capsule())
            .opacity(isEnabled ? (configuration.isPressed ? 0.75 : 1) : 0.45)
    }
}

struct LogSheetHeader: View {
    var title: String
    var color: String
    var closeLabel = "Cancel"
    var actionTitle: String?
    var actionEnabled = true
    var actionID = "saveRecord"
    var close: () -> Void
    var action: (() -> Void)?
    var body: some View {
        HStack(spacing: 12) {
            Button(action: close) { Image(systemName: "xmark").font(.title3).frame(width: 44, height: 44) }
                .accessibilityLabel(closeLabel).buttonStyle(.plain)
            Text(title).font(.system(.title3, design: .serif, weight: .medium))
                .multilineTextAlignment(.center).frame(maxWidth: .infinity)
            if let actionTitle, let action {
                Button(actionTitle, action: action).font(.body.weight(.semibold))
                    .frame(minWidth: 44, minHeight: 44).buttonStyle(.plain)
                    .disabled(!actionEnabled).opacity(actionEnabled ? 1 : 0.45).accessibilityIdentifier(actionID)
            } else {
                Color.clear.frame(width: 44, height: 44)
            }
        }.foregroundStyle(Palette.buttonInk).padding(.horizontal, 12).padding(.vertical, 8)
            .background(Palette.fill(color))
    }
}

struct EntryRow<Content: View>: View {
    var title: String
    @ViewBuilder var content: () -> Content
    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: 16) {
                Text(title).fixedSize(); Spacer(minLength: 12); content().frame(minHeight: 44)
            }
            VStack(alignment: .leading, spacing: 8) {
                Text(title).font(.subheadline).foregroundStyle(.secondary)
                content().frame(maxWidth: .infinity, minHeight: 44, alignment: .trailing)
            }
        }.frame(minHeight: 48).padding(.horizontal, 20).padding(.vertical, 4)
    }
}

struct CareSectionHeading<Action: View>: View {
    var type: String
    @ViewBuilder var action: () -> Action
    @Environment(\.dynamicTypeSize) private var dynamicType
    private var label: some View {
        HStack(spacing: 10) {
            RecordSymbol(type: type)
            Text(Catalog.shared.spec(type).title).font(.title3.weight(.semibold))
                .foregroundStyle(Palette.tint(Catalog.shared.spec(type).color))
        }
    }

    var body: some View {
        if dynamicType.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 12) {
                label
                HStack { Spacer(); action() }
            }
        } else {
            HStack(spacing: 10) { label; Spacer(); action() }
        }
    }
}
