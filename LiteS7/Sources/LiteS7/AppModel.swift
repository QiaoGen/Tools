import Foundation

@MainActor
final class AppModel: ObservableObject {
    @Published var configuration: ConnectionConfiguration
    @Published var connectionState: ConnectionState = .disconnected
    @Published var addressText = "DB1.DBW0"
    @Published var valueType: S7ValueType = .uint16
    @Published var writeValue = "0"
    @Published var currentRead: ReadDisplay?
    @Published var statusMessage = "填写 PLC 地址后建立连接"
    @Published var frames: [ProtocolFrame] = []
    @Published var history: [OperationHistory] = []
    @Published var isPolling = false
    @Published var pollIntervalMilliseconds = 500
    @Published var isBusy = false

    private let client = S7Client()
    private var pollTask: Task<Void, Never>?
    private let defaults = UserDefaults.standard

    init() {
        if let data = defaults.data(forKey: "connection.configuration"),
           let saved = try? JSONDecoder().decode(ConnectionConfiguration.self, from: data) {
            configuration = saved
        } else {
            configuration = ConnectionConfiguration()
        }

        if let data = defaults.data(forKey: "operation.history"),
           let saved = try? JSONDecoder().decode([OperationHistory].self, from: data) {
            history = saved
        }
    }

    func connect() async {
        guard connectionState != .connecting else { return }
        connectionState = .connecting
        statusMessage = "正在进行 ISO-on-TCP / S7 握手…"
        isBusy = true
        do {
            let handshakeFrames = try await client.connect(configuration: configuration)
            appendFrames(handshakeFrames)
            connectionState = .connected
            statusMessage = "已连接 \(configuration.host):\(configuration.port) · Rack \(configuration.rack) / Slot \(configuration.slot)"
            persistConfiguration()
        } catch {
            connectionState = .failed(error.localizedDescription)
            statusMessage = error.localizedDescription
        }
        isBusy = false
    }

    func disconnect() {
        stopPolling()
        Task { await client.disconnect() }
        connectionState = .disconnected
        statusMessage = "连接已断开"
        frames.append(ProtocolFrame(direction: .info, bytes: "连接已断开"))
    }

    func readOnce(recordHistory: Bool = true, managesBusyState: Bool = true) async {
        guard connectionState == .connected else {
            statusMessage = LiteS7Error.notConnected.localizedDescription
            return
        }
        if managesBusyState {
            guard !isBusy else { return }
            isBusy = true
        }
        defer {
            if managesBusyState { isBusy = false }
        }

        let started = ContinuousClock.now
        do {
            let address = try S7Address.parse(addressText, valueType: valueType)
            let exchange = try await client.read(address: address, valueType: valueType)
            let value = try S7ValueCodec.decode(exchange.data, as: valueType)
            let elapsed = milliseconds(since: started)
            currentRead = ReadDisplay(
                address: address.original,
                type: valueType,
                value: value,
                hex: S7ValueCodec.hex(exchange.data),
                binary: S7ValueCodec.binary(exchange.data),
                elapsedMilliseconds: elapsed
            )
            statusMessage = "读取完成 · \(elapsed) ms"
            appendFrames(exchange.frames)
            if recordHistory {
                addHistory(kind: .read, value: value, success: true, elapsed: elapsed)
            }
        } catch {
            let elapsed = milliseconds(since: started)
            statusMessage = error.localizedDescription
            if recordHistory {
                addHistory(kind: .read, value: "—", success: false, elapsed: elapsed)
            }
            if isPolling { stopPolling() }
        }
    }

    func writeOnce() async {
        guard connectionState == .connected else {
            statusMessage = LiteS7Error.notConnected.localizedDescription
            return
        }
        guard !isBusy else { return }

        isBusy = true
        let started = ContinuousClock.now
        do {
            let address = try S7Address.parse(addressText, valueType: valueType)
            let payload = try S7ValueCodec.encode(writeValue, as: valueType)
            let exchange = try await client.write(address: address, valueType: valueType, data: payload)
            let elapsed = milliseconds(since: started)
            statusMessage = "写入完成 · \(elapsed) ms"
            appendFrames(exchange.frames)
            addHistory(kind: .write, value: writeValue, success: true, elapsed: elapsed)
            await readOnce(recordHistory: false, managesBusyState: false)
        } catch {
            let elapsed = milliseconds(since: started)
            statusMessage = error.localizedDescription
            addHistory(kind: .write, value: writeValue, success: false, elapsed: elapsed)
        }
        isBusy = false
    }

    func setPolling(_ enabled: Bool) {
        if enabled {
            guard connectionState == .connected else {
                statusMessage = "连接 PLC 后才能开启轮询"
                isPolling = false
                return
            }
            isPolling = true
            pollTask?.cancel()
            pollTask = Task { [weak self] in
                guard let self else { return }
                while !Task.isCancelled {
                    await self.readOnce(recordHistory: false)
                    if !self.isPolling { break }
                    let delay = UInt64(max(100, self.pollIntervalMilliseconds)) * 1_000_000
                    try? await Task.sleep(nanoseconds: delay)
                }
            }
        } else {
            stopPolling()
        }
    }

    func loadHistory(_ item: OperationHistory) {
        stopPolling()
        addressText = item.address
        valueType = item.valueType
        if item.kind == .write { writeValue = item.value }
        statusMessage = "已载入历史操作"
    }

    func clearHistory() {
        history.removeAll()
        persistHistory()
    }

    func clearFrames() {
        frames.removeAll()
    }

    private func stopPolling() {
        isPolling = false
        pollTask?.cancel()
        pollTask = nil
    }

    private func addHistory(kind: OperationKind, value: String, success: Bool, elapsed: Int) {
        history.insert(
            OperationHistory(
                id: UUID(),
                timestamp: Date(),
                kind: kind,
                address: addressText.uppercased(),
                valueType: valueType,
                value: value,
                success: success,
                elapsedMilliseconds: elapsed
            ),
            at: 0
        )
        if history.count > 80 { history.removeLast(history.count - 80) }
        persistHistory()
    }

    private func appendFrames(_ newFrames: [ProtocolFrame]) {
        frames.append(contentsOf: newFrames)
        if frames.count > 120 { frames.removeFirst(frames.count - 120) }
    }

    private func persistConfiguration() {
        if let data = try? JSONEncoder().encode(configuration) {
            defaults.set(data, forKey: "connection.configuration")
        }
    }

    private func persistHistory() {
        if let data = try? JSONEncoder().encode(history) {
            defaults.set(data, forKey: "operation.history")
        }
    }

    private func milliseconds(since start: ContinuousClock.Instant) -> Int {
        let duration = start.duration(to: .now)
        return Int(duration.components.seconds * 1_000) + Int(duration.components.attoseconds / 1_000_000_000_000_000)
    }
}
