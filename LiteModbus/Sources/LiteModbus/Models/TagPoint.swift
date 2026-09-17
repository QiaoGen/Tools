import Foundation

/// 点位数据类型。寄存器类点位可占 1 / 2 / 4 个寄存器。
enum TagDataType: String, Codable, CaseIterable, Identifiable {
    case bool
    case uint16
    case int16
    case uint32
    case int32
    case float32
    case uint64
    case int64
    case float64

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .bool: return "Bool"
        case .uint16: return "UInt16"
        case .int16: return "Int16"
        case .uint32: return "UInt32"
        case .int32: return "Int32"
        case .float32: return "Float32"
        case .uint64: return "UInt64"
        case .int64: return "Int64"
        case .float64: return "Float64"
        }
    }

    var registerCount: Int {
        switch self {
        case .bool, .uint16, .int16: return 1
        case .uint32, .int32, .float32: return 2
        case .uint64, .int64, .float64: return 4
        }
    }

    var isBitType: Bool { self == .bool }
}

/// 多寄存器类型的字节序（按 16 位字排列 + 字内字节交换）。
/// - ABCD：大端（标准 Modbus）
/// - CDAB：相邻字交换
/// - BADC：字内字节交换
/// - DCBA：小端（完全逆序）
enum ByteOrder: String, Codable, CaseIterable, Identifiable {
    case abcd = "ABCD"
    case cdab = "CDAB"
    case badc = "BADC"
    case dcba = "DCBA"

    var id: String { rawValue }

    /// 传输序寄存器数组 → 规范大端字数组（高字在前）。
    func canonicalWords(from regs: [UInt16]) -> [UInt16] {
        switch self {
        case .abcd:
            return regs
        case .cdab:
            var out = regs
            for i in stride(from: 0, to: out.count - 1, by: 2) {
                out.swapAt(i, i + 1)
            }
            return out
        case .badc:
            return regs.map { $0.byteSwapped }
        case .dcba:
            return regs.reversed().map { $0.byteSwapped }
        }
    }

    /// 规范大端字数组 → 传输序寄存器数组。
    func transmissionRegisters(from words: [UInt16]) -> [UInt16] {
        // 两个方向的置换互逆，直接复用。
        return canonicalWords(from: words)
    }
}

/// 点位当前值。以原始位型保存，按类型解释。
enum TagValue: Equatable, Codable {
    case bool(Bool)
    case uint16(UInt16)
    case int16(Int16)
    case uint32(UInt32)
    case int32(Int32)
    case float32(Float)
    case uint64(UInt64)
    case int64(Int64)
    case float64(Double)

    var dataType: TagDataType {
        switch self {
        case .bool: return .bool
        case .uint16: return .uint16
        case .int16: return .int16
        case .uint32: return .uint32
        case .int32: return .int32
        case .float32: return .float32
        case .uint64: return .uint64
        case .int64: return .int64
        case .float64: return .float64
        }
    }

    /// 规范大端字节序（高位字节在前）。
    var bigEndianBytes: [UInt8] {
        switch self {
        case .bool(let v): return [v ? 1 : 0]
        case .uint16(let v): return withBytes(UInt64(v), count: 2)
        case .int16(let v): return withBytes(UInt64(UInt16(bitPattern: v)), count: 2)
        case .uint32(let v): return withBytes(UInt64(v), count: 4)
        case .int32(let v): return withBytes(UInt64(UInt32(bitPattern: v)), count: 4)
        case .float32(let v): return withBytes(UInt64(v.bitPattern), count: 4)
        case .uint64(let v): return withBytes(v, count: 8)
        case .int64(let v): return withBytes(UInt64(bitPattern: v), count: 8)
        case .float64(let v): return withBytes(v.bitPattern, count: 8)
        }
    }

    private func withBytes(_ bits: UInt64, count: Int) -> [UInt8] {
        (0..<count).map { UInt8(bits >> UInt64(8 * (count - 1 - $0)) & 0xFF) }
    }

    static func from(bigEndianWords words: [UInt16], type: TagDataType) -> TagValue? {
        var bytes: [UInt8] = []
        for w in words {
            bytes.append(UInt8(w >> 8))
            bytes.append(UInt8(w & 0xFF))
        }
        func beUInt(_ count: Int) -> UInt64 {
            var v: UInt64 = 0
            for i in 0..<count { v = v << 8 | UInt64(bytes[i]) }
            return v
        }
        switch type {
        case .bool:
            return .bool(bytes.first.map { $0 != 0 } ?? false)
        case .uint16: return .uint16(UInt16(truncatingIfNeeded: beUInt(2)))
        case .int16: return .int16(Int16(bitPattern: UInt16(truncatingIfNeeded: beUInt(2))))
        case .uint32: return .uint32(UInt32(truncatingIfNeeded: beUInt(4)))
        case .int32: return .int32(Int32(bitPattern: UInt32(truncatingIfNeeded: beUInt(4))))
        case .float32: return .float32(Float(bitPattern: UInt32(truncatingIfNeeded: beUInt(4))))
        case .uint64: return .uint64(beUInt(8))
        case .int64: return .int64(Int64(bitPattern: beUInt(8)))
        case .float64: return .float64(Double(bitPattern: beUInt(8)))
        }
    }

    /// 解码为传输序寄存器。bool 之外都按数值编码。
    func transmissionRegisters(order: ByteOrder) -> [UInt16] {
        let bytes = bigEndianBytes
        var words: [UInt16] = []
        var i = 0
        while i + 1 < bytes.count {
            words.append(UInt16(bytes[i]) << 8 | UInt16(bytes[i + 1]))
            i += 2
        }
        if case .bool(let v) = self {
            return [v ? 1 : 0]
        }
        return order.transmissionRegisters(from: words)
    }

    /// 表格显示文本（工程格式）。
    var displayText: String {
        switch self {
        case .bool(let v): return v ? "1" : "0"
        case .uint16(let v): return "\(v)"
        case .int16(let v): return "\(v)"
        case .uint32(let v): return "\(v)"
        case .int32(let v): return "\(v)"
        case .float32(let v): return formatFloat(Double(v))
        case .uint64(let v): return "\(v)"
        case .int64(let v): return "\(v)"
        case .float64(let v): return formatFloat(v)
        }
    }

    private func formatFloat(_ v: Double) -> String {
        if v.isNaN { return "NaN" }
        if v.isInfinite { return v > 0 ? "+∞" : "-∞" }
        if abs(v) >= 1e10 || (abs(v) < 1e-4 && v != 0) {
            return String(format: "%.4e", v)
        }
        return String(format: "%.4g", v)
    }

    /// 从用户输入解析（支持 0x 十六进制整数）。
    static func parse(_ text: String, type: TagDataType) -> TagValue? {
        let t = text.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return nil }
        switch type {
        case .bool:
            if t == "1" || t.lowercased() == "true" || t.lowercased() == "on" { return .bool(true) }
            if t == "0" || t.lowercased() == "false" || t.lowercased() == "off" { return .bool(false) }
            return nil
        case .uint16:
            if t.lowercased().hasPrefix("0x"), let v = UInt16(t.dropFirst(2), radix: 16) { return .uint16(v) }
            return UInt16(t).map { .uint16($0) }
        case .int16:
            if t.lowercased().hasPrefix("0x"), let v = UInt16(t.dropFirst(2), radix: 16) { return .int16(Int16(bitPattern: v)) }
            return Int16(t).map { .int16($0) }
        case .uint32:
            if t.lowercased().hasPrefix("0x"), let v = UInt32(t.dropFirst(2), radix: 16) { return .uint32(v) }
            return UInt32(t).map { .uint32($0) }
        case .int32:
            if t.lowercased().hasPrefix("0x"), let v = UInt32(t.dropFirst(2), radix: 16) { return .int32(Int32(bitPattern: v)) }
            return Int32(t).map { .int32($0) }
        case .float32:
            return Float(t).map { .float32($0) }
        case .uint64:
            if t.lowercased().hasPrefix("0x"), let v = UInt64(t.dropFirst(2), radix: 16) { return .uint64(v) }
            return UInt64(t).map { .uint64($0) }
        case .int64:
            if t.lowercased().hasPrefix("0x"), let v = UInt64(t.dropFirst(2), radix: 16) { return .int64(Int64(bitPattern: v)) }
            return Int64(t).map { .int64($0) }
        case .float64:
            return Double(t).map { .float64($0) }
        }
    }
}

/// 点位地址：区域 + 0 基偏移 + 可选位号。
/// 字符串约定：40001 = 保持寄存器 0；40001.1 = 其 bit1；六位编号 400101 = 保持寄存器 100。
struct TagAddress: Equatable, Codable {
    var area: ModbusArea
    /// 0 基协议地址。
    var offset: Int
    /// nil = 整寄存器；0...15 = 寄存器位（0 为最低位 LSB）。
    var bit: Int?

    var isBitAccess: Bool { bit != nil }

    /// 用户可读编号（40001 / 40001.1）。
    var displayNumber: String {
        let number = area.displayAddress(offset: offset)
        if let bit {
            return "\(number).\(bit)"
        }
        return "\(number)"
    }

    // MARK: - 解析

    enum ParseError: LocalizedError {
        case empty
        case invalidCharacters
        case unknownArea(String)
        case outOfRange
        case invalidBit

        var errorDescription: String? {
            switch self {
            case .empty: return "地址为空"
            case .invalidCharacters: return "地址只能包含数字和位号（如 40001.1）"
            case .unknownArea(let p): return "地址前缀须为 0/1/3/4，收到 \(p)"
            case .outOfRange: return "地址超出范围（每区最多 65536 个单元）"
            case .invalidBit: return "位号须为 0–15（0 为最低位）"
            }
        }
    }

    static func parse(_ text: String) throws -> TagAddress {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ParseError.empty }
        var main = trimmed
        var bit: Int?
        if let dotIndex = trimmed.firstIndex(of: ".") {
            main = String(trimmed[..<dotIndex])
            let bitPart = String(trimmed[trimmed.index(after: dotIndex)...])
            guard let b = Int(bitPart), (0...15).contains(b) else { throw ParseError.invalidBit }
            bit = b
        }
        guard let number = Int(main), number >= 0 else { throw ParseError.invalidCharacters }
        let digits = main.count
        guard let first = main.first, let areaRaw = Int(String(first)),
              let area = ModbusArea(rawValue: areaRaw) else {
            throw ParseError.unknownArea(main.isEmpty ? "-" : String(main.prefix(1)))
        }
        let offset: Int
        if digits <= 5 {
            offset = number - area.fiveDigitBase
        } else {
            // 六位编号：400101 → 保持寄存器 100。
            offset = number - (area.rawValue * 100000 + 1)
        }
        guard offset >= 0, offset < ModbusLimits.addressSpace else { throw ParseError.outOfRange }
        return TagAddress(area: area, offset: offset, bit: bit)
    }
}
