import Foundation

/// 主站点位（变量）。地址支持位细分（40001.1）。
struct TagPoint: Identifiable, Codable, Equatable, Hashable {
    var id: UUID = UUID()
    /// 变量名称，如「电机温度」。
    var name: String = ""
    var addressNumber: Int = 40001
    /// nil = 整寄存器 / 线圈；0...15 = 寄存器位。
    var bit: Int? = nil
    var dataType: TagDataType = .uint16
    var byteOrder: ByteOrder = .abcd
    /// 工程单位（°C、kPa…），可选。
    var unit: String = ""
    var comment: String = ""
    /// 轮询启用。
    var pollEnabled: Bool = true
    /// 显示在看板。
    var onDashboard: Bool = false

    var address: TagAddress {
        get {
            (try? TagAddress.parse("\(addressNumber)" + (bit.map { ".\($0)" } ?? ""))) ??
                TagAddress(area: .holdingRegisters, offset: 0, bit: bit)
        }
        set {
            addressNumber = newValue.area.displayAddress(offset: newValue.offset)
            bit = newValue.bit
        }
    }

    var displayAddress: String {
        let number = address.area.displayAddress(offset: address.offset)
        return bit.map { "\(number).\($0)" } ?? "\(number)"
    }

    /// 该点位读取需要的寄存器数量（位点位读整寄存器）。
    var readRegisterCount: Int { dataType.registerCount }

    /// 可写区域：线圈与保持寄存器。
    var isWritable: Bool {
        switch address.area {
        case .coils: return dataType == .bool
        case .holdingRegisters: return true
        default: return false
        }
    }
}

/// 配方条目：一个点位的写入值（值以字符串保存，随类型解释）。
struct RecipeEntry: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    /// 点位名称快照。
    var name: String = ""
    var addressNumber: Int = 40001
    var bit: Int? = nil
    var dataType: TagDataType = .uint16
    var byteOrder: ByteOrder = .abcd
    var unit: String = ""
    var valueText: String = "0"

    var displayAddress: String {
        guard let parsed = try? TagAddress.parse("\(addressNumber)") else { return "\(addressNumber)" }
        let number = parsed.area.displayAddress(offset: parsed.offset)
        return bit.map { "\(number).\($0)" } ?? "\(number)"
    }
}

/// 配方：一组点位 + 目标值，可一键下写到设备。
struct Recipe: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var name: String = "新配方"
    var notes: String = ""
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var entries: [RecipeEntry] = []
}

/// 主站连接配置。
struct MasterConnectionConfig: Codable, Equatable {
    var host: String = "127.0.0.1"
    var port: UInt16 = 1502
    var unitId: UInt8 = 1
    var timeoutMs: Int = 1000
    var pollIntervalMs: Int = 1000
}

/// 主站文档（JSON）。
struct MasterDocument: Codable {
    var connection = MasterConnectionConfig()
    var tags: [TagPoint] = []
}

/// 从站文档（JSON）：监听配置 + 变量名 + 内存快照。
struct SlaveDocument: Codable {
    var port: UInt16 = 1502
    var respondToAllUnits = true
    var unitIds: [UInt8] = [1]
    var responseDelayMs: Int = 0
    /// 变量名称：键为 "区前缀:偏移"，如 "4:0"。
    var names: [String: String] = [:]
    /// 各区默认显示范围：键为区前缀。
    var viewRanges: [String: RangeInfo] = [:]
    var memory: [SlaveDataStore.SparseEntry] = []

    struct RangeInfo: Codable, Equatable {
        var start: Int
        var count: Int
    }

    static func nameKey(area: ModbusArea, offset: Int) -> String {
        "\(area.rawValue):\(offset)"
    }

    static func rangeKey(area: ModbusArea) -> String { "\(area.rawValue)" }
}
