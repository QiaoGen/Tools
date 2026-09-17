import Foundation

/// 程序员模式的四种进制。
enum BaseRadix: Int, CaseIterable, Identifiable {
    case bin = 2
    case oct = 8
    case dec = 10
    case hex = 16

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .hex: "HEX"
        case .dec: "DEC"
        case .oct: "OCT"
        case .bin: "BIN"
        }
    }
}

/// 二元运算。`apply` 返回 nil 表示运算出错（除零 / 模零）。
enum BinaryOp: String, CaseIterable {
    case add, sub, mul, div, mod
    case and, or, xor, nand, nor
    case shl, shr, rol, ror

    var symbol: String {
        switch self {
        case .add: "+"
        case .sub: "−"
        case .mul: "×"
        case .div: "÷"
        case .mod: "Mod"
        case .and: "AND"
        case .or: "OR"
        case .xor: "XOR"
        case .nand: "NAND"
        case .nor: "NOR"
        case .shl: "<<"
        case .shr: ">>"
        case .rol: "RoL"
        case .ror: "RoR"
        }
    }

    /// 基本模式可用的四则运算。
    static let basicOps: [BinaryOp] = [.add, .sub, .mul, .div]

    var isBasicOp: Bool { Self.basicOps.contains(self) }

    func apply(_ a: UInt64, _ b: UInt64, word: WordSize) -> UInt64? {
        let m = word.mask
        let x = a & m
        let y = b & m
        switch self {
        case .add: return (x &+ y) & m
        case .sub: return (x &- y) & m
        case .mul: return (x &* y) & m
        case .div: return y == 0 ? nil : x / y
        case .mod: return y == 0 ? nil : x % y
        case .and: return x & y
        case .or: return x | y
        case .xor: return x ^ y
        case .nand: return ~(x & y) & m
        case .nor: return ~(x | y) & m
        case .shl: return y >= UInt64(word.rawValue) ? 0 : (x << Int(y)) & m
        case .shr: return y >= UInt64(word.rawValue) ? 0 : (x >> Int(y)) & m
        case .rol: return word.rotateLeft(x, by: y)
        case .ror: return word.rotateRight(x, by: y)
        }
    }

    /// 基本模式的双精度浮点运算。
    func applyDouble(_ a: Double, _ b: Double) -> Double? {
        switch self {
        case .add: return a + b
        case .sub: return a - b
        case .mul: return a * b
        case .div: return b == 0 ? nil : a / b
        default: return nil
        }
    }
}

/// 一元运算（程序员模式）。
enum UnaryOp {
    case not       // 按位取反
    case negate    // 二进制补码取负

    func apply(_ value: UInt64, word: WordSize) -> UInt64 {
        switch self {
        case .not: ~value & word.mask
        case .negate: (~value &+ 1) & word.mask
        }
    }
}
