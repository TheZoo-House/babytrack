import BabyCore
import SwiftUI

typealias Palette = CarePalette

extension CarePalette {
    static func configureNavigation() {
        let bar = UINavigationBar.appearance()
        for (style, large) in [(UIFont.TextStyle.headline, false), (.largeTitle, true)] {
            let font = UIFont.preferredFont(forTextStyle: style)
            let rounded = UIFont(descriptor: font.fontDescriptor.withDesign(.rounded) ?? font.fontDescriptor, size: 0)
            if large {
                bar.largeTitleTextAttributes = [.font: rounded]
            } else {
                bar.titleTextAttributes = [.font: rounded]
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
        HStack { Text(title).font(.system(.title3, design: .rounded, weight: .medium)); Spacer(); trailing() }.padding(.vertical, 8)
    }
}

struct RecordRow: View {
    var entity: Entity
    var pending = false
    var showTypeTitle = true
    var compact = false
    @Environment(\.dynamicTypeSize) private var dynamicType
    var body: some View {
        let detailIsTitle = !showTypeTitle && entity.title == Catalog.shared.spec(entity.type).title && !entity.displayDetail.isEmpty
        HStack(alignment: .center, spacing: 14) {
            RecordSymbol(type: entity.type, size: compact ? 24 : 38)
            VStack(alignment: .leading, spacing: 4) {
                Text(detailIsTitle ? entity.displayDetail : entity.title).font((compact ? Font.subheadline : .body).weight(.semibold)).lineLimit(2).foregroundStyle(Palette.ink)
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
        }.padding(.vertical, compact ? 6 : 8).contentShape(Rectangle())
    }

    @ViewBuilder private var metadata: some View {
        if !["book", "toy", "clothing", "location", "child"].contains(entity.type) {
            VStack(alignment: dynamicType.isAccessibilitySize ? .leading : .trailing, spacing: 4) {
                Text(entity.date, format: .dateTime.hour().minute()).font((compact ? Font.caption : .subheadline).monospacedDigit())
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
        case "diaper":
            let dirty = ["Dirty", "Both"].contains(fields["contents"] ?? "")
            let otherDetail = fields["detail"]?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "blowout" ? nil : fields["detail"]
            return ([fields["contents"]] + (dirty ? [otherDetail, fields["color"], fields["consistency"]] : []) + [DiaperFields.hasBlowout(fields) ? "Blowout" : nil, fields["rash"] == "true" ? "Diaper rash" : nil]).compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
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
            .background(Palette.fill(color), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .opacity(isEnabled ? (configuration.isPressed ? 0.75 : 1) : 0.45)
    }
}

struct CompactCareActionStyle: ButtonStyle {
    var color: String
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.subheadline.weight(.semibold)).foregroundStyle(Palette.buttonInk)
            .padding(.horizontal, 14).padding(.vertical, 8).frame(minWidth: 64, minHeight: 40)
            .background(Palette.fill(color), in: RoundedRectangle(cornerRadius: 11))
            .frame(minHeight: 44)
            .contentShape(Rectangle()).opacity(configuration.isPressed ? 0.7 : 1)
    }
}

struct AddRecordButton: View {
    var type: String
    var label: String? = nil
    @Environment(AppStore.self) private var store
    var body: some View {
        Button { store.form = FormRequest(type: type) } label: {
            Image(systemName: "plus").font(.body.weight(.semibold))
        }.buttonStyle(CareActionStyle(color: Catalog.shared.spec(type).color))
            .accessibilityLabel(label ?? "Add " + Catalog.shared.spec(type).title.lowercased())
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
    @Environment(\.dynamicTypeSize) private var dynamicType
    private var heading: some View {
        Text(title).font(.system(.title3, design: .rounded, weight: .semibold))
            .multilineTextAlignment(.center).frame(maxWidth: .infinity).accessibilitySortPriority(2)
    }
    private var closeButton: some View {
        Button(action: close) { Image(systemName: "xmark").font(.title3).frame(width: 44, height: 44) }
            .accessibilityLabel(closeLabel).accessibilityIdentifier("closeSheet-\(title)").buttonStyle(.plain)
    }
    @ViewBuilder private var actionButton: some View {
        if let actionTitle, let action {
            Button(actionTitle, action: action).font(.body.weight(.semibold))
                .padding(.horizontal, 14).frame(minHeight: 44).foregroundStyle(Palette.ink)
                .background(Palette.paper.opacity(0.95), in: Capsule()).buttonStyle(.plain)
                .disabled(!actionEnabled).opacity(actionEnabled ? 1 : 0.45).accessibilityIdentifier(actionID)
        } else { Color.clear.frame(width: 44, height: 44) }
    }
    var body: some View {
        Group {
            if dynamicType.isAccessibilitySize {
                VStack(spacing: 4) { HStack { closeButton; Spacer(); actionButton }; heading }
            } else {
                HStack(spacing: 12) { closeButton; heading; actionButton }
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

struct ChoiceButtons: View {
    var options: [String]
    @Binding var selection: String
    var color: String
    var identifier: String
    var optional = false
    var minimumWidth: CGFloat = 110
    var horizontal = false
    @Environment(\.dynamicTypeSize) private var dynamicType
    private var columns: [GridItem] {
        if dynamicType.isAccessibilitySize { return [GridItem(.flexible())] }
        if horizontal { return Array(repeating: GridItem(.flexible(), spacing: 4), count: options.count) }
        return [GridItem(.adaptive(minimum: minimumWidth), spacing: 8)]
    }
    private func label(_ option: String) -> String {
        if identifier == "measure", option == "Head circumference" { return "Head size" }
        if identifier == "kind" { return option == "other" ? "Other" : Catalog.shared.spec(option).title }
        return option
    }
    var body: some View {
        LazyVGrid(columns: columns, spacing: 8) {
            ForEach(options, id: \.self) { option in
                let chosen = selection == option
                Button { selection = chosen && optional ? "" : option } label: {
                    HStack(spacing: 4) {
                        Text(label(option)).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                        if chosen && identifier != "unit" { Image(systemName: "checkmark").font(.caption.weight(.bold)) }
                    }.font(.subheadline.weight(chosen ? .semibold : .regular)).frame(maxWidth: .infinity, minHeight: 44).padding(.horizontal, 8)
                        .foregroundStyle(chosen ? Palette.buttonInk : Palette.ink)
                        .background(chosen ? Palette.fill(color) : Palette.tint(color).opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Palette.tint(color).opacity(chosen ? 0 : 0.25), lineWidth: 1))
                }.buttonStyle(.plain).accessibilityIdentifier("\(identifier)-\(option)")
                    .accessibilityAddTraits(chosen ? .isSelected : [])
            }
        }
    }
}

private struct CareSheetStyle: ViewModifier {
    @Environment(\.dynamicTypeSize) private var dynamicType
    @ViewBuilder func body(content: Content) -> some View {
        let sheet = content.presentationSizing(.page).presentationDragIndicator(.visible).presentationCornerRadius(24)
            .presentationBackground(Palette.paper).foregroundStyle(Palette.ink)
        if dynamicType.isAccessibilitySize { sheet.presentationDetents([.large]) } else { sheet }
    }
}

extension View {
    func careSheetStyle() -> some View { modifier(CareSheetStyle()) }
}
