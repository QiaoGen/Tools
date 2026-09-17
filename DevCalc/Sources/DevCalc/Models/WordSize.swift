import Foundation

/// 计算字长。所有运算结果都截断到字长范围内（无符号位模式存储）。
enum WordSize: Int, CaseIterable, Identifiable {
    case bits8 = 8
    case bits16 = 16
    case bits32 = 32
    case bits64 = 64

    var id: Int { rawValue }

    var label: String { "\(rawValue) 位" }

    var mask: UInt64 {
        rawValue == 64 ? .max : (1 << rawValue) &- 1
    }

    var signBit: UInt64 { 1 << (rawValue - 1) }

    /// 把位模式按该字长重新解释为有符号数（二进制补码）。
    func signedValue(of value: UInt64) -> Int64 {
        let v = value & mask
        guard rawValue < 64 else { return Int64(bitPattern: v) }
        if v & signBit == 0 { return Int64(v) }
        return Int64(bitPattern: v | ~mask)
    }

    func rotateLeft(_ value: UInt64, by amount: UInt64) -> UInt64 {
        let v = value & mask
        let n = Int(amount % UInt64(rawValue))
        guard n > 0 else { return v }
        if rawValue == 64 { return (v << n) | (v >> (64 - n)) }
        return ((v << n) | (v >> (rawValue - n))) & mask
    }

    func rotateRight(_ value: UInt64, by amount: UInt64) -> UInt64 {
        let v = value & mask
        let n = Int(amount % UInt64(rawValue))
        guard n > 0 else { return v }
        if rawValue == 64 { return (v >> n) | (v << (64 - n)) }
        return ((v >> n) | (v << (rawValue - n))) & mask
    }
}
