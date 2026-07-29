import Foundation

enum S7Area: UInt8, Codable, Sendable {
    case input = 0x81
    case output = 0x82
    case marker = 0x83
    case dataBlock = 0x84

    var shortName: String {
        switch self {
        case .input: "I"
        case .output: "Q"
        case .marker: "M"
        case .dataBlock: "DB"
        }
    }

    var isWritable: Bool {
        self == .marker || self == .dataBlock
    }
}

enum S7ValueType: String, CaseIterable, Codable, Identifiable, Sendable {
    case bool = "BOOL"
    case uint8 = "BYTE"
    case int16 = "INT"
    case uint16 = "WORD"
    case int32 = "DINT"
    case uint32 = "DWORD"
    case float32 = "REAL"

    var id: String { rawValue }

    var byteCount: Int {
        switch self {
        case .bool, .uint8: 1
        case .int16, .uint16: 2
        case .int32, .uint32, .float32: 4
        }
    }

    var requestTransportSize: UInt8 {
        switch self {
        case .bool: 0x01
        case .uint8: 0x02
        case .int16, .uint16: 0x04
        case .int32, .uint32: 0x06
        case .float32: 0x08
        }
    }

    var unitCount: UInt16 { 1 }

    var placeholder: String {
        switch self {
        case .bool: "true / false"
        case .uint8: "0...255 或 0xFF"
        case .int16: "-32768...32767"
        case .uint16: "0...65535 或 0xFFFF"
        case .int32: "-2147483648...2147483647"
        case .uint32: "0...4294967295"
        case .float32: "例如 12.5"
        }
    }
}

struct S7Address: Equatable, Sendable {
    let area: S7Area
    let dbNumber: UInt16
    let byteOffset: Int
    let bitOffset: Int?
    let original: String

    var bitAddress: Int {
        byteOffset * 8 + (bitOffset ?? 0)
    }

    static func parse(_ source: String, valueType: S7ValueType) throws -> S7Address {
        let text = source.uppercased().replacingOccurrences(of: " ", with: "")

        if let values = captures(pattern: #"^DB([0-9]+)\.DB([XBWD])([0-9]+)(?:\.([0-7]))?$"#, in: text) {
            guard let dbText = values[0], let offsetText = values[2],
                  let db = UInt16(dbText), let offset = Int(offsetText) else {
                throw LiteS7Error.invalidAddress("DB 编号或偏移超出范围")
            }
            let designator = values[1] ?? ""
            let bit = values[3].flatMap(Int.init)
            try validate(designator: designator, bit: bit, valueType: valueType)
            return S7Address(area: .dataBlock, dbNumber: db, byteOffset: offset, bitOffset: bit, original: text)
        }

        if let values = captures(pattern: #"^([MIQ])([BWD]?)([0-9]+)(?:\.([0-7]))?$"#, in: text) {
            guard let offsetText = values[2], let offset = Int(offsetText) else {
                throw LiteS7Error.invalidAddress("地址偏移超出范围")
            }
            let area: S7Area = switch values[0] ?? "" {
            case "M": .marker
            case "I": .input
            default: .output
            }
            let designator = values[1] ?? ""
            let bit = values[3].flatMap(Int.init)
            try validate(designator: designator, bit: bit, valueType: valueType)
            return S7Address(area: area, dbNumber: 0, byteOffset: offset, bitOffset: bit, original: text)
        }

        throw LiteS7Error.invalidAddress("支持 DB1.DBX0.0、DB1.DBB0、DB1.DBW0、DB1.DBD0、M0.0、MB0、MW0、MD0、I/Q 同类地址")
    }

    private static func validate(designator: String, bit: Int?, valueType: S7ValueType) throws {
        if valueType == .bool {
            guard bit != nil, designator == "X" || designator.isEmpty else {
                throw LiteS7Error.invalidAddress("BOOL 必须使用位地址，例如 DB1.DBX0.0 或 M0.0")
            }
        } else if bit != nil || designator == "X" {
            throw LiteS7Error.invalidAddress("非 BOOL 类型不能使用位地址")
        }
    }

    private static func captures(pattern: String, in source: String) -> [String?]? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(source.startIndex..<source.endIndex, in: source)
        guard let match = regex.firstMatch(in: source, range: range) else { return nil }
        return (1..<match.numberOfRanges).map { index in
            let captureRange = match.range(at: index)
            guard captureRange.location != NSNotFound,
                  let range = Range(captureRange, in: source) else { return nil }
            return String(source[range])
        }
    }
}

struct ConnectionConfiguration: Codable, Sendable {
    var host = "192.168.0.1"
    var port: UInt16 = 102
    var rack = 0
    var slot = 1
}

enum OperationKind: String, Codable, Sendable {
    case read = "读取"
    case write = "写入"
}

struct OperationHistory: Identifiable, Codable, Sendable {
    let id: UUID
    let timestamp: Date
    let kind: OperationKind
    let address: String
    let valueType: S7ValueType
    let value: String
    let success: Bool
    let elapsedMilliseconds: Int
}

struct ProtocolFrame: Identifiable, Sendable {
    enum Direction: String, Sendable {
        case transmit = "TX"
        case receive = "RX"
        case info = "INFO"
    }

    let id = UUID()
    let timestamp = Date()
    let direction: Direction
    let bytes: String
}

struct ReadDisplay: Sendable {
    let address: String
    let type: S7ValueType
    let value: String
    let hex: String
    let binary: String
    let elapsedMilliseconds: Int
}

enum ConnectionState: Equatable {
    case disconnected
    case connecting
    case connected
    case failed(String)

    var title: String {
        switch self {
        case .disconnected: "未连接"
        case .connecting: "连接中"
        case .connected: "已连接"
        case .failed: "连接异常"
        }
    }
}

enum LiteS7Error: LocalizedError, Sendable {
    case invalidAddress(String)
    case invalidValue(String)
    case notConnected
    case connection(String)
    case protocolError(String)
    case plcError(UInt8)
    case readOnlyArea

    var errorDescription: String? {
        switch self {
        case .invalidAddress(let reason): "地址无效：\(reason)"
        case .invalidValue(let reason): "写入值无效：\(reason)"
        case .notConnected: "尚未连接 PLC"
        case .connection(let reason): "连接失败：\(reason)"
        case .protocolError(let reason): "S7 协议错误：\(reason)"
        case .plcError(let code): "PLC 拒绝请求，返回码 0x\(String(format: "%02X", code))"
        case .readOnlyArea: "LiteS7 当前仅允许写入 DB 和 M 区域，I/Q 区域只读"
        }
    }
}

enum S7ValueCodec {
    static func decode(_ data: Data, as type: S7ValueType) throws -> String {
        guard data.count >= type.byteCount else {
            throw LiteS7Error.protocolError("返回数据长度不足")
        }
        let bytes = [UInt8](data.prefix(type.byteCount))
        switch type {
        case .bool:
            return bytes[0] == 0 ? "false" : "true"
        case .uint8:
            return String(bytes[0])
        case .int16:
            let raw = UInt16(bytes[0]) << 8 | UInt16(bytes[1])
            return String(Int16(bitPattern: raw))
        case .uint16:
            return String(UInt16(bytes[0]) << 8 | UInt16(bytes[1]))
        case .int32:
            let raw = uint32(bytes)
            return String(Int32(bitPattern: raw))
        case .uint32:
            return String(uint32(bytes))
        case .float32:
            let raw = uint32(bytes)
            return String(format: "%.7g", Float(bitPattern: raw))
        }
    }

    static func encode(_ source: String, as type: S7ValueType) throws -> Data {
        let value = source.trimmingCharacters(in: .whitespacesAndNewlines)
        switch type {
        case .bool:
            switch value.lowercased() {
            case "1", "true", "on", "yes": return Data([1])
            case "0", "false", "off", "no": return Data([0])
            default: throw LiteS7Error.invalidValue("BOOL 可填写 true/false 或 1/0")
            }
        case .uint8:
            guard let number = parseUnsigned(value), number <= UInt8.max else {
                throw LiteS7Error.invalidValue(type.placeholder)
            }
            return Data([UInt8(number)])
        case .int16:
            guard let number = Int16(value) else { throw LiteS7Error.invalidValue(type.placeholder) }
            return bigEndianData(UInt16(bitPattern: number))
        case .uint16:
            guard let number = parseUnsigned(value), number <= UInt16.max else {
                throw LiteS7Error.invalidValue(type.placeholder)
            }
            return bigEndianData(UInt16(number))
        case .int32:
            guard let number = Int32(value) else { throw LiteS7Error.invalidValue(type.placeholder) }
            return bigEndianData(UInt32(bitPattern: number))
        case .uint32:
            guard let number = parseUnsigned(value), number <= UInt32.max else {
                throw LiteS7Error.invalidValue(type.placeholder)
            }
            return bigEndianData(UInt32(number))
        case .float32:
            guard let number = Float(value), number.isFinite else { throw LiteS7Error.invalidValue(type.placeholder) }
            return bigEndianData(number.bitPattern)
        }
    }

    static func hex(_ data: Data) -> String {
        data.map { String(format: "%02X", $0) }.joined(separator: " ")
    }

    static func binary(_ data: Data) -> String {
        data.map { String($0, radix: 2).leftPadded(to: 8, with: "0") }.joined(separator: " ")
    }

    private static func parseUnsigned(_ text: String) -> UInt64? {
        if text.lowercased().hasPrefix("0x") {
            return UInt64(text.dropFirst(2), radix: 16)
        }
        return UInt64(text)
    }

    private static func uint32(_ bytes: [UInt8]) -> UInt32 {
        UInt32(bytes[0]) << 24 | UInt32(bytes[1]) << 16 | UInt32(bytes[2]) << 8 | UInt32(bytes[3])
    }

    private static func bigEndianData<T: FixedWidthInteger>(_ value: T) -> Data {
        var big = value.bigEndian
        return withUnsafeBytes(of: &big) { Data($0) }
    }
}

private extension String {
    func leftPadded(to length: Int, with character: Character) -> String {
        String(repeating: String(character), count: max(0, length - count)) + self
    }
}
