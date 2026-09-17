import XCTest
@testable import LiteModbus

/// 主从回环集成测试：真实 TCP 监听 + 连接 + 读写。
final class IntegrationTests: XCTestCase {
    func testMasterSlaveLoop() async throws {
        let port = UInt16.random(in: 30000...60000)
        let slave = ModbusTCPSlave()
        slave.store.writeRegisters(area: .holdingRegisters, offset: 0, values: [0x1234, 0x5678])
        try slave.start(port: port)
        defer { slave.stop() }
        try await Task.sleep(nanoseconds: 300_000_000) // 等监听就绪

        let client = ModbusTCPClient()
        try await client.connect(host: "127.0.0.1", port: port, timeout: 3)
        defer { client.disconnect() }

        // 读保持寄存器
        let regs = try await client.readRegisters(area: .holdingRegisters, address: 0, count: 2,
                                                  unitId: 1, timeout: 2)
        XCTAssertEqual(regs, [0x1234, 0x5678])

        // 写单寄存器
        try await client.writeSingleRegister(address: 5, value: 999, unitId: 1, timeout: 2)
        XCTAssertEqual(slave.store.value(area: .holdingRegisters, offset: 5), 999)

        // 写单线圈 + 读回
        try await client.writeSingleCoil(address: 7, value: true, unitId: 1, timeout: 2)
        let coils = try await client.readBits(area: .coils, address: 7, count: 1, unitId: 1, timeout: 2)
        XCTAssertEqual(coils, [true])

        // 非法地址 → 异常 0x02
        do {
            _ = try await client.readRegisters(area: .holdingRegisters, address: 65530, count: 10,
                                               unitId: 1, timeout: 2)
            XCTFail("应当抛出异常响应")
        } catch ModbusError.exception(let e) {
            XCTAssertEqual(e.code, 0x02)
        }

        // Float32 CDAB 多寄存器下写 + 读回解码
        let words = TagValue.float32(3.5).transmissionRegisters(order: .cdab)
        try await client.writeMultipleRegisters(address: 10, values: words, unitId: 1, timeout: 2)
        let back = slave.store.readRegisters(area: .holdingRegisters, offset: 10, count: 2)
        let decoded = TagValue.from(bigEndianWords: ByteOrder.cdab.canonicalWords(from: back),
                                    type: .float32)
        XCTAssertEqual(decoded, .float32(3.5))

        // 位写（读-改-写路径）
        try await client.writeSingleRegister(address: 20, value: 0b0000_0000_0000_0001,
                                             unitId: 1, timeout: 2)
        try await client.writeMultipleCoils(address: 30, values: [true, false, true],
                                            unitId: 1, timeout: 2)
        let bits = try await client.readBits(area: .coils, address: 30, count: 3, unitId: 1, timeout: 2)
        XCTAssertEqual(bits, [true, false, true])

        XCTAssertGreaterThan(slave.stats.requests, 0)
    }

    func testBatchGrouping() {
        func tag(_ n: Int) -> TagPoint {
            var t = TagPoint()
            t.addressNumber = n
            return t
        }
        let tags = [tag(40001), tag(40002), tag(40010), tag(40011), tag(40200), tag(30100)]
        let batches = MasterViewModel.buildBatches(from: tags)
        // 40001/40002 合并，40010/40011 合并，40200 与 30100 各自独立
        XCTAssertEqual(batches.count, 4)
        let holding = batches.filter { $0.area == .holdingRegisters }
        XCTAssertEqual(holding.count, 3)
        XCTAssertEqual(holding[0].start, 0)
        XCTAssertEqual(holding[0].end, 2)
    }
}
