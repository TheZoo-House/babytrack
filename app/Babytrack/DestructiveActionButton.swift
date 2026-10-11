import SwiftUI

struct DestructiveActionButton: View {
    var title: String
    var question: String
    var message: String? = nil
    var identifier: String
    var enabled = true
    var action: () -> Void
    @State private var confirming = false
    @Environment(\.dynamicTypeSize) private var dynamicType

    var body: some View {
        Button { confirming = true } label: {
            Label(title, systemImage: "trash").font(.body.weight(.semibold)).frame(minHeight: 44).padding(.horizontal, 12)
        }.buttonStyle(.bordered).tint(.red).disabled(!enabled).accessibilityIdentifier(identifier)
            .popover(isPresented: $confirming, attachmentAnchor: .rect(.bounds), arrowEdge: .top) {
                VStack(alignment: .leading, spacing: 12) {
                    Text(question).font(.headline).foregroundStyle(Palette.ink).fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("deleteConfirmation")
                    if let message {
                        if dynamicType.isAccessibilitySize {
                            ScrollView { Text(message).font(.subheadline).foregroundStyle(Palette.ink) }.frame(maxHeight: 200)
                        } else {
                            Text(message).font(.subheadline).foregroundStyle(Palette.ink).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    let layout = dynamicType.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 8)) : AnyLayout(HStackLayout(spacing: 12))
                    layout {
                        Button("Cancel") { confirming = false }.buttonStyle(.bordered).accessibilityIdentifier("cancelDestructiveAction")
                        Button("Delete", role: .destructive) { confirming = false; action() }
                            .buttonStyle(.borderedProminent).tint(.red).foregroundStyle(.white).accessibilityIdentifier("confirmDestructiveAction")
                    }.frame(minHeight: 44)
                }.padding(20).frame(width: 280).background(Palette.paper)
                    .presentationCompactAdaptation(.popover)
            }
            .padding(.bottom, confirming ? (dynamicType.isAccessibilitySize ? 400 : message == nil ? 150 : 240) : 0)
    }
}
