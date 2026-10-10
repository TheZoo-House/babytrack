#if canImport(UIKit)
    import SwiftUI
    import UIKit

    public enum CarePalette {
        public static let ink = color(0x24263C, 0xF4F5FB)
        public static let paper = color(0xF7F8FC, 0x161824)
        public static let accent = color(0x5752A2, 0xBBB4EB)
        public static let secondary = color(0x5C6075, 0xB8BCD0)
        public static let buttonInk = color(0x24263C)

        /// Catalog keys stay stable; each care category carries its color throughout.
        public static func tint(_ key: String) -> Color {
            switch key {
            case "amber": color(0x865516, 0xF4C56E)
            case "mint": color(0x286380, 0x95CCE8)
            case "indigo": color(0x5752A2, 0xBBB4EB)
            case "rose": color(0x97415F, 0xF2B0C1)
            default: accent
            }
        }

        public static func fill(_ key: String) -> Color {
            switch key {
            case "amber": color(0xF4C56E)
            case "mint": color(0x95CCE8)
            case "indigo": color(0xBBB4EB)
            case "rose": color(0xF2B0C1)
            default: color(0xD7D8EE)
            }
        }

        private static func color(_ light: UInt32, _ dark: UInt32? = nil) -> Color {
            func uiColor(_ hex: UInt32) -> UIColor {
                UIColor(red: CGFloat((hex >> 16) & 255) / 255, green: CGFloat((hex >> 8) & 255) / 255,
                        blue: CGFloat(hex & 255) / 255, alpha: 1)
            }
            return Color(uiColor: UIColor { uiColor($0.userInterfaceStyle == .dark ? (dark ?? light) : light) })
        }
    }
#endif
