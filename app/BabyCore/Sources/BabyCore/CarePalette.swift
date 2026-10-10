#if canImport(UIKit)
    import SwiftUI
    import UIKit

    public enum CarePalette {
        public static let ink = Color(
            light: UIColor(red: 0.13, green: 0.22, blue: 0.19, alpha: 1),
            dark: .init(red: 0.92, green: 0.92, blue: 0.9, alpha: 1)
        )
        public static let paper = Color(
            light: .init(red: 0.98, green: 0.97, blue: 0.94, alpha: 1),
            dark: .init(red: 0.07, green: 0.12, blue: 0.10, alpha: 1)
        )
        public static let accent = Color(
            light: .init(red: 0.24, green: 0.38, blue: 0.34, alpha: 1),
            dark: .init(red: 0.55, green: 0.77, blue: 0.67, alpha: 1)
        )
        public static let secondary = Color(light: .init(red: 0.36, green: 0.42, blue: 0.39, alpha: 1),
                                            dark: .init(red: 0.68, green: 0.75, blue: 0.71, alpha: 1))
        /// The catalog's color keys remain protocol-compatible; all activity chrome
        /// shares the same botanical identity. Symbols distinguish record types.
        public static func tint(_: String) -> Color {
            accent
        }

        public static let ochre = Color(light: .init(red: 0.62, green: 0.43, blue: 0.16, alpha: 1),
                                        dark: .init(red: 0.84, green: 0.67, blue: 0.36, alpha: 1))
        public static let buttonInk = Color(light: .init(red: 0.98, green: 0.97, blue: 0.94, alpha: 1),
                                            dark: .init(red: 0.07, green: 0.12, blue: 0.10, alpha: 1))
        public static func fill(_: String) -> Color {
            accent
        }
    }

    extension Color {
        init(light: UIColor, dark: UIColor) {
            self.init(uiColor: UIColor { $0.userInterfaceStyle == .dark ? dark : light })
        }
    }

#endif
