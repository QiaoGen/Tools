import Foundation
import Network

/// Modbus TCP 主站连接。基于 Network.framework，支持事务 ID 匹配、超时与多请求排队。
final class ModbusTCPClient {
    struct Pending {
        let continuation: CheckedContinuation<Data, Error>
        let timeoutItem: DispatchWorkItem
    }

    private let queue = DispatchQueue(label: "litemodbus.master.connection")
    private let stateLock = NSLock()
    private var connection: NWConnection?
    private var receiveBuffer = Data()
    private var pending: [UInt16: Pending] = [:]
    private var nextTransactionId: UInt16 = 0
    private var rxCount = 0

    /// 通信事件回调（在后台队列调用）：direction, data, error。
    var onFrame: ((TrafficDirection, Data, Error?) -> Void)?

    // MARK: - 连接管理

    var isConnected: Bool {
        stateLock.lock(); defer { stateLock.unlock() }
        return connection?.state == .ready
    }

    func connect(host: String, port: UInt16, timeout: TimeInterval) async throws {
        let endpointHost = NWEndpoint.Host(host)
        let portValue = NWEndpoint.Port(rawValue: port) ?? 502
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            let conn = NWConnection(host: endpointHost, port: portValue, using: .tcp)
            var finished = false
            let timeoutItem = DispatchWorkItem { [weak conn] in
                guard !finished else { return }
                finished = true
                conn?.cancel()
                cont.resume(throwing: ModbusError.timeout)
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: timeoutItem)
            conn.stateUpdateHandler = { [weak self] state in
                self?.queue.async { [weak self] in
                    switch state {
                    case .ready:
                        guard !finished else { return }
                        finished = true
                        timeoutItem.cancel()
                        self?.connection = conn
                        self?.receiveBuffer.removeAll()
                        self?.startReceiveLoop()
                        cont.resume()
                    case .failed(let error):
                        guard !finished else { return }
                        finished = true
                        timeoutItem.cancel()
                        cont.resume(throwing: ModbusError.connectFailed(error.localizedDescription))
                    case .cancelled:
                        guard !finished else { return }
                        finished = true
                        timeoutItem.cancel()
                        cont.resume(throwing: ModbusError.connectionClosed)
                    default:
                        break
                    }
                }
            }
            conn.start(queue: queue)
        }
    }

    func disconnect() {
        queue.async { [self] in
            connection?.cancel()
            connection = nil
            failAllPending(ModbusError.connectionClosed)
        }
    }

    // MARK: - 事务

    /// 发送 PDU 并等待同事务 ID 的响应 PDU。
    func execute(unitId: UInt8, pdu: Data, timeout: TimeInterval) async throws -> Data {
        let response: Data = try await withCheckedThrowingContinuation { cont in
            queue.async { [self] in
                guard let conn = connection, conn.state == .ready else {
                    cont.resume(throwing: ModbusError.notConnected)
                    return
                }
                nextTransactionId &+= 1
                let tid = nextTransactionId
                let data = ModbusCodec.buildMBAP(transactionId: tid, unitId: unitId, pdu: pdu)

                let timeoutItem = DispatchWorkItem { [weak self] in
                    self?.failPending(tid, ModbusError.timeout)
                }
                stateLock.lock()
                pending[tid] = Pending(continuation: cont, timeoutItem: timeoutItem)
                stateLock.unlock()
                DispatchQueue.global().asyncAfter(
                    deadline: .now() + timeout,
                    execute: timeoutItem
                )

                onFrame?(.tx, data, nil)
                conn.send(content: data, completion: .contentProcessed { [weak self] error in
                    if let error {
                        self?.queue.async { [weak self] in
                            self?.failPending(tid, error)
                        }
                    }
                })
            }
        }
        return response
    }

    // MARK: - 接收循环

    private func startReceiveLoop() {
        guard let conn = connection else { return }
        conn.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            self.queue.async { [weak self] in
                guard let self else { return }
                if let data, !data.isEmpty {
                    receiveBuffer.append(data)
                    drainBuffer()
                }
                if isComplete || error != nil {
                    failAllPending(ModbusError.connectionClosed)
                    return
                }
                startReceiveLoop()
            }
        }
    }

    private func drainBuffer() {
        while true {
            guard receiveBuffer.count >= ModbusCodec.mbapHeaderLength else { return }
            let length = receiveBuffer.readBEUInt16(at: 4)
            let total = Int(length) + 6
            guard receiveBuffer.count >= total else { return }
            guard let (header, pdu, consumed) = try? ModbusCodec.parseFrame(from: receiveBuffer) else {
                failAllPending(ModbusError.malformedFrame("响应帧解析失败"))
                receiveBuffer.removeAll()
                return
            }
            receiveBuffer.removeFirst(consumed)
            rxCount &+= 1
            onFrame?(.rx, ModbusCodec.buildMBAP(transactionId: header.transactionId,
                                                unitId: header.unitId, pdu: pdu), nil)

            stateLock.lock()
            let waiting = pending.removeValue(forKey: header.transactionId)
            stateLock.unlock()
            if let waiting {
                waiting.timeoutItem.cancel()
                waiting.continuation.resume(returning: pdu)
            }
        }
    }

    private func failPending(_ tid: UInt16, _ error: Error) {
        stateLock.lock()
        let waiting = pending.removeValue(forKey: tid)
        stateLock.unlock()
        waiting?.timeoutItem.cancel()
        waiting?.continuation.resume(throwing: error)
    }

    private func failAllPending(_ error: Error) {
        stateLock.lock()
        let all = pending
        pending.removeAll()
        stateLock.unlock()
        for waiting in all.values {
            waiting.timeoutItem.cancel()
            waiting.continuation.resume(throwing: error)
        }
    }
}

// MARK: - 高层 API

extension ModbusTCPClient {
    private func runRequest(unitId: UInt8, pdu: Data, timeout: TimeInterval) async throws -> Data {
        let response = try await execute(unitId: unitId, pdu: pdu, timeout: timeout)
        if ModbusCodec.isException(response) {
            throw ModbusError.exception(try ModbusCodec.parseException(response))
        }
        return response
    }

    func readBits(area: ModbusArea, address: UInt16, count: Int,
                  unitId: UInt8, timeout: TimeInterval) async throws -> [Bool] {
        guard count >= 1, count <= ModbusLimits.maxReadBits else {
            throw ModbusError.invalidRequest("位数量 1...\(ModbusLimits.maxReadBits)")
        }
        let pdu = ModbusCodec.readRequest(fc: area.readFunctionCode,
                                          address: address, count: UInt16(count))
        let response = try await runRequest(unitId: unitId, pdu: pdu, timeout: timeout)
        let allBits = try ModbusCodec.parseReadBitsResponse(response)
        return Array(allBits.prefix(count))
    }

    func readRegisters(area: ModbusArea, address: UInt16, count: Int,
                       unitId: UInt8, timeout: TimeInterval) async throws -> [UInt16] {
        guard count >= 1, count <= ModbusLimits.maxReadRegisters else {
            throw ModbusError.invalidRequest("寄存器数量 1...\(ModbusLimits.maxReadRegisters)")
        }
        let pdu = ModbusCodec.readRequest(fc: area.readFunctionCode,
                                          address: address, count: UInt16(count))
        let response = try await runRequest(unitId: unitId, pdu: pdu, timeout: timeout)
        return try ModbusCodec.parseReadRegistersResponse(response)
    }

    func writeSingleCoil(address: UInt16, value: Bool,
                         unitId: UInt8, timeout: TimeInterval) async throws {
        let pdu = ModbusCodec.writeSingleCoilRequest(address: address, value: value)
        let response = try await runRequest(unitId: unitId, pdu: pdu, timeout: timeout)
        try ModbusCodec.parseWriteSingleEcho(response, expectedAddress: address)
    }

    func writeSingleRegister(address: UInt16, value: UInt16,
                             unitId: UInt8, timeout: TimeInterval) async throws {
        let pdu = ModbusCodec.writeSingleRegisterRequest(address: address, value: value)
        let response = try await runRequest(unitId: unitId, pdu: pdu, timeout: timeout)
        try ModbusCodec.parseWriteSingleEcho(response, expectedAddress: address)
    }

    func writeMultipleCoils(address: UInt16, values: [Bool],
                            unitId: UInt8, timeout: TimeInterval) async throws {
        let pdu = try ModbusCodec.writeMultipleCoilsRequest(address: address, values: values)
        let response = try await runRequest(unitId: unitId, pdu: pdu, timeout: timeout)
        try ModbusCodec.parseWriteMultipleEcho(response, expectedAddress: address, expectedCount: values.count)
    }

    func writeMultipleRegisters(address: UInt16, values: [UInt16],
                                unitId: UInt8, timeout: TimeInterval) async throws {
        let pdu = try ModbusCodec.writeMultipleRegistersRequest(address: address, values: values)
        let response = try await runRequest(unitId: unitId, pdu: pdu, timeout: timeout)
        try ModbusCodec.parseWriteMultipleEcho(response, expectedAddress: address, expectedCount: values.count)
    }
}

/// 报文方向。
enum TrafficDirection: String, Codable {
    case tx
    case rx
}
