import Foundation
import Network

struct S7ExchangeResult: Sendable {
    let data: Data
    let frames: [ProtocolFrame]
}

actor S7Client {
    private var connection: NWConnection?
    private let queue = DispatchQueue(label: "LiteS7.Network")
    private var pduReference: UInt16 = 1

    func connect(configuration: ConnectionConfiguration) async throws -> [ProtocolFrame] {
        disconnect()

        guard let port = NWEndpoint.Port(rawValue: configuration.port) else {
            throw LiteS7Error.connection("端口无效")
        }

        let tcpOptions = NWProtocolTCP.Options()
        tcpOptions.connectionTimeout = 5
        let parameters = NWParameters(tls: nil, tcp: tcpOptions)
        let connection = NWConnection(host: NWEndpoint.Host(configuration.host), port: port, using: parameters)
        self.connection = connection

        do {
            try await waitUntilReady(connection)

            let cotp = makeCOTPConnectionRequest(rack: configuration.rack, slot: configuration.slot)
            let cotpReply = try await exchange(cotp)
            try validateCOTPConfirmation(cotpReply)

            let setup = makeSetupCommunicationRequest()
            let setupReply = try await exchange(setup)
            try validateS7Response(setupReply)

            return [
                ProtocolFrame(direction: .transmit, bytes: S7ValueCodec.hex(cotp)),
                ProtocolFrame(direction: .receive, bytes: S7ValueCodec.hex(cotpReply)),
                ProtocolFrame(direction: .transmit, bytes: S7ValueCodec.hex(setup)),
                ProtocolFrame(direction: .receive, bytes: S7ValueCodec.hex(setupReply))
            ]
        } catch {
            connection.cancel()
            self.connection = nil
            if let error = error as? LiteS7Error { throw error }
            throw LiteS7Error.connection(error.localizedDescription)
        }
    }

    func disconnect() {
        connection?.cancel()
        connection = nil
    }

    func read(address: S7Address, valueType: S7ValueType) async throws -> S7ExchangeResult {
        let request = makeReadRequest(address: address, valueType: valueType)
        let reply = try await exchange(request)
        let data = try parseReadResponse(reply)
        return S7ExchangeResult(
            data: data,
            frames: [
                ProtocolFrame(direction: .transmit, bytes: S7ValueCodec.hex(request)),
                ProtocolFrame(direction: .receive, bytes: S7ValueCodec.hex(reply))
            ]
        )
    }

    func write(address: S7Address, valueType: S7ValueType, data: Data) async throws -> S7ExchangeResult {
        guard address.area.isWritable else { throw LiteS7Error.readOnlyArea }
        let request = makeWriteRequest(address: address, valueType: valueType, data: data)
        let reply = try await exchange(request)
        try parseWriteResponse(reply)
        return S7ExchangeResult(
            data: data,
            frames: [
                ProtocolFrame(direction: .transmit, bytes: S7ValueCodec.hex(request)),
                ProtocolFrame(direction: .receive, bytes: S7ValueCodec.hex(reply))
            ]
        )
    }

    private func waitUntilReady(_ connection: NWConnection) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    connection.stateUpdateHandler = nil
                    continuation.resume()
                case .failed(let error):
                    connection.stateUpdateHandler = nil
                    continuation.resume(throwing: LiteS7Error.connection(error.localizedDescription))
                case .cancelled:
                    connection.stateUpdateHandler = nil
                    continuation.resume(throwing: LiteS7Error.connection("连接已取消"))
                default:
                    break
                }
            }
            connection.start(queue: queue)
        }
    }

    private func exchange(_ packet: Data) async throws -> Data {
        guard let connection else { throw LiteS7Error.notConnected }
        try await send(packet, on: connection)
        return try await receivePacket(on: connection)
    }

    private func send(_ data: Data, on connection: NWConnection) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.send(content: data, completion: .contentProcessed { error in
                if let error {
                    continuation.resume(throwing: LiteS7Error.connection(error.localizedDescription))
                } else {
                    continuation.resume()
                }
            })
        }
    }

    private func receivePacket(on connection: NWConnection) async throws -> Data {
        let header = try await receiveExactly(4, on: connection)
        guard header.count == 4, header[0] == 0x03, header[1] == 0x00 else {
            throw LiteS7Error.protocolError("TPKT 报文头无效")
        }
        let length = Int(header[2]) << 8 | Int(header[3])
        guard length >= 7, length <= 65_535 else {
            throw LiteS7Error.protocolError("TPKT 报文长度无效")
        }
        let body = try await receiveExactly(length - 4, on: connection)
        return header + body
    }

    private func receiveExactly(_ count: Int, on connection: NWConnection) async throws -> Data {
        var result = Data()
        while result.count < count {
            let remaining = count - result.count
            let chunk: Data = try await withCheckedThrowingContinuation { continuation in
                connection.receive(minimumIncompleteLength: 1, maximumLength: remaining) { data, _, isComplete, error in
                    if let error {
                        continuation.resume(throwing: LiteS7Error.connection(error.localizedDescription))
                    } else if let data, !data.isEmpty {
                        continuation.resume(returning: data)
                    } else if isComplete {
                        continuation.resume(throwing: LiteS7Error.connection("PLC 已关闭连接"))
                    } else {
                        continuation.resume(throwing: LiteS7Error.connection("未收到完整数据"))
                    }
                }
            }
            result.append(chunk)
        }
        return result
    }

    func makeCOTPConnectionRequest(rack: Int, slot: Int) -> Data {
        let rackSlot = UInt8(clamping: rack * 0x20 + slot)
        return Data([
            0x03, 0x00, 0x00, 0x16,
            0x11, 0xE0, 0x00, 0x00, 0x00, 0x01, 0x00,
            0xC1, 0x02, 0x01, 0x00,
            0xC2, 0x02, 0x01, rackSlot,
            0xC0, 0x01, 0x0A
        ])
    }

    func makeSetupCommunicationRequest() -> Data {
        let reference = nextReference()
        var data = Data([0x03, 0x00, 0x00, 0x19, 0x02, 0xF0, 0x80, 0x32, 0x01, 0x00, 0x00])
        data.appendUInt16(reference)
        data.append(contentsOf: [0x00, 0x08, 0x00, 0x00, 0xF0, 0x00, 0x00, 0x01, 0x00, 0x01, 0x01, 0xE0])
        return data
    }

    func makeReadRequest(address: S7Address, valueType: S7ValueType) -> Data {
        let reference = nextReference()
        var data = Data([0x03, 0x00, 0x00, 0x1F, 0x02, 0xF0, 0x80, 0x32, 0x01, 0x00, 0x00])
        data.appendUInt16(reference)
        data.append(contentsOf: [0x00, 0x0E, 0x00, 0x00, 0x04, 0x01, 0x12, 0x0A, 0x10, valueType.requestTransportSize])
        data.appendUInt16(valueType.unitCount)
        data.appendUInt16(address.dbNumber)
        data.append(address.area.rawValue)
        data.appendUInt24(address.bitAddress)
        return data
    }

    func makeWriteRequest(address: S7Address, valueType: S7ValueType, data payload: Data) -> Data {
        let reference = nextReference()
        let dataLength = 4 + payload.count
        let totalLength = 7 + 10 + 14 + dataLength
        var data = Data([0x03, 0x00])
        data.appendUInt16(UInt16(totalLength))
        data.append(contentsOf: [0x02, 0xF0, 0x80, 0x32, 0x01, 0x00, 0x00])
        data.appendUInt16(reference)
        data.appendUInt16(14)
        data.appendUInt16(UInt16(dataLength))
        data.append(contentsOf: [0x05, 0x01, 0x12, 0x0A, 0x10, valueType.requestTransportSize])
        data.appendUInt16(valueType.unitCount)
        data.appendUInt16(address.dbNumber)
        data.append(address.area.rawValue)
        data.appendUInt24(address.bitAddress)
        data.append(0x00)
        data.append(valueType == .bool ? 0x03 : 0x04)
        data.appendUInt16(valueType == .bool ? 1 : UInt16(payload.count * 8))
        data.append(payload)
        return data
    }

    private func validateCOTPConfirmation(_ packet: Data) throws {
        guard packet.count >= 7, packet[5] == 0xD0 else {
            throw LiteS7Error.protocolError("PLC 未确认 COTP 连接")
        }
    }

    private func validateS7Response(_ packet: Data) throws {
        let s7 = try s7Payload(packet)
        guard s7.count >= 12, s7[0] == 0x32, s7[1] == 0x03 else {
            throw LiteS7Error.protocolError("S7 握手响应无效")
        }
        guard s7[10] == 0, s7[11] == 0 else {
            throw LiteS7Error.protocolError("S7 握手被拒绝 (\(s7[10]), \(s7[11]))")
        }
    }

    private func parseReadResponse(_ packet: Data) throws -> Data {
        let s7 = try s7Payload(packet)
        guard s7.count >= 16, s7[0] == 0x32, s7[1] == 0x03 else {
            throw LiteS7Error.protocolError("读取响应格式无效")
        }
        guard s7[10] == 0, s7[11] == 0 else {
            throw LiteS7Error.protocolError("读取响应错误 (\(s7[10]), \(s7[11]))")
        }
        let parameterLength = Int(s7[6]) << 8 | Int(s7[7])
        let dataStart = 12 + parameterLength
        guard dataStart + 4 <= s7.count else { throw LiteS7Error.protocolError("读取响应被截断") }
        let returnCode = s7[dataStart]
        guard returnCode == 0xFF else { throw LiteS7Error.plcError(returnCode) }
        let transport = s7[dataStart + 1]
        let rawLength = Int(s7[dataStart + 2]) << 8 | Int(s7[dataStart + 3])
        let byteLength = transport == 0x09 ? rawLength : (rawLength + 7) / 8
        guard dataStart + 4 + byteLength <= s7.count else {
            throw LiteS7Error.protocolError("读取数据长度不匹配")
        }
        return s7.subdata(in: (dataStart + 4)..<(dataStart + 4 + byteLength))
    }

    private func parseWriteResponse(_ packet: Data) throws {
        let s7 = try s7Payload(packet)
        guard s7.count >= 15, s7[0] == 0x32, s7[1] == 0x03 else {
            throw LiteS7Error.protocolError("写入响应格式无效")
        }
        guard s7[10] == 0, s7[11] == 0 else {
            throw LiteS7Error.protocolError("写入响应错误 (\(s7[10]), \(s7[11]))")
        }
        let parameterLength = Int(s7[6]) << 8 | Int(s7[7])
        let dataStart = 12 + parameterLength
        guard dataStart < s7.count else { throw LiteS7Error.protocolError("写入响应被截断") }
        let returnCode = s7[dataStart]
        guard returnCode == 0xFF else { throw LiteS7Error.plcError(returnCode) }
    }

    private func s7Payload(_ packet: Data) throws -> Data {
        guard packet.count >= 8, packet[4] == 0x02, packet[5] == 0xF0 else {
            throw LiteS7Error.protocolError("COTP 数据报文无效")
        }
        return packet.subdata(in: 7..<packet.count)
    }

    private func nextReference() -> UInt16 {
        defer { pduReference = pduReference == UInt16.max ? 1 : pduReference + 1 }
        return pduReference
    }
}

private extension Data {
    mutating func appendUInt16(_ value: UInt16) {
        append(UInt8((value >> 8) & 0xFF))
        append(UInt8(value & 0xFF))
    }

    mutating func appendUInt24(_ value: Int) {
        append(UInt8((value >> 16) & 0xFF))
        append(UInt8((value >> 8) & 0xFF))
        append(UInt8(value & 0xFF))
    }
}
