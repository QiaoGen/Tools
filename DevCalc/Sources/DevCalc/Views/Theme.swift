import SwiftUI
import AppKit

/// 语义色板：全部通过 NSColor 动态提供者实现，自动跟随系统明暗外观切换。
/// 色值唯一来源见 .superdesign/design-system.md。
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

    static let windowBackground = dynamic(
        light: rgb(0xF4F4F7),
        dark: rgb(0x1B1B1D)
    )
    static let keyDigit = dynamic(
        light: rgb(0xFBFBFD),
        dark: rgb(0x5E5E63)
    )
    static let keyFunction = dynamic(
        light: rgb(0xE3E3E8),
        dark: rgb(0x3A3A3E)
    )
    static let keyHex = dynamic(
        light: rgb(0xDCE9F2),
        dark: rgb(0x35566B)
    )
    static let accent = dynamic(
        light: rgb(0x007AFF),
        dark: rgb(0x0A84FF)
    )
    static let labelGray = dynamic(
        light: rgb(0x6E6E73),
        dark: rgb(0x8E8E93)
    )
    static let hairline = dynamic(
        light: NSColor.black.withAlphaComponent(0.10),
        dark: NSColor.white.withAlphaComponent(0.08)
    )
    /// 置 0 的 bit 格子背景。
    static let bitCellClear = dynamic(
        light: NSColor.black.withAlphaComponent(0.05),
        dark: NSColor.white.withAlphaComponent(0.06)
    )
    /// 数字/功能键上的文字：浅色外观近黑，深色外观白色。
    static let keyNeutralLabel = dynamic(
        light: rgb(0x1C1C1E),
        dark: NSColor.white
    )

    static func keyBackground(for role: KeyRole) -> Color {
        switch role {
        case .digit: keyDigit
        case .hex: keyHex
        case .function: keyFunction
        case .op, .equals: accent
        }
    }

    static func keyForeground(for role: KeyRole) -> Color {
        switch role {
        case .digit, .function: keyNeutralLabel
        case .hex, .op, .equals: Color(nsColor: .white)
        }
    }
}

enum KeyRole {
    case digit
    case hex
    case function
    case op
    case equals
}

extension Font {
    /// 数值显示用等宽字体（进制对齐是硬需求）。
    static func calcMono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}
