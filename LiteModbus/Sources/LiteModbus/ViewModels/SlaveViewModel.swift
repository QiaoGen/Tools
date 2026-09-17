import Foundation

/// 从站视图模型：监听、统计、寄存器表、内存编辑、快照。
@MainActor
final class SlaveViewModel: ObservableObject {
    let slave = ModbusTCPSlave()
    let log = TrafficLog()

    @Published var isRunning = false
    @Published var port: UInt16 = 1502 { didSet { scheduleSave() } }
    @Published var respondToAllUnits = true { didSet { scheduleSave() } }
    @Published var unitIdsText = "1" { didSet { applyUnitIds(); scheduleSave() } }
    @Published var responseDelayMs = 0 { didSet { slave.responseDelayMs = responseDelayMs; scheduleSave() } }

    @Published var activeConnections = 0
    @Published var requests = 0
    @Published var exceptions = 0
    @Published var ratePerSecond: Double = 0

    @Published var selectedArea: ModbusArea = .holdingRegisters {
        didSet { syncRangeFromSaved() }
    }
    /// 各区显示范围：起始显示编号 + 数量。
    @Published var rangeStart: [ModbusArea: Int] = [
        .coils: 1, .discreteInputs: 10001, .inputRegisters: 30001, .holdingRegisters: 40001,
    ] { didSet { scheduleSave() } }
    @Published var rangeCount: [ModbusArea: Int] = [
        .coils: 16, .discreteInputs: 16, .inputRegisters: 16, .holdingRegisters: 16,
    ] { didSet { scheduleSave() } }

    /// 变量名：键 "区:偏移"。
    @Published var names: [String: String] = [:] { didSet { scheduleSave() } }
    @Published var rows: [SlaveRow] = []

    private var timer: Timer?
    private var saveWork: DispatchWorkItem?

    struct SlaveRow: Identifiable {
        var id: Int { offset }
        var offset: Int
        var displayNumber: Int
        var name: String
        var word: UInt16
        var bits: [Bool]
        var isCoilArea: Bool
    }

    init() {
        load()
        slave.responseDelayMs = responseDelayMs
        slave.respondToAllUnits = respondToAllUnits
        slave.unitIds = parseUnitIds()
        slave.store.onWrite = { [weak self] in
            Task { @MainActor [weak self] in
                self?.rebuildRows()
            }
        }
        slave.onFrame = { [weak self] direction, data, error, summary in
            guard let self else { return }
            let entry = TrafficLogEntry(direction: direction, bytes: data,
                                        error: error?.localizedDescription, summary: summary)
            self.log.append(entry)
        }
        rebuildRows()
        startTimer()
    }

    // MARK: - 监听

    func toggleRun() {
        if isRunning {
            slave.stop()
            isRunning = false
        } else {
            slave.respondToAllUnits = respondToAllUnits
            slave.unitIds = parseUnitIds()
            slave.responseDelayMs = responseDelayMs
            do {
                try slave.start(port: port)
                isRunning = true
            } catch {
                log.append(TrafficLogEntry(direction: .tx, bytes: Data(),
                                           error: "监听失败：\(error.localizedDescription)"))
            }
        }
    }

    private func parseUnitIds() -> Set<UInt8> {
        let trimmed = unitIdsText.replacingOccurrences(of: " ", with: "")
        var ids = Set<UInt8>()
        // 逗号分隔列表，每段支持 "5" 或区间 "1-247"。
        for segment in trimmed.split(separator: ",") {
            if let dash = segment.range(of: "-") {
                let a = segment[..<dash.lowerBound]
                let b = segment[dash.upperBound...]
                if let start = UInt8(a), let end = UInt8(b), start <= end {
                    for v in start...end where v >= 1 { ids.insert(v) }
                }
            } else if let v = UInt8(segment), v >= 1 {
                ids.insert(v)
            }
        }
        return ids.isEmpty ? [1] : ids
    }

    private func applyUnitIds() {
        slave.unitIds = parseUnitIds()
        slave.respondToAllUnits = respondToAllUnits
    }

    // MARK: - 表格

    func viewStartOffset() -> Int {
        let start = rangeStart[selectedArea] ?? selectedArea.fiveDigitBase
        guard let parsed = try? TagAddress.parse("\(start)"), parsed.area == selectedArea else {
            return 0
        }
        return parsed.offset
    }

    func rebuildRows() {
        let area = selectedArea
        let start = viewStartOffset()
        let count = max(1, min(500, rangeCount[area] ?? 16))
        guard start + count <= ModbusLimits.addressSpace else { return }
        var newRows: [SlaveRow] = []
        newRows.reserveCapacity(count)
        let isCoil = area == .coils || area == .discreteInputs
        for i in 0..<count {
            let offset = start + i
            let word = slave.store.value(area: area, offset: offset)
            let bits = (0..<16).map { word >> UInt16($0) & 1 == 1 }
            newRows.append(SlaveRow(offset: offset,
                                    displayNumber: area.displayAddress(offset: offset),
                                    name: names[SlaveDocument.nameKey(area: area, offset: offset)] ?? "",
                                    word: word,
                                    bits: bits,
                                    isCoilArea: isCoil))
        }
        rows = newRows
    }

    func setName(_ name: String, offset: Int) {
        names[SlaveDocument.nameKey(area: selectedArea, offset: offset)] = name
        rebuildRows()
    }

    func name(area: ModbusArea, offset: Int) -> String {
        names[SlaveDocument.nameKey(area: area, offset: offset)] ?? ""
    }

    /// 双击修改寄存器值（解析多种进制）。
    func setRegisterText(_ text: String, offset: Int) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        let value: UInt16?
        if trimmed.lowercased().hasPrefix("0x") {
            value = UInt16(trimmed.dropFirst(2), radix: 16)
        } else {
            value = UInt16(trimmed)
        }
        guard let v = value else { return "需要 0–65535 或 0x 十六进制" }
        slave.store.writeRegisters(area: selectedArea, offset: offset, values: [v])
        rebuildRows()
        return nil
    }

    func setCoil(_ on: Bool, offset: Int) {
        let area: ModbusArea = selectedArea == .coils ? .coils : .discreteInputs
        slave.store.writeBits(area: area, offset: offset, values: [on])
        rebuildRows()
    }

    func toggleBit(offset: Int, bit: Int) {
        switch selectedArea {
        case .coils:
            slave.store.writeBits(area: .coils, offset: offset, values: [!slave.store.bitValue(area: .coils, offset: offset, bit: 0)])
        case .discreteInputs:
            slave.store.writeBits(area: .discreteInputs, offset: offset, values: [!slave.store.bitValue(area: .discreteInputs, offset: offset, bit: 0)])
        default:
            let current = slave.store.bitValue(area: selectedArea, offset: offset, bit: bit)
            slave.store.setRegisterBit(area: selectedArea, offset: offset, bit: bit, value: !current)
        }
        rebuildRows()
    }

    func floatText(_ word: UInt16, _ neighbor: UInt16?) -> String {
        // Float(AB CD)：当前行与下一行组成
        guard let next = neighbor else { return "-" }
        let value = TagValue.from(bigEndianWords: [word, next], type: .float32)
        if case .float32(let f)? = value {
            if f.isNaN { return "NaN" }
            return String(format: "%.4g", Double(f))
        }
        return "-"
    }

    // MARK: - 快照

    func exportSnapshot() -> [SlaveDataStore.SparseEntry] {
        slave.store.snapshot()
    }

    func importSnapshot(_ entries: [SlaveDataStore.SparseEntry]) {
        slave.store.restore(from: entries)
        rebuildRows()
    }

    func resetStats() {
        slave.stats.reset()
    }

    // MARK: - 定时刷新

    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.activeConnections = self.slave.activeConnections
                self.requests = self.slave.stats.requests
                self.exceptions = self.slave.stats.exceptions
                self.ratePerSecond = self.slave.stats.ratePerSecond
                if self.slave.isRunning != self.isRunning {
                    self.isRunning = self.slave.isRunning
                }
            }
        }
    }

    // MARK: - 持久化

    private func syncRangeFromSaved() {
        // 区域切换时无需额外动作，rangeStart/rangeCount 已按区保存。
    }

    private func load() {
        guard let doc: SlaveDocument = JSONStore.shared.load(SlaveDocument.self, from: JSONStore.slaveFile) else {
            return
        }
        port = doc.port
        respondToAllUnits = doc.respondToAllUnits
        unitIdsText = doc.unitIds.isEmpty ? "1" : doc.unitIds.map(String.init).joined(separator: ",")
        responseDelayMs = doc.responseDelayMs
        names = doc.names
        for (key, info) in doc.viewRanges {
            guard let area = ModbusArea(rawValue: Int(key) ?? -1) else { continue }
            rangeStart[area] = info.start
            rangeCount[area] = info.count
        }
        slave.store.restore(from: doc.memory)
    }

    private func scheduleSave() {
        saveWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            var ranges: [String: SlaveDocument.RangeInfo] = [:]
            for area in ModbusArea.allCases {
                ranges[SlaveDocument.rangeKey(area: area)] = SlaveDocument.RangeInfo(
                    start: self.rangeStart[area] ?? area.fiveDigitBase,
                    count: self.rangeCount[area] ?? 16)
            }
            let doc = SlaveDocument(port: self.port,
                                    respondToAllUnits: self.respondToAllUnits,
                                    unitIds: Array(self.parseUnitIds()).sorted(),
                                    responseDelayMs: self.responseDelayMs,
                                    names: self.names,
                                    viewRanges: ranges,
                                    memory: self.slave.store.snapshot())
            JSONStore.shared.save(doc, as: JSONStore.slaveFile)
        }
        saveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }
}
