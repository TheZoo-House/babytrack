import BabyCore
import SwiftUI

typealias Palette = CarePalette

extension CarePalette {
    static func configureNavigation() {
        let bar = UINavigationBar.appearance()
        for (style, large) in [(UIFont.TextStyle.headline, false), (.largeTitle, true)] {
            let font = UIFont.preferredFont(forTextStyle: style)
            let serif = UIFont(descriptor: font.fontDescriptor.withDesign(.serif) ?? font.fontDescriptor, size: 0)
            if large {
                bar.largeTitleTextAttributes = [.font: serif]
            } else {
                bar.titleTextAttributes = [.font: serif]
            }
        }
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
        HStack { Text(title).font(.system(.title3, design: .serif, weight: .medium)); Spacer(); trailing() }.padding(.vertical, 8)
    }
}

struct RecordRow: View {
    var entity: Entity
    var pending = false
    var showTypeTitle = true
    @Environment(\.dynamicTypeSize) private var dynamicType
    var body: some View {
        let detailIsTitle = !showTypeTitle && entity.title == Catalog.shared.spec(entity.type).title && !entity.displayDetail.isEmpty
        HStack(alignment: .center, spacing: 14) {
            RecordSymbol(type: entity.type)
            VStack(alignment: .leading, spacing: 4) {
                Text(detailIsTitle ? entity.displayDetail : entity.title).font(.body.weight(.semibold)).lineLimit(2).foregroundStyle(Palette.ink)
                if !detailIsTitle && !entity.displayDetail
                    .isEmpty
                {
                    Text(entity.displayDetail).font(.subheadline).foregroundStyle(Palette.secondary).lineLimit(2)
                }
                if pending {
                    Text("Waiting to sync").font(.caption).foregroundStyle(Palette.secondary)
                }
                if dynamicType.isAccessibilitySize {
                    metadata.padding(.top, 4)
                }
            }
            Spacer(minLength: 8)
            if !dynamicType.isAccessibilitySize {
                metadata
            }
            Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(Palette.secondary)
        }.padding(.vertical, 8).contentShape(Rectangle())
    }

    @ViewBuilder private var metadata: some View {
        if !["book", "toy", "clothing", "location", "child"].contains(entity.type) {
            VStack(alignment: dynamicType.isAccessibilitySize ? .leading : .trailing, spacing: 4) {
                Text(entity.date, format: .dateTime.hour().minute()).font(.subheadline.monospacedDigit())
                    .foregroundStyle(Palette.secondary)
                if !entity.actor.isEmpty {
                    Text(entity.actor).font(.caption).foregroundStyle(Palette.secondary)
                }
            }
        }
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
                Text(Catalog.shared.spec(type).title).font(.system(.title2, design: .serif, weight: .semibold))
                if let child, !child.isEmpty {
                    Text(child).font(.subheadline).foregroundStyle(Palette.secondary)
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
                configuration.label.font(.caption).foregroundStyle(Palette.secondary)
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
                Text(title).font(.subheadline).foregroundStyle(Palette.secondary)
                content().frame(maxWidth: .infinity, minHeight: 44, alignment: .trailing)
            }
        }.frame(minHeight: 48).padding(.horizontal, 20).padding(.vertical, 4)
    }
}
