import Foundation

/// Modbus 数据区。rawValue 同时是 5 位编号的前缀数字（40001 → 4）。
enum ModbusArea: Int, Codable, CaseIterable, Identifiable {
    case coils = 0
    case discreteInputs = 1
    case inputRegisters = 3
    case holdingRegisters = 4

    var id: Int { rawValue }

    /// 5 位编号基数，如保持寄存器 40001。
    var fiveDigitBase: Int { rawValue * 10000 + 1 }

    var isRegisterArea: Bool { self == .inputRegisters || self == .holdingRegisters }

    /// 读功能码。
    var readFunctionCode: UInt8 {
        switch self {
        case .coils: return ModbusFunction.readCoils.rawValue
        case .discreteInputs: return ModbusFunction.readDiscreteInputs.rawValue
        case .holdingRegisters: return ModbusFunction.readHoldingRegisters.rawValue
        case .inputRegisters: return ModbusFunction.readInputRegisters.rawValue
        }
    }

    var name: String {
        switch self {
        case .coils: return "线圈 0x"
        case .discreteInputs: return "离散输入 1x"
        case .inputRegisters: return "输入寄存器 3x"
        case .holdingRegisters: return "保持寄存器 4x"
        }
    }

    var shortName: String {
        switch self {
        case .coils: return "0x 线圈"
        case .discreteInputs: return "1x 离散"
        case .inputRegisters: return "3x 输入"
        case .holdingRegisters: return "4x 保持"
        }
    }

    var symbol: String {
        switch self {
        case .coils: return "0x"
        case .discreteInputs: return "1x"
        case .inputRegisters: return "3x"
        case .holdingRegisters: return "4x"
        }
    }

    /// 把 0 基协议地址转回 5 位编号（超过 9999 时用 6 位编号）。
    func displayAddress(offset: Int) -> Int {
        if offset <= 9998 {
            return fiveDigitBase + offset
        }
        return rawValue * 100000 + 1 + offset
    }
}

/// 功能码（本工具支持的主站请求 / 从站响应集合）。
enum ModbusFunction: UInt8 {
    case readCoils = 0x01
    case readDiscreteInputs = 0x02
    case readHoldingRegisters = 0x03
    case readInputRegisters = 0x04
    case writeSingleCoil = 0x05
    case writeSingleRegister = 0x06
    case writeMultipleCoils = 0x0F
    case writeMultipleRegisters = 0x10

    var name: String {
        switch self {
        case .readCoils: return "读线圈 (01)"
        case .readDiscreteInputs: return "读离散输入 (02)"
        case .readHoldingRegisters: return "读保持寄存器 (03)"
        case .readInputRegisters: return "读输入寄存器 (04)"
        case .writeSingleCoil: return "写单线圈 (05)"
        case .writeSingleRegister: return "写单寄存器 (06)"
        case .writeMultipleCoils: return "写多线圈 (0F)"
        case .writeMultipleRegisters: return "写多寄存器 (10)"
        }
    }
}

/// Modbus 异常码。
struct ModbusException: Error, Equatable, CustomStringConvertible {
    let code: UInt8

    init(code: UInt8) { self.code = code }

    var name: String {
        switch code {
        case 0x01: return "非法功能"
        case 0x02: return "非法数据地址"
        case 0x03: return "非法数据值"
        case 0x04: return "从站设备故障"
        case 0x05: return "确认"
        case 0x06: return "从站设备忙"
        case 0x08: return "存储奇偶校验错误"
        case 0x0A: return "网关路径不可用"
        case 0x0B: return "网关目标无响应"
        default: return "异常 \(code)"
        }
    }

    var description: String { "异常 0x\(String(code, radix: 16)) \(name)" }

    static let illegalFunction = ModbusException(code: 0x01)
    static let illegalDataAddress = ModbusException(code: 0x02)
    static let illegalDataValue = ModbusException(code: 0x03)
    static let serverDeviceFailure = ModbusException(code: 0x04)
}

/// 协议规定的数量上限。
enum ModbusLimits {
    static let maxReadBits = 2000
    static let maxReadRegisters = 125
    static let maxWriteBits = 1968
    static let maxWriteRegisters = 123
    static let addressSpace = 65536
}

/// 通信层错误。
enum ModbusError: Error, Equatable {
    case notConnected
    case connectFailed(String)
    case timeout
    case connectionClosed
    case malformedFrame(String)
    case protocolIdMismatch
    case invalidResponse(String)
    case invalidRequest(String)
    case bindFailed(String)
    case exception(ModbusException)
}
