import Foundation

/// MBAP 头 + PDU 的编解码。所有函数都是纯函数，便于单元测试。
enum ModbusCodec {
    static let mbapHeaderLength = 7

    struct MBAPHeader: Equatable {
        var transactionId: UInt16
        var protocolId: UInt16
        var unitId: UInt8
        /// MBAP 长度字段（= unitId 1 字节 + PDU 长度）。
        var length: UInt16
    }

    // MARK: - MBAP

    static func buildMBAP(transactionId: UInt16, unitId: UInt8, pdu: Data) -> Data {
        var data = Data(capacity: mbapHeaderLength + pdu.count)
        data.appendBE(transactionId)
        data.appendBE(UInt16(0)) // 协议标识恒为 0
        data.appendBE(UInt16(pdu.count + 1))
        data.append(unitId)
        data.append(pdu)
        return data
    }

    /// 从缓冲区开头解析一帧。返回 (头, PDU, 整帧字节数)。
    static func parseFrame(from buffer: Data) throws -> (MBAPHeader, Data, Int) {
        guard buffer.count >= mbapHeaderLength else {
            throw ModbusError.malformedFrame("帧头不足")
        }
        let transactionId = buffer.readBEUInt16(at: 0)
        let protocolId = buffer.readBEUInt16(at: 2)
        let length = buffer.readBEUInt16(at: 4)
        let unitId = buffer[buffer.startIndex + 6]

        guard protocolId == 0 else { throw ModbusError.protocolIdMismatch }
        guard length >= 2, length <= 260 else {
            throw ModbusError.malformedFrame("非法长度字段 \(length)")
        }
        let total = Int(length) + 6
        guard buffer.count >= total else {
            throw ModbusError.malformedFrame("帧体不足")
        }
        let pdu = buffer.subdata(in: (buffer.startIndex + 7)..<(buffer.startIndex + total))
        let header = MBAPHeader(transactionId: transactionId, protocolId: protocolId,
                                unitId: unitId, length: length)
        return (header, pdu, total)
    }

    // MARK: - 请求构建

    static func readRequest(fc: UInt8, address: UInt16, count: UInt16) -> Data {
        var pdu = Data([fc])
        pdu.appendBE(address)
        pdu.appendBE(count)
        return pdu
    }

    static func writeSingleCoilRequest(address: UInt16, value: Bool) -> Data {
        var pdu = Data([ModbusFunction.writeSingleCoil.rawValue])
        pdu.appendBE(address)
        pdu.appendBE(value ? UInt16(0xFF00) : 0)
        return pdu
    }

    static func writeSingleRegisterRequest(address: UInt16, value: UInt16) -> Data {
        var pdu = Data([ModbusFunction.writeSingleRegister.rawValue])
        pdu.appendBE(address)
        pdu.appendBE(value)
        return pdu
    }

    static func writeMultipleCoilsRequest(address: UInt16, values: [Bool]) throws -> Data {
        guard !values.isEmpty, values.count <= ModbusLimits.maxWriteBits else {
            throw ModbusError.invalidRequest("线圈数量 1...\(ModbusLimits.maxWriteBits)")
        }
        var pdu = Data([ModbusFunction.writeMultipleCoils.rawValue])
        pdu.appendBE(address)
        pdu.appendBE(UInt16(values.count))
        pdu.append(UInt8((values.count + 7) / 8))
        pdu.append(bitsByteString(values))
        return pdu
    }

    static func writeMultipleRegistersRequest(address: UInt16, values: [UInt16]) throws -> Data {
        guard !values.isEmpty, values.count <= ModbusLimits.maxWriteRegisters else {
            throw ModbusError.invalidRequest("寄存器数量 1...\(ModbusLimits.maxWriteRegisters)")
        }
        var pdu = Data([ModbusFunction.writeMultipleRegisters.rawValue])
        pdu.appendBE(address)
        pdu.appendBE(UInt16(values.count))
        pdu.append(UInt8(values.count * 2))
        for v in values { pdu.appendBE(v) }
        return pdu
    }

    // MARK: - 响应解析

    /// 响应 PDU 首字节；异常响应 = 0x80 | fc。
    static func responseFunctionCode(_ pdu: Data) throws -> UInt8 {
        guard let fc = pdu.first else { throw ModbusError.invalidResponse("空 PDU") }
        return fc
    }

    static func isException(_ pdu: Data) -> Bool {
        guard let fc = pdu.first else { return false }
        return fc & 0x80 != 0
    }

    static func parseException(_ pdu: Data) throws -> ModbusException {
        guard pdu.count >= 2 else { throw ModbusError.invalidResponse("异常响应缺字节") }
        return ModbusException(code: pdu[pdu.startIndex + 1])
    }

    /// 解析读线圈 / 读离散输入响应（01/02），返回布尔数组。
    static func parseReadBitsResponse(_ pdu: Data) throws -> [Bool] {
        guard pdu.count >= 2 else { throw ModbusError.invalidResponse("响应过短") }
        let fc = pdu[pdu.startIndex]
        guard fc == ModbusFunction.readCoils.rawValue || fc == ModbusFunction.readDiscreteInputs.rawValue else {
            throw ModbusError.invalidResponse("功能码不匹配 0x\(String(fc, radix: 16))")
        }
        let byteCount = Int(pdu[pdu.startIndex + 1])
        guard pdu.count == byteCount + 2 else {
            throw ModbusError.invalidResponse("字节数不符")
        }
        var bits: [Bool] = []
        bits.reserveCapacity(byteCount * 8)
        for i in 0..<byteCount {
            let byte = pdu[pdu.startIndex + 2 + i]
            for bit in 0..<8 {
                bits.append((byte >> bit) & 1 == 1)
            }
        }
        return bits
    }

    /// 解析读寄存器响应（03/04），返回寄存器数组。
    static func parseReadRegistersResponse(_ pdu: Data) throws -> [UInt16] {
        guard pdu.count >= 2 else { throw ModbusError.invalidResponse("响应过短") }
        let fc = pdu[pdu.startIndex]
        guard fc == ModbusFunction.readHoldingRegisters.rawValue || fc == ModbusFunction.readInputRegisters.rawValue else {
            throw ModbusError.invalidResponse("功能码不匹配 0x\(String(fc, radix: 16))")
        }
        let byteCount = Int(pdu[pdu.startIndex + 1])
        guard byteCount % 2 == 0, pdu.count == byteCount + 2 else {
            throw ModbusError.invalidResponse("字节数不符")
        }
        var regs: [UInt16] = []
        regs.reserveCapacity(byteCount / 2)
        for i in stride(from: 0, to: byteCount, by: 2) {
            let hi = UInt16(pdu[pdu.startIndex + 2 + i])
            let lo = UInt16(pdu[pdu.startIndex + 3 + i])
            regs.append(hi << 8 | lo)
        }
        return regs
    }

    /// 校验写单点响应回显（05/06）。
    static func parseWriteSingleEcho(_ pdu: Data, expectedAddress: UInt16) throws {
        guard pdu.count == 5 else { throw ModbusError.invalidResponse("回显长度不符") }
        let address = pdu.readBEUInt16(at: 1)
        guard address == expectedAddress else {
            throw ModbusError.invalidResponse("回显地址不符")
        }
    }

    /// 校验写多点响应（0F/10）。
    static func parseWriteMultipleEcho(_ pdu: Data, expectedAddress: UInt16, expectedCount: Int) throws {
        guard pdu.count == 5 else { throw ModbusError.invalidResponse("回显长度不符") }
        let address = pdu.readBEUInt16(at: 1)
        let count = pdu.readBEUInt16(at: 3)
        guard address == expectedAddress, count == expectedCount else {
            throw ModbusError.invalidResponse("回显地址/数量不符")
        }
    }

    // MARK: - 位打包

    static func bitsByteString(_ bits: [Bool]) -> Data {
        var data = Data(count: (bits.count + 7) / 8)
        for (i, bit) in bits.enumerated() where bit {
            data[data.startIndex + i / 8] |= UInt8(1 << (i % 8))
        }
        return data
    }

    /// 把字节流按 LSB 在前的 Modbus 约定解成布尔数组，返回恰好 count 个。
    static func bits(from data: Data, count: Int) -> [Bool] {
        var bits: [Bool] = []
        bits.reserveCapacity(count)
        for i in 0..<count {
            let byte = data[data.startIndex + i / 8]
            bits.append((byte >> (i % 8)) & 1 == 1)
        }
        return bits
    }
}

// MARK: - Data 大端辅助

extension Data {
    mutating func appendBE(_ value: UInt16) {
        append(UInt8(value >> 8 & 0xFF))
        append(UInt8(value & 0xFF))
    }

    func readBEUInt16(at offset: Int) -> UInt16 {
        let a = UInt16(self[startIndex + offset])
        let b = UInt16(self[startIndex + offset + 1])
        return a << 8 | b
    }
}
