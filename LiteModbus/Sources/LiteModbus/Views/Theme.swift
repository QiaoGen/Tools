import SwiftUI
import AppKit

/// 语义色板：全部通过 NSColor 动态提供者实现，自动跟随系统明暗外观切换。
/// 色值唯一来源见 LiteModbus/design-system.md。
enum Theme {
    private static func dynamic(light: NSColor, dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let match = appearance.bestMatch(from: [
                .aqua, .darkAqua,
                .accessibilityHighContrastAqua, .accessibilityHighContrastDarkAqua,
            ])
            return match == .darkAqua || match == .accessibilityHighContrastDarkAqua ? dark : light
        })
    }

    private static func rgb(_ hex: UInt32, alpha: CGFloat = 1) -> NSColor {
        NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
                green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255,
                alpha: alpha)
    }

    static let windowBackground = dynamic(light: rgb(0xF4F4F7), dark: rgb(0x1B1B1D))
    static let panelBackground = dynamic(light: rgb(0xFFFFFF), dark: rgb(0x262628))
    static let sidebarBackground = dynamic(light: rgb(0xECECF1), dark: rgb(0x222225))
    static let cardBackground = dynamic(light: rgb(0xFFFFFF), dark: rgb(0x2C2C2E))
    static let accent = dynamic(light: rgb(0x007AFF), dark: rgb(0x0A84FF))
    static let success = dynamic(light: rgb(0x34C759), dark: rgb(0x30D158))
    static let warning = dynamic(light: rgb(0xFF9500), dark: rgb(0xFF9F0A))
    static let error = dynamic(light: rgb(0xFF3B30), dark: rgb(0xFF453A))
    static let labelGray = dynamic(light: rgb(0x6E6E73), dark: rgb(0x8E8E93))
    static let hairline = dynamic(light: NSColor.black.withAlphaComponent(0.10),
                                  dark: NSColor.white.withAlphaComponent(0.08))
    static let insetBackground = dynamic(light: NSColor.black.withAlphaComponent(0.04),
                                         dark: NSColor.white.withAlphaComponent(0.05))
    static let flashBackground = dynamic(light: rgb(0x007AFF, alpha: 0.12),
                                         dark: rgb(0x0A84FF, alpha: 0.20))
    static let selectedRow = dynamic(light: rgb(0x007AFF, alpha: 0.08),
                                     dark: rgb(0x0A84FF, alpha: 0.12))
    static let primaryText = dynamic(light: rgb(0x1C1C1E), dark: NSColor.white)
}

extension Font {
    /// 数值 / 地址 / 报文用等宽字体。
    static func mono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}
