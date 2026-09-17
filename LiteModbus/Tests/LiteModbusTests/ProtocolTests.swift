import XCTest
@testable import LiteModbus

final class CodecTests: XCTestCase {
    func testMBAPRoundTrip() throws {
        let pdu = Data([0x03, 0x00, 0x00, 0x00, 0x0A])
        let frame = ModbusCodec.buildMBAP(transactionId: 0x1A2B, unitId: 0x11, pdu: pdu)
        XCTAssertEqual(Array(frame), [0x1A, 0x2B, 0x00, 0x00, 0x00, 0x06, 0x11, 0x03, 0x00, 0x00, 0x00, 0x0A])
        let (header, parsed, consumed) = try ModbusCodec.parseFrame(from: frame)
        XCTAssertEqual(header.transactionId, 0x1A2B)
        XCTAssertEqual(header.unitId, 0x11)
        XCTAssertEqual(header.length, 6)
        XCTAssertEqual(parsed, pdu)
        XCTAssertEqual(consumed, frame.count)
    }

    func testParseFrameRejectsBadProtocolID() {
        var frame = ModbusCodec.buildMBAP(transactionId: 1, unitId: 1, pdu: Data([0x03, 0, 0, 0, 1]))
        frame[2] = 0x01 // 协议标识非 0
        XCTAssertThrowsError(try ModbusCodec.parseFrame(from: frame))
    }

    func testReadRegistersResponse() throws {
        var pdu = Data([0x03, 0x08])
        pdu.append(contentsOf: [0x12, 0x34, 0xFF, 0xFF, 0x00, 0x01, 0xAB, 0xCD])
        let regs = try ModbusCodec.parseReadRegistersResponse(pdu)
        XCTAssertEqual(regs, [0x1234, 0xFFFF, 0x0001, 0xABCD])
    }

    func testReadBitsResponse() throws {
        // 19 个线圈：0xCD 0x01 0xB5（Modbus 规范示例）
        let pdu = Data([0x01, 0x03, 0xCD, 0x01, 0xB5])
        let bits = try ModbusCodec.parseReadBitsResponse(pdu)
        XCTAssertEqual(bits.count, 24)
        XCTAssertTrue(bits[0]); XCTAssertFalse(bits[1])
        XCTAssertTrue(bits[6]); XCTAssertTrue(bits[7]) // 0xCD = 1100 1101
        XCTAssertTrue(bits[8]) // 第二字节 0x01 → bit0
    }

    func testBitsPacking() {
        let bits = [true, false, false, true, false, false, false, false, true]
        let packed = ModbusCodec.bitsByteString(bits)
        XCTAssertEqual(Array(packed), [0b0000_1001, 0b0000_0001])
        let roundTrip = ModbusCodec.bits(from: packed, count: bits.count)
        XCTAssertEqual(roundTrip, bits)
    }

    func testWriteMultipleCoilsRequest() throws {
        let pdu = try ModbusCodec.writeMultipleCoilsRequest(address: 19, values: [
            true, false, true, true, false, false, true, true,
            true, false,
        ])
        // 规范示例：0F 0013 000A 02 CD 01
        XCTAssertEqual(Array(pdu), [0x0F, 0x00, 0x13, 0x00, 0x0A, 0x02, 0xCD, 0x01])
    }

    func testExceptionResponse() throws {
        let pdu = Data([0x83, 0x02])
        XCTAssertTrue(ModbusCodec.isException(pdu))
        let e = try ModbusCodec.parseException(pdu)
        XCTAssertEqual(e.code, 0x02)
        XCTAssertEqual(e.name, "非法数据地址")
    }
}

final class AddressTests: XCTestCase {
    func testFiveDigitParse() throws {
        let a = try TagAddress.parse("40001")
        XCTAssertEqual(a.area, .holdingRegisters)
        XCTAssertEqual(a.offset, 0)
        XCTAssertNil(a.bit)
        XCTAssertEqual(a.displayNumber, "40001")
    }

    func testBitParse() throws {
        let a = try TagAddress.parse("40001.1")
        XCTAssertEqual(a.area, .holdingRegisters)
        XCTAssertEqual(a.offset, 0)
        XCTAssertEqual(a.bit, 1)
        XCTAssertEqual(a.displayNumber, "40001.1")
    }

    func testAllAreas() throws {
        XCTAssertEqual(try TagAddress.parse("00001").area, .coils)
        XCTAssertEqual(try TagAddress.parse("10005").area, .discreteInputs)
        XCTAssertEqual(try TagAddress.parse("30010").offset, 9)
        XCTAssertEqual(try TagAddress.parse("49999").offset, 9998)
    }

    func testSixDigitExtended() throws {
        let a = try TagAddress.parse("400101")
        XCTAssertEqual(a.area, .holdingRegisters)
        XCTAssertEqual(a.offset, 100)
        let b = try TagAddress.parse("465536")
        XCTAssertEqual(b.offset, 65535)
        XCTAssertEqual(b.displayNumber, "465536")
    }

    func testErrors() {
        XCTAssertThrowsError(try TagAddress.parse("50001"))
        XCTAssertThrowsError(try TagAddress.parse("40001.16"))
        XCTAssertThrowsError(try TagAddress.parse("abc"))
        XCTAssertThrowsError(try TagAddress.parse("50000"))
        XCTAssertThrowsError(try TagAddress.parse("00000")) // 偏移 -1
    }
}

final class ByteOrderTests: XCTestCase {
    func testEncodeABCD() {
        // Float32 100.0 = 0x42C80000 → ABCD: [0x42C8, 0x0000]
        let regs = TagValue.float32(100.0).transmissionRegisters(order: .abcd)
        XCTAssertEqual(regs, [0x42C8, 0x0000])
    }

    func testEncodeCDAB() {
        let regs = TagValue.float32(100.0).transmissionRegisters(order: .cdab)
        XCTAssertEqual(regs, [0x0000, 0x42C8])
    }

    func testEncodeBADC() {
        let regs = TagValue.float32(100.0).transmissionRegisters(order: .badc)
        XCTAssertEqual(regs, [0xC842, 0x0000])
    }

    func testEncodeDCBA() {
        let regs = TagValue.float32(100.0).transmissionRegisters(order: .dcba)
        XCTAssertEqual(regs, [0x0000, 0xC842])
    }

    func testRoundTripAllOrders() {
        let orders: [ByteOrder] = [.abcd, .cdab, .badc, .dcba]
        for order in orders {
            let original = TagValue.float32(3.14159)
            let regs = original.transmissionRegisters(order: order)
            let words = order.canonicalWords(from: regs)
            let decoded = TagValue.from(bigEndianWords: words, type: .float32)
            XCTAssertEqual(decoded, original, "字节序 \(order) 往返失败")
        }
    }

    func testInt32Negative() {
        let value = TagValue.int32(-2)
        let regs = value.transmissionRegisters(order: .abcd)
        XCTAssertEqual(regs, [0xFFFF, 0xFFFE])
        let back = TagValue.from(bigEndianWords: ByteOrder.abcd.canonicalWords(from: regs), type: .int32)
        XCTAssertEqual(back, value)
    }

    func testFloat64SixteenBytes() {
        let value = TagValue.float64(2.718281828)
        let regs = value.transmissionRegisters(order: .abcd)
        XCTAssertEqual(regs.count, 4)
        let back = TagValue.from(bigEndianWords: ByteOrder.abcd.canonicalWords(from: regs), type: .float64)
        XCTAssertEqual(back, value)
    }

    func testValueParse() {
        XCTAssertEqual(TagValue.parse("42", type: .uint16), .uint16(42))
        XCTAssertEqual(TagValue.parse("0xFF", type: .uint16), .uint16(255))
        XCTAssertEqual(TagValue.parse("-1", type: .int16), .int16(-1))
        XCTAssertEqual(TagValue.parse("1.5", type: .float32), .float32(1.5))
        XCTAssertEqual(TagValue.parse("on", type: .bool), .bool(true))
        XCTAssertNil(TagValue.parse("99999", type: .uint16))
    }
}

final class TagModelTests: XCTestCase {
    func testTagPointAddressHelpers() {
        var tag = TagPoint()
        tag.addressNumber = 40010
        tag.bit = 3
        XCTAssertEqual(tag.displayAddress, "40010.3")
        XCTAssertEqual(tag.address.area, .holdingRegisters)
        XCTAssertEqual(tag.address.offset, 9)
    }

    func testSparseSnapshotRestore() {
        let store = SlaveDataStore()
        store.writeRegisters(area: .holdingRegisters, offset: 0, values: [65535])
        store.writeRegisters(area: .inputRegisters, offset: 9, values: [511])
        store.writeBits(area: .coils, offset: 4, values: [true])
        let snap = store.snapshot()
        XCTAssertEqual(snap.count, 3)

        let other = SlaveDataStore()
        other.restore(from: snap)
        XCTAssertEqual(other.value(area: .holdingRegisters, offset: 0), 65535)
        XCTAssertEqual(other.value(area: .inputRegisters, offset: 9), 511)
        XCTAssertEqual(other.value(area: .coils, offset: 4), 1)
    }

    func testSlaveExecuteFC03() throws {
        let slave = ModbusTCPSlave()
        slave.store.writeRegisters(area: .holdingRegisters, offset: 0, values: [0x1234, 0x5678])
        let request = ModbusCodec.readRequest(fc: 0x03, address: 0, count: 2)
        let result = try slave.execute(pdu: request)
        XCTAssertEqual(Array(result.pdu), [0x03, 0x04, 0x12, 0x34, 0x56, 0x78])
        XCTAssertFalse(result.isException)
    }

    func testSlaveExecuteFC10AndFC06() throws {
        let slave = ModbusTCPSlave()
        var write = Data([0x10])
        write.appendBE(100)
        write.appendBE(2)
        write.append(4)
        write.appendBE(0x00AA)
        write.appendBE(0x00BB)
        let result = try slave.execute(pdu: write)
        XCTAssertFalse(result.isException)
        XCTAssertEqual(slave.store.value(area: .holdingRegisters, offset: 100), 0x00AA)
        XCTAssertEqual(slave.store.value(area: .holdingRegisters, offset: 101), 0x00BB)

        var single = Data([0x06])
        single.appendBE(50)
        single.appendBE(1234)
        _ = try slave.execute(pdu: single)
        XCTAssertEqual(slave.store.value(area: .holdingRegisters, offset: 50), 1234)
    }

    func testSlaveExceptionIllegalAddress() throws {
        let slave = ModbusTCPSlave()
        let request = ModbusCodec.readRequest(fc: 0x03, address: 65530, count: 10)
        XCTAssertThrowsError(try slave.execute(pdu: request)) { error in
            XCTAssertEqual(error as? ModbusException, .illegalDataAddress)
        }
    }

    func testSlaveExceptionIllegalFunction() throws {
        let slave = ModbusTCPSlave()
        let request = Data([0x41, 0x00, 0x00, 0x00, 0x01])
        XCTAssertThrowsError(try slave.execute(pdu: request)) { error in
            XCTAssertEqual(error as? ModbusException, .illegalFunction)
        }
    }

    func testSlaveFC05WriteCoil() throws {
        let slave = ModbusTCPSlave()
        var pdu = Data([0x05])
        pdu.appendBE(7)
        pdu.appendBE(0xFF00)
        let result = try slave.execute(pdu: pdu)
        XCTAssertEqual(result.pdu, pdu)
        XCTAssertEqual(slave.store.value(area: .coils, offset: 7), 1)

        // 非法线圈值 → 异常 03
        var bad = Data([0x05])
        bad.appendBE(7)
        bad.appendBE(0x0002)
        XCTAssertThrowsError(try slave.execute(pdu: bad))
    }

    func testSlaveFC01ReadCoils() throws {
        let slave = ModbusTCPSlave()
        slave.store.writeBits(area: .coils, offset: 19, values: [true, false, true, true])
        let request = ModbusCodec.readRequest(fc: 0x01, address: 19, count: 4)
        let result = try slave.execute(pdu: request)
        XCTAssertEqual(Array(result.pdu), [0x01, 0x01, 0b0000_1101])
    }
}
