import Foundation
import Network

/// 从站内存：4 个数据区，各 65536 单元。线程安全。
final class SlaveDataStore {
    private let lock = NSLock()
    private var coils = [Bool](repeating: false, count: ModbusLimits.addressSpace)
    private var discrete = [Bool](repeating: false, count: ModbusLimits.addressSpace)
    private var holding = [UInt16](repeating: 0, count: ModbusLimits.addressSpace)
    private var input = [UInt16](repeating: 0, count: ModbusLimits.addressSpace)

    /// 任意写入（含主站经网络写入）后回调，UI 节流后刷新。
    var onWrite: (() -> Void)?

    func readBits(area: ModbusArea, offset: Int, count: Int) -> [Bool] {
        lock.lock(); defer { lock.unlock() }
        let source = area == .coils ? coils : discrete
        return (0..<count).map { source[offset + $0] }
    }

    func readRegisters(area: ModbusArea, offset: Int, count: Int) -> [UInt16] {
        lock.lock(); defer { lock.unlock() }
        let source = area == .holdingRegisters ? holding : input
        return (0..<count).map { source[offset + $0] }
    }

    func writeBits(area: ModbusArea, offset: Int, values: [Bool]) {
        lock.lock()
        if area == .coils {
            for (i, v) in values.enumerated() { coils[offset + i] = v }
        } else {
            for (i, v) in values.enumerated() { discrete[offset + i] = v }
        }
        lock.unlock()
        onWrite?()
    }

    func writeRegisters(area: ModbusArea, offset: Int, values: [UInt16]) {
        lock.lock()
        if area == .holdingRegisters {
            for (i, v) in values.enumerated() { holding[offset + i] = v }
        } else {
            for (i, v) in values.enumerated() { input[offset + i] = v }
        }
        lock.unlock()
        onWrite?()
    }

    func setBit(area: ModbusArea, offset: Int, bit: Int, value: Bool) {
        lock.lock()
        if area == .coils {
            coils[offset] = value
        } else {
            let mask = UInt16(1) << UInt16(bit)
            if value { holding[offset] |= mask } else { holding[offset] &= ~mask }
        }
        lock.unlock()
        onWrite?()
    }

    func setRegisterBit(area: ModbusArea, offset: Int, bit: Int, value: Bool) {
        lock.lock()
        let mask = UInt16(1) << UInt16(bit)
        if area == .holdingRegisters {
            if value { holding[offset] |= mask } else { holding[offset] &= ~mask }
        } else {
            if value { input[offset] |= mask } else { input[offset] &= ~mask }
        }
        lock.unlock()
        onWrite?()
    }

    func value(area: ModbusArea, offset: Int) -> UInt16 {
        lock.lock(); defer { lock.unlock() }
        switch area {
        case .coils: return coils[offset] ? 1 : 0
        case .discreteInputs: return discrete[offset] ? 1 : 0
        case .inputRegisters: return input[offset]
        case .holdingRegisters: return holding[offset]
        }
    }

    func bitValue(area: ModbusArea, offset: Int, bit: Int) -> Bool {
        value(area: area, offset: offset) >> UInt16(bit) & 1 == 1
    }

    // MARK: - 快照（JSON 存取）

    struct SparseEntry: Codable, Equatable {
        var area: Int
        var address: Int
        var value: Int
    }

    func snapshot() -> [SparseEntry] {
        lock.lock(); defer { lock.unlock() }
        var entries: [SparseEntry] = []
        for (i, v) in coils.enumerated() where v {
            entries.append(SparseEntry(area: ModbusArea.coils.rawValue, address: i, value: 1))
        }
        for (i, v) in discrete.enumerated() where v {
            entries.append(SparseEntry(area: ModbusArea.discreteInputs.rawValue, address: i, value: 1))
        }
        for area in [ModbusArea.inputRegisters, .holdingRegisters] {
            let source = area == .inputRegisters ? input : holding
            for (i, v) in source.enumerated() where v != 0 {
                entries.append(SparseEntry(area: area.rawValue, address: i, value: Int(v)))
            }
        }
        return entries
    }

    func restore(from entries: [SparseEntry]) {
        lock.lock()
        coils = [Bool](repeating: false, count: ModbusLimits.addressSpace)
        discrete = [Bool](repeating: false, count: ModbusLimits.addressSpace)
        holding = [UInt16](repeating: 0, count: ModbusLimits.addressSpace)
        input = [UInt16](repeating: 0, count: ModbusLimits.addressSpace)
        for e in entries where e.address >= 0 && e.address < ModbusLimits.addressSpace {
            switch ModbusArea(rawValue: e.area) {
            case .coils: coils[e.address] = e.value != 0
            case .discreteInputs: discrete[e.address] = e.value != 0
            case .inputRegisters: input[e.address] = UInt16(clamping: e.value)
            case .holdingRegisters: holding[e.address] = UInt16(clamping: e.value)
            case .none: break
            }
        }
        lock.unlock()
        onWrite?()
    }
}

/// 从站统计计数器（线程安全）。
final class SlaveStats {
    private let lock = NSLock()
    private var _requests = 0
    private var _exceptions = 0
    private var _connectionsTotal = 0
    private var _perFunction: [UInt8: Int] = [:]
    private var windowStart = Date()
    private var windowCount = 0
    private(set) var ratePerSecond: Double = 0

    var requests: Int { lock.lock(); defer { lock.unlock() }; return _requests }
    var exceptions: Int { lock.lock(); defer { lock.unlock() }; return _exceptions }
    var connectionsTotal: Int { lock.lock(); defer { lock.unlock() }; return _connectionsTotal }

    func recordRequest(fc: UInt8, isException: Bool) {
        lock.lock()
        _requests += 1
        if isException { _exceptions += 1 }
        _perFunction[fc, default: 0] += 1
        windowCount += 1
        let elapsed = Date().timeIntervalSince(windowStart)
        if elapsed >= 1 {
            ratePerSecond = Double(windowCount) / elapsed
            windowStart = Date()
            windowCount = 0
        }
        lock.unlock()
    }

    func recordConnection() {
        lock.lock(); _connectionsTotal += 1; lock.unlock()
    }

    func functionCounts() -> [(fc: UInt8, count: Int)] {
        lock.lock(); defer { lock.unlock() }
        return _perFunction.map { ($0.key, $0.value) }.sorted { $0.1 > $1.1 }
    }

    func reset() {
        lock.lock()
        _requests = 0; _exceptions = 0; _perFunction = [:]
        ratePerSecond = 0; windowCount = 0; windowStart = Date()
        lock.unlock()
    }
}

/// Modbus TCP 从站（服务器）。监听端口，对每个连接应答请求。
final class ModbusTCPSlave {
    let store = SlaveDataStore()
    let stats = SlaveStats()

    /// 是否响应任意 Unit ID；否则只响应 unitIds 集合。
    var respondToAllUnits = true
    var unitIds: Set<UInt8> = [1]
    /// 模拟响应延迟（毫秒），用于调试主站超时。
    var responseDelayMs: Int = 0

    /// 请求日志回调（后台队列）：方向、原始帧、错误、摘要。
    var onFrame: ((TrafficDirection, Data, Error?, String) -> Void)?

    private let queue = DispatchQueue(label: "litemodbus.slave.server")
    private var listener: NWListener?
    private let connectionsLock = NSLock()
    private var connections: [NWConnection] = []
    private(set) var activeConnections = 0

    var isRunning: Bool { listener != nil }
    var port: UInt16 = 1502

    func start(port: UInt16) throws {
        stop()
        self.port = port
        guard let nwPort = NWEndpoint.Port(rawValue: port) else {
            throw ModbusError.bindFailed("端口无效")
        }
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        guard let nwListener = try? NWListener(using: params, on: nwPort) else {
            throw ModbusError.bindFailed("端口 \(port) 监听失败（502 以下端口需要管理员权限）")
        }
        nwListener.stateUpdateHandler = { [weak self] state in
            if case .failed = state {
                self?.stop()
            }
        }
        nwListener.newConnectionHandler = { [weak self] connection in
            self?.accept(connection)
        }
        nwListener.start(queue: queue)
        listener = nwListener
    }

    func stop() {
        listener?.cancel()
        listener = nil
        connectionsLock.lock()
        let all = connections
        connections.removeAll()
        connectionsLock.unlock()
        all.forEach { $0.cancel() }
        queue.sync { activeConnections = 0 }
    }

    private func accept(_ connection: NWConnection) {
        connectionsLock.lock()
        connections.append(connection)
        connectionsLock.unlock()
        stats.recordConnection()
        queue.async { self.activeConnections += 1 }
        connection.start(queue: queue)
        receiveLoop(connection, buffer: Data())
    }

    private func receiveLoop(_ connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            var buf = buffer
            if let data, !data.isEmpty { buf.append(data) }
            if isComplete || error != nil {
                self.drop(connection)
                return
            }
            buf = self.drain(buffer: buf, connection: connection)
            self.receiveLoop(connection, buffer: buf)
        }
    }

    private func drop(_ connection: NWConnection) {
        connection.cancel()
        connectionsLock.lock()
        connections.removeAll { $0 === connection }
        connectionsLock.unlock()
        queue.async { self.activeConnections = max(0, self.activeConnections - 1) }
    }

    /// 从缓冲区解析并应答所有完整帧，返回剩余字节。
    private func drain(buffer: Data, connection: NWConnection) -> Data {
        var buf = buffer
        while buf.count >= ModbusCodec.mbapHeaderLength {
            guard let (header, pdu, consumed) = try? ModbusCodec.parseFrame(from: buf) else {
                return Data() // 帧损坏，丢弃缓冲
            }
            if buf.count < consumed { break }
            buf.removeFirst(consumed)

            let requestPDU = pdu
            let unit = header.unitId
            let tid = header.transactionId
            if responseDelayMs > 0 {
                let delay = UInt64(responseDelayMs) * 1_000_000
                DispatchQueue.global().asyncAfter(deadline: .now() + .nanoseconds(Int(delay))) { [weak self] in
                    self?.handle(pdu: requestPDU, unitId: unit, transactionId: tid, connection: connection)
                }
            } else {
                handle(pdu: requestPDU, unitId: unit, transactionId: tid, connection: connection)
            }
        }
        return buf
    }

    private func handle(pdu: Data, unitId: UInt8, transactionId: UInt16, connection: NWConnection) {
        guard let fcByte = pdu.first else { return }

        // Unit ID 过滤：不匹配则静默丢弃（协议惯例）。
        if !respondToAllUnits, !unitIds.contains(unitId), unitId != 0, unitId != 0xFF {
            return
        }

        let (response, isException, summary): (Data, Bool, String)
        do {
            let r = try execute(pdu: pdu)
            response = r.pdu
            isException = r.isException
            summary = r.summary
        } catch let e as ModbusException {
            response = Data([fcByte | 0x80, e.code])
            isException = true
            summary = "异常响应：\(e.name)"
        } catch {
            response = Data([fcByte | 0x80, 0x04])
            isException = true
            summary = "内部错误"
        }

        stats.recordRequest(fc: fcByte, isException: isException)
        let frame = ModbusCodec.buildMBAP(transactionId: transactionId,
                                          unitId: unitId, pdu: response)
        onFrame?(.tx, frame, nil, summary)

        connection.send(content: frame, completion: .contentProcessed { _ in })
    }

    struct ExecutionResult {
        var pdu: Data
        var isException: Bool
        var summary: String
    }

    /// 对请求 PDU 执行业务逻辑（也供单元测试直接调用）。
    func execute(pdu: Data) throws -> ExecutionResult {
        guard pdu.count >= 5 else { throw ModbusException(code: 0x03) }
        let fc = pdu[pdu.startIndex]
        let address = Int(pdu.readBEUInt16(at: 1))

        switch ModbusFunction(rawValue: fc) {
        case .readCoils, .readDiscreteInputs:
            let count = Int(pdu.readBEUInt16(at: 3))
            guard (1...ModbusLimits.maxReadBits).contains(count) else { throw ModbusException.illegalDataValue }
            let area: ModbusArea = fc == 0x01 ? .coils : .discreteInputs
            guard address + count <= ModbusLimits.addressSpace else { throw ModbusException.illegalDataAddress }
            let bits = store.readBits(area: area, offset: address, count: count)
            let packed = ModbusCodec.bitsByteString(bits)
            var out = Data([fc, UInt8(packed.count)])
            out.append(packed)
            return ExecutionResult(pdu: out, isException: false,
                                   summary: "\(area.name) \(address)×\(count)")

        case .readHoldingRegisters, .readInputRegisters:
            let count = Int(pdu.readBEUInt16(at: 3))
            guard (1...ModbusLimits.maxReadRegisters).contains(count) else { throw ModbusException.illegalDataValue }
            let area: ModbusArea = fc == 0x03 ? .holdingRegisters : .inputRegisters
            guard address + count <= ModbusLimits.addressSpace else { throw ModbusException.illegalDataAddress }
            let regs = store.readRegisters(area: area, offset: address, count: count)
            var out = Data([fc, UInt8(count * 2)])
            for r in regs { out.appendBE(r) }
            return ExecutionResult(pdu: out, isException: false,
                                   summary: "\(area.name) \(address)×\(count)")

        case .writeSingleCoil:
            let value = pdu.readBEUInt16(at: 3)
            guard value == 0 || value == 0xFF00 else { throw ModbusException.illegalDataValue }
            guard address < ModbusLimits.addressSpace else { throw ModbusException.illegalDataAddress }
            store.writeBits(area: .coils, offset: address, values: [value == 0xFF00])
            return ExecutionResult(pdu: pdu, isException: false,
                                   summary: "写线圈 \(address) = \(value == 0xFF00 ? 1 : 0)")

        case .writeSingleRegister:
            guard address < ModbusLimits.addressSpace else { throw ModbusException.illegalDataAddress }
            let value = pdu.readBEUInt16(at: 3)
            store.writeRegisters(area: .holdingRegisters, offset: address, values: [value])
            return ExecutionResult(pdu: pdu, isException: false,
                                   summary: "写保持寄存器 \(address) = \(value)")

        case .writeMultipleCoils:
            let count = Int(pdu.readBEUInt16(at: 3))
            let byteCount = Int(pdu[pdu.startIndex + 5])
            guard (1...ModbusLimits.maxWriteBits).contains(count), byteCount == (count + 7) / 8,
                  pdu.count == 6 + byteCount else { throw ModbusException.illegalDataValue }
            guard address + count <= ModbusLimits.addressSpace else { throw ModbusException.illegalDataAddress }
            let bitsData = pdu.subdata(in: (pdu.startIndex + 6)..<(pdu.startIndex + 6 + byteCount))
            store.writeBits(area: .coils, offset: address, values: ModbusCodec.bits(from: bitsData, count: count))
            var out = Data([fc])
            out.appendBE(UInt16(address))
            out.appendBE(UInt16(count))
            return ExecutionResult(pdu: out, isException: false,
                                   summary: "写线圈 \(address)×\(count)")

        case .writeMultipleRegisters:
            let count = Int(pdu.readBEUInt16(at: 3))
            let byteCount = Int(pdu[pdu.startIndex + 5])
            guard (1...ModbusLimits.maxWriteRegisters).contains(count), byteCount == count * 2,
                  pdu.count == 6 + byteCount else { throw ModbusException.illegalDataValue }
            guard address + count <= ModbusLimits.addressSpace else { throw ModbusException.illegalDataAddress }
            var regs: [UInt16] = []
            for i in stride(from: 0, to: byteCount, by: 2) {
                regs.append(pdu.readBEUInt16(at: 6 + i))
            }
            store.writeRegisters(area: .holdingRegisters, offset: address, values: regs)
            var out = Data([fc])
            out.appendBE(UInt16(address))
            out.appendBE(UInt16(count))
            return ExecutionResult(pdu: out, isException: false,
                                   summary: "写保持寄存器 \(address)×\(count)")

        case .none:
            throw ModbusException.illegalFunction
        }
    }
}
