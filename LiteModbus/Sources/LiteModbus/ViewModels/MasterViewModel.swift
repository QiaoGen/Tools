import Foundation
import Combine

/// 主站视图模型：连接、点位表、轮询引擎、手动写入、报文日志。
@MainActor
final class MasterViewModel: ObservableObject {
    @Published var config = MasterConnectionConfig() {
        didSet { scheduleSave() }
    }
    @Published var tags: [TagPoint] = [] {
        didSet { scheduleSave() }
    }
    @Published var values: [UUID: TagValue] = [:]
    @Published var valueErrors: [UUID: String] = [:]
    @Published var valueTimes: [UUID: Date] = [:]
    @Published var flashing: Set<UUID> = []

    @Published var isConnecting = false
    @Published var isConnected = false
    @Published var connectionError: String?

    @Published var isPolling = false
    @Published var cycleTimeMs: Double = 0
    @Published var txCount = 0
    @Published var rxCount = 0
    @Published var errCount = 0

    let log = TrafficLog()
    let client = ModbusTCPClient()

    private var pollTask: Task<Void, Never>?
    private var saveWork: DispatchWorkItem?
    private var flashWork: DispatchWorkItem?

    init() {
        load()
        client.onFrame = { [weak self] direction, data, error in
            guard let self else { return }
            let entry = TrafficLogEntry(direction: direction, bytes: data, error: error?.localizedDescription,
                                        summary: Self.summarize(frame: data, direction: direction))
            self.log.append(entry)
            Task { @MainActor [weak self] in
                guard let self else { return }
                switch direction {
                case .tx: self.txCount += 1
                case .rx: self.rxCount += 1
                }
            }
        }
    }

    // MARK: - 连接

    func connect() {
        guard !isConnecting else { return }
        isConnecting = true
        connectionError = nil
        Task { [weak self] in
            guard let self else { return }
            do {
                try await self.client.connect(host: self.config.host,
                                              port: self.config.port,
                                              timeout: Double(self.config.timeoutMs) / 1000)
                self.isConnected = true
            } catch {
                self.connectionError = error.localizedDescription
                self.log.append(TrafficLogEntry(direction: .tx, bytes: Data(),
                                                error: "连接失败：\(error.localizedDescription)"))
            }
            self.isConnecting = false
        }
    }

    func disconnect() {
        stopPolling()
        client.disconnect()
        isConnected = false
    }

    func toggleConnection() {
        isConnected ? disconnect() : connect()
    }

    // MARK: - 轮询

    func startPolling() {
        guard !isPolling else { return }
        guard isConnected else { return }
        isPolling = true
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let started = Date()
                await self.pollCycle()
                let elapsed = Date().timeIntervalSince(started) * 1000
                let wait = max(10, Double(self.config.pollIntervalMs) - elapsed)
                try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000))
            }
        }
    }

    func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
        isPolling = false
    }

    private func pollCycle() async {
        let t0 = Date()
        for batch in Self.buildBatches(from: tags) {
            let timeout = Double(config.timeoutMs) / 1000
            do {
                switch batch.area {
                case .holdingRegisters, .inputRegisters:
                    let regs = try await client.readRegisters(
                        area: batch.area, address: UInt16(batch.start),
                        count: batch.end - batch.start,
                        unitId: config.unitId, timeout: timeout)
                    for tag in batch.tags {
                        applyRegisters(regs, to: tag, batchStart: batch.start)
                    }
                case .coils, .discreteInputs:
                    let bits = try await client.readBits(
                        area: batch.area, address: UInt16(batch.start),
                        count: batch.end - batch.start,
                        unitId: config.unitId, timeout: timeout)
                    for tag in batch.tags {
                        let index = tag.address.offset - batch.start
                        setTagValue(.bool(bits[index]), tag: tag)
                    }
                }
            } catch {
                errCount += 1
                let message = Self.errorText(error)
                for tag in batch.tags {
                    valueErrors[tag.id] = message
                }
            }
        }
        cycleTimeMs = Date().timeIntervalSince(t0) * 1000
    }

    private func applyRegisters(_ regs: [UInt16], to tag: TagPoint, batchStart: Int) {
        let index = tag.address.offset - batchStart
        if let bit = tag.address.bit {
            let bitValue = regs[index] >> UInt16(bit) & 1 == 1
            setTagValue(.bool(bitValue), tag: tag)
            return
        }
        let slice = Array(regs[index..<index + tag.dataType.registerCount])
        let words = tag.byteOrder.canonicalWords(from: slice)
        guard let value = TagValue.from(bigEndianWords: words, type: tag.dataType) else { return }
        setTagValue(value, tag: tag)
    }

    private func setTagValue(_ value: TagValue, tag: TagPoint) {
        valueErrors[tag.id] = nil
        valueTimes[tag.id] = Date()
        if values[tag.id] != value {
            values[tag.id] = value
            flashing.insert(tag.id)
            flashWork?.cancel()
            flashWork = DispatchWorkItem { [weak self] in
                self?.flashing.removeAll()
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: flashWork!)
        }
    }

    /// 单个点位手动读取。
    func readTag(_ tag: TagPoint) {
        Task { [weak self] in
            guard let self else { return }
            let timeout = Double(self.config.timeoutMs) / 1000
            do {
                switch tag.address.area {
                case .coils, .discreteInputs:
                    let bits = try await self.client.readBits(area: tag.address.area,
                                                              address: UInt16(tag.address.offset),
                                                              count: 1,
                                                              unitId: self.config.unitId, timeout: timeout)
                    self.setTagValue(.bool(bits[0]), tag: tag)
                case .holdingRegisters, .inputRegisters:
                    let regs = try await self.client.readRegisters(area: tag.address.area,
                                                                   address: UInt16(tag.address.offset),
                                                                   count: tag.dataType.registerCount,
                                                                   unitId: self.config.unitId, timeout: timeout)
                    self.applyRegisters(regs, to: tag, batchStart: tag.address.offset)
                }
            } catch {
                self.errCount += 1
                self.valueErrors[tag.id] = Self.errorText(error)
            }
        }
    }

    // MARK: - 写入

    enum WriteOutcome: Equatable {
        case ok
        case failed(String)
    }

    @discardableResult
    func write(tag: TagPoint, value: TagValue) async -> WriteOutcome {
        guard tag.isWritable else { return .failed("该区域只读") }
        let timeout = Double(config.timeoutMs) / 1000
        let address = UInt16(tag.address.offset)
        do {
            switch tag.address.area {
            case .coils:
                guard case .bool(let b) = value else { return .failed("线圈只接受布尔值") }
                try await client.writeSingleCoil(address: address, value: b,
                                                 unitId: config.unitId, timeout: timeout)
            case .holdingRegisters:
                if let bit = tag.address.bit {
                    guard case .bool(let b) = value else { return .failed("位点位只接受布尔值") }
                    let regs = try await client.readRegisters(area: .holdingRegisters, address: address,
                                                              count: 1, unitId: config.unitId, timeout: timeout)
                    var word = regs[0]
                    let mask = UInt16(1) << UInt16(bit)
                    word = b ? word | mask : word & ~mask
                    try await client.writeSingleRegister(address: address, value: word,
                                                         unitId: config.unitId, timeout: timeout)
                } else {
                    let regs = value.transmissionRegisters(order: tag.byteOrder)
                    if regs.count == 1 {
                        try await client.writeSingleRegister(address: address, value: regs[0],
                                                             unitId: config.unitId, timeout: timeout)
                    } else {
                        try await client.writeMultipleRegisters(address: address, values: regs,
                                                                unitId: config.unitId, timeout: timeout)
                    }
                }
            default:
                return .failed("该区域只读")
            }
            // 写后回读刷新显示
            readTag(tag)
            return .ok
        } catch {
            errCount += 1
            return .failed(Self.errorText(error))
        }
    }

    /// 应用配方：按条目顺序下写，返回每条结果。
    func applyRecipe(_ entries: [RecipeEntry]) async -> [UUID: WriteOutcome] {
        var results: [UUID: WriteOutcome] = [:]
        for entry in entries {
            var tag = TagPoint()
            tag.addressNumber = entry.addressNumber
            tag.bit = entry.bit
            tag.dataType = entry.dataType
            tag.byteOrder = entry.byteOrder
            guard let value = TagValue.parse(entry.valueText, type: entry.dataType) else {
                results[entry.id] = .failed("值无法解析")
                continue
            }
            results[entry.id] = await write(tag: tag, value: value)
        }
        return results
    }

    /// 从当前点位捕获一条配方（可写且已有读值的点位）。
    func captureRecipeEntries(includeUnwritten: Bool = false) -> [RecipeEntry] {
        tags.filter { $0.isWritable && (includeUnwritten || values[$0.id] != nil) }
            .map { tag in
                var entry = RecipeEntry()
                entry.name = tag.name.isEmpty ? tag.displayAddress : tag.name
                entry.addressNumber = tag.addressNumber
                entry.bit = tag.bit
                entry.dataType = tag.dataType
                entry.byteOrder = tag.byteOrder
                entry.unit = tag.unit
                if let value = values[tag.id] {
                    entry.valueText = value.displayText
                }
                return entry
            }
    }

    // MARK: - 点位管理

    func add(_ tag: TagPoint) {
        tags.append(tag)
    }

    func remove(_ tag: TagPoint) {
        tags.removeAll { $0.id == tag.id }
        values[tag.id] = nil
        valueErrors[tag.id] = nil
    }

    func duplicate(_ tag: TagPoint) {
        var copy = tag
        copy.id = UUID()
        copy.name = tag.name + " 副本"
        copy.onDashboard = false
        tags.append(copy)
    }

    /// 批量添加：从起始地址生成 count 个连续点位。
    nonisolated static func makeBatch(prefix: String, addressNumber: Int, count: Int,
                          bit: Int?, dataType: TagDataType, byteOrder: ByteOrder,
                          unit: String, onDashboard: Bool) -> [TagPoint] {
        guard let first = try? TagAddress.parse("\(addressNumber)") else { return [] }
        return (0..<max(1, count)).compactMap { i in
            let offset = first.offset + i * max(1, dataType.registerCount)
            guard offset < ModbusLimits.addressSpace else { return nil }
            var tag = TagPoint()
            tag.name = prefix.isEmpty ? "" : "\(prefix)\(i + 1)"
            tag.addressNumber = first.area.displayAddress(offset: offset)
            tag.bit = bit
            tag.dataType = dataType
            tag.byteOrder = byteOrder
            tag.unit = unit
            tag.onDashboard = onDashboard
            return tag
        }
    }

    // MARK: - 轮询分组

    struct ReadBatch {
        var area: ModbusArea
        var start: Int
        var end: Int
        var tags: [TagPoint]
    }

    /// 把点位按区域分组，仅相邻/重叠地址合并成批量读（间隙合并会读到未定义地址，
    /// 严格设备会返回异常 02，因此不做间隙填充）。长度不超协议上限。
    nonisolated static func buildBatches(from tags: [TagPoint]) -> [ReadBatch] {
        var batches: [ReadBatch] = []
        for area in ModbusArea.allCases {
            let areaTags = tags
                .filter { $0.pollEnabled && $0.address.area == area }
                .sorted { ($0.address.offset, $0.address.bit ?? -1) < ($1.address.offset, $1.address.bit ?? -1) }
            var current: ReadBatch?
            let spanLimit = area.isRegisterArea ? ModbusLimits.maxReadRegisters : ModbusLimits.maxReadBits
            for tag in areaTags {
                let start = tag.address.offset
                let end = start + max(1, tag.dataType.registerCount)
                if current != nil, start <= current!.end, end - current!.start <= spanLimit {
                    current!.end = max(current!.end, end)
                    current!.tags.append(tag)
                } else {
                    if let c = current { batches.append(c) }
                    current = ReadBatch(area: area, start: start, end: end, tags: [tag])
                }
            }
            if let c = current { batches.append(c) }
        }
        return batches
    }

    // MARK: - 报文摘要

    nonisolated static func summarize(frame: Data, direction: TrafficDirection) -> String {
        guard frame.count >= 8, let header = try? ModbusCodec.parseFrame(from: frame) else { return "" }
        let pdu = frame.subdata(in: (frame.startIndex + 7)..<frame.endIndex)
        guard let fcByte = pdu.first else { return "" }
        if fcByte & 0x80 != 0 {
            let code = pdu.count >= 2 ? pdu[pdu.startIndex + 1] : 0
            return "异常 \(ModbusException(code: code).name)"
        }
        guard let fc = ModbusFunction(rawValue: fcByte) else {
            return String(format: "功能码 0x%02X", fcByte)
        }
        func addr(_ i: Int) -> Int { Int(pdu.readBEUInt16(at: i)) }
        switch fc {
        case .readCoils, .readDiscreteInputs, .readHoldingRegisters, .readInputRegisters:
            guard pdu.count >= 5 else { return fc.name }
            let area = areaForFunction(fc) ?? .holdingRegisters
            let number = area.displayAddress(offset: addr(1))
            return "\(fc.name) \(number)×\(addr(3))"
        case .writeSingleCoil:
            return pdu.count >= 5 ? "写线圈 \(addr(1)) = \(addr(3) == 0xFF00 ? 1 : 0)" : fc.name
        case .writeSingleRegister:
            return pdu.count >= 5 ? "写保持寄存器 \(addr(1)) = \(addr(3))" : fc.name
        case .writeMultipleCoils:
            return pdu.count >= 5 ? "写线圈 \(addr(1))×\(addr(3))" : fc.name
        case .writeMultipleRegisters:
            return pdu.count >= 5 ? "写保持寄存器 \(addr(1))×\(addr(3))" : fc.name
        }
    }

    private nonisolated static func areaForFunction(_ fc: ModbusFunction) -> ModbusArea? {
        switch fc {
        case .readCoils: return .coils
        case .readDiscreteInputs: return .discreteInputs
        case .readHoldingRegisters: return .holdingRegisters
        case .readInputRegisters: return .inputRegisters
        default: return nil
        }
    }

    nonisolated static func errorText(_ error: Error) -> String {
        if case ModbusError.exception(let e) = error {
            return e.name
        }
        if case ModbusError.timeout = error {
            return "超时"
        }
        return error.localizedDescription
    }

    // MARK: - 持久化

    private func load() {
        if let doc: MasterDocument = JSONStore.shared.load(MasterDocument.self, from: JSONStore.masterFile) {
            config = doc.connection
            tags = doc.tags
        }
    }

    private func scheduleSave() {
        saveWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            let doc = MasterDocument(connection: self.config, tags: self.tags)
            JSONStore.shared.save(doc, as: JSONStore.masterFile)
        }
        saveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
    }
}
