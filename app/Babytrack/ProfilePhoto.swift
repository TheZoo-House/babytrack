import BabyCore
import PhotosUI
import SwiftUI

struct ProfileAvatar: View {
    var photo: String?
    var size: CGFloat = 40
    var child = false
    var body: some View {
        Group {
            if let photo, let data = Data(base64Encoded: photo), let image = UIImage(data: data) {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Image(systemName: child ? "face.smiling.fill" : "person.fill").resizable().scaledToFit()
                    .padding(size * 0.25).foregroundStyle(Palette.accent)
            }
        }.frame(width: size, height: size).background(Palette.accent.opacity(0.1))
            .clipShape(Circle()).accessibilityHidden(true)
    }
}

enum PhotoEncoding {
    static func encode(_ data: Data, longestSide: CGFloat = 1000) -> String? {
        guard let image = UIImage(data: data) else { return nil }
        let ratio = min(1, longestSide / max(image.size.width, image.size.height))
        let size = CGSize(width: image.size.width * ratio, height: image.size.height * ratio)
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }.jpegData(compressionQuality: 0.65)?.base64EncodedString()
    }
}

struct CaregiverProfileView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var photo: String?
    @State private var selected: PhotosPickerItem?
    var body: some View {
        VStack(spacing: 0) {
            LogSheetHeader(title: "Caregiver profile", color: "neutral", actionTitle: "Save", close: { dismiss() }) {
                if store.setCaregiverPhoto(photo) {
                    dismiss()
                }
            }
            ScrollView { VStack(spacing: 16) {
                ProfileAvatar(photo: photo, size: 100)
                Text(store.state.snapshot.user.name).font(.headline)
                PhotosPicker(photo == nil ? "Add profile photo" : "Replace profile photo", selection: $selected, matching: .images)
                    .buttonStyle(CareActionStyle(color: "neutral"))
                if photo != nil {
                    Button("Remove photo", role: .destructive) { photo = nil }
                }
            }.padding(24) }
        }.background(Palette.paper).presentationDetents([.height(360), .large]).careSheetStyle()
            .onAppear { photo = store.caregiverPhoto }
            .onChange(of: selected) { _, item in
                Task {
                    if let data = try? await item?.loadTransferable(type: Data.self), selected == item, let encoded = PhotoEncoding.encode(data, longestSide: 256) {
                        photo = encoded
                    }
                }
            }
    }
}
