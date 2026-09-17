import Foundation

/// 数值格式化：各进制分组显示、双精度数字显示。
enum CalcFormatter {

    /// 从右往左每 size 位插入一个空格，如 "73BD5A2C" (size 2) -> "73 BD 5A 2C"。
    static func grouped(_ digits: String, size: Int) -> String {
        guard size > 0, digits.count > size else { return digits }
        var parts: [String] = []
        var endIndex = digits.endIndex
        while endIndex > digits.startIndex {
            let start = digits.index(endIndex, offsetBy: -size, limitedBy: digits.startIndex) ?? digits.startIndex
            parts.append(String(digits[start..<endIndex]))
            endIndex = start
        }
        return parts.reversed().joined(separator: " ")
    }

    /// 程序员模式：按当前进制格式化（DEC 会根据有符号设置重新解释）。
    static func programmer(_ value: UInt64, base: BaseRadix, word: WordSize, signed: Bool) -> String {
        switch base {
        case .hex:
            return grouped(String(value & word.mask, radix: 16).uppercased(), size: 2)
        case .dec:
            if signed {
                let v = word.signedValue(of: value)
                return v < 0 ? "-" + grouped(String(-v), size: 3) : grouped(String(v), size: 3)
            }
            return grouped(String(value & word.mask), size: 3)
        case .oct:
            return grouped(String(value & word.mask, radix: 8), size: 3)
        case .bin:
            return grouped(String(value & word.mask, radix: 2), size: 4)
        }
    }

    /// 基本模式：双精度显示，整数不带小数点，千位分组。
    static func decimal(_ value: Double) -> String {
        guard value.isFinite else { return "错误" }
        if value == value.rounded(), abs(value) < 1e15 {
            let v = Int64(exactly: value.rounded()) ?? 0
            return v < 0 ? "-" + grouped(String(-v), size: 3) : grouped(String(v), size: 3)
        }
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.groupingSeparator = " "
        f.decimalSeparator = "."
        f.groupingSize = 3
        f.maximumFractionDigits = 10
        f.minimumFractionDigits = 0
        return f.string(from: NSNumber(value: value)) ?? String(value)
    }

    /// 基本模式输入中的实时分组，如 "12345.6" -> "12 345.6"。
    static func typing(_ text: String) -> String {
        guard let dotIndex = text.firstIndex(of: ".") else {
            return grouped(text, size: 3)
        }
        let intPart = String(text[..<dotIndex])
        let rest = String(text[dotIndex...])
        let sign = intPart.hasPrefix("-") ? "-" : ""
        let digits = sign.isEmpty ? intPart : String(intPart.dropFirst())
        return sign + grouped(digits, size: 3) + rest
    }
}
