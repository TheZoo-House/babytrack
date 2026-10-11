import SwiftUI

private struct InCareSheet: EnvironmentKey { static let defaultValue = false }
extension EnvironmentValues {
    var inCareSheet: Bool { get { self[InCareSheet.self] } set { self[InCareSheet.self] = newValue } }
}
struct CareBodyHeight: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}
struct CareHeaderHeight: PreferenceKey {
    static let defaultValue: CGFloat = 60
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

struct CareSheetBody<Content: View>: View {
    @ViewBuilder var content: () -> Content
    var body: some View {
        ScrollView {
            content().frame(maxWidth: .infinity, alignment: .leading)
                .background { GeometryReader { proxy in Color.clear.preference(key: CareBodyHeight.self, value: proxy.size.height) } }
        }.scrollDismissesKeyboard(.interactively).defaultScrollAnchor(.top).accessibilityIdentifier("careSheetScroll")
    }
}

struct CareListBody<Content: View>: View {
    @ViewBuilder var content: () -> Content
    var body: some View {
        CareSheetBody {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(sections: content()) { section in
                    ForEach(section.header) { header in header.font(.caption.weight(.semibold)).foregroundStyle(Palette.secondary).padding(.horizontal, 20).padding(.top, 16).padding(.bottom, 8) }
                    ForEach(Array(section.content.enumerated()), id: \.element.id) { index, row in
                        row.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).padding(.horizontal, 20).padding(.vertical, 8)
                        if index < section.content.count - 1 { Divider().padding(.horizontal, 20) }
                    }
                    ForEach(section.footer) { footer in footer.font(.caption).foregroundStyle(Palette.secondary).padding(.horizontal, 20).padding(.vertical, 8) }
                }
            }.padding(.bottom, 12)
        }
    }
}

struct CareSheetStyle: ViewModifier {
    @Environment(\.dynamicTypeSize) private var dynamicType
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var bodyHeight: CGFloat = 300
    @State private var headerHeight: CGFloat = 60
    @State private var selected: PresentationDetent = .height(372)
    private var fit: CGFloat { max(160, min(ceil(bodyHeight + headerHeight + 12), UIScreen.main.bounds.height * 0.86)) }
    func body(content: Content) -> some View {
        let sheet = content.environment(\.inCareSheet, true)
            .presentationDragIndicator(.visible).presentationCornerRadius(24)
            .presentationBackground(Palette.paper).foregroundStyle(Palette.ink)
            .onPreferenceChange(CareBodyHeight.self) { if $0 > 0 { bodyHeight = $0 } }
            .onPreferenceChange(CareHeaderHeight.self) { headerHeight = $0 }
            .presentationDetents(dynamicType.isAccessibilitySize ? [.large] : [.height(fit), .large], selection: $selected)
            .onChange(of: fit) { _, value in if selected != .large { selected = .height(value) } }
            .onAppear { selected = dynamicType.isAccessibilitySize ? .large : .height(fit) }
        if sizeClass == .regular || UIDevice.current.userInterfaceIdiom == .pad {
            sheet.frame(idealWidth: 540, maxWidth: 540).presentationSizing(.form)
        } else {
            sheet.presentationSizing(.fitted)
        }
    }
}
