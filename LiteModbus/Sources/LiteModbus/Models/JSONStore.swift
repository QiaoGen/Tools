import Foundation

/// 本地 JSON 持久化。所有数据存放在 ~/Library/Application Support/LiteModbus/。
final class JSONStore {
    static let shared = JSONStore()

    let directory: URL

    private let encoder: JSONEncoder
    private let decoder = JSONDecoder()
    private let queue = DispatchQueue(label: "litemodbus.jsonstore")

    init(directory: URL? = nil) {
        let base = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("LiteModbus", isDirectory: true)
        self.directory = base
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    var displayPath: String {
        directory.path.replacingOccurrences(of: NSHomeDirectory(), with: "~")
    }

    // MARK: - 读写

    func save<T: Encodable>(_ value: T, as file: String) {
        queue.async { [self] in
            guard let data = try? encoder.encode(value) else { return }
            try? data.write(to: directory.appendingPathComponent(file), options: .atomic)
        }
    }

    func load<T: Decodable>(_ type: T.Type, from file: String) -> T? {
        queue.sync {
            guard let data = try? Data(contentsOf: directory.appendingPathComponent(file)) else { return nil }
            return try? decoder.decode(type, from: data)
        }
    }

    /// 导出 JSON 到任意路径（配方导出等）。
    func export<T: Encodable>(_ value: T, to url: URL) throws {
        let data = try encoder.encode(value)
        try data.write(to: url, options: .atomic)
    }

    func importJSON<T: Decodable>(_ type: T.Type, from url: URL) throws -> T {
        let data = try Data(contentsOf: url)
        return try decoder.decode(type, from: data)
    }

    static let masterFile = "master.json"
    static let slaveFile = "slave.json"
    static let recipesFile = "recipes.json"
}

/// 报文日志条目（主站与从站共用）。
struct TrafficLogEntry: Identifiable, Equatable {
    var id = UUID()
    var direction: TrafficDirection
    var time = Date()
    var bytes: Data
    var error: String? = nil
    var summary: String = ""
    var durationMs: Double? = nil

    var hexText: String {
        bytes.prefix(64).map { String(format: "%02X", $0) }.joined(separator: " ")
        + (bytes.count > 64 ? " …(\(bytes.count)B)" : "")
    }

    var functionText: String {
        guard bytes.count >= 8 else { return "-" }
        let fc = bytes[bytes.startIndex + 7]
        if fc & 0x80 != 0 {
            let code = bytes.count >= 9 ? bytes[bytes.startIndex + 8] : 0
            return "0x\(String(fc & 0x7F, radix: 16)) 异常\(code)"
        }
        return String(format: "0x%02X", fc)
    }
}

/// 环形缓冲报文日志。
final class TrafficLog: ObservableObject {
    @Published private(set) var entries: [TrafficLogEntry] = []
    private let lock = NSLock()
    private let capacity = 2000

    func append(_ entry: TrafficLogEntry) {
        lock.lock()
        entries.append(entry)
        if entries.count > capacity {
            entries.removeFirst(entries.count - capacity)
        }
        lock.unlock()
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.objectWillChange.send()
        }
    }

    func clear() {
        lock.lock()
        entries.removeAll()
        lock.unlock()
        DispatchQueue.main.async { [weak self] in
            self?.objectWillChange.send()
        }
    }
}
