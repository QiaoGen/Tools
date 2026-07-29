import XCTest
@testable import LiteS7

final class LiteS7Tests: XCTestCase {
    func testParsesDBAndMarkerAddresses() throws {
        let db = try S7Address.parse("DB12.DBX4.3", valueType: .bool)
        XCTAssertEqual(db.area, .dataBlock)
        XCTAssertEqual(db.dbNumber, 12)
        XCTAssertEqual(db.bitAddress, 35)

        let marker = try S7Address.parse("MW10", valueType: .uint16)
        XCTAssertEqual(marker.area, .marker)
        XCTAssertEqual(marker.byteOffset, 10)
        XCTAssertNil(marker.bitOffset)
    }

    func testRejectsInvalidBitTypeCombination() {
        XCTAssertThrowsError(try S7Address.parse("DB1.DBX0.0", valueType: .uint16))
        XCTAssertThrowsError(try S7Address.parse("DB1.DBB0", valueType: .bool))
    }

    func testRoundTripsValues() throws {
        let cases: [(S7ValueType, String)] = [
            (.bool, "true"),
            (.uint8, "255"),
            (.int16, "-1234"),
            (.uint16, "65535"),
            (.int32, "-1234567"),
            (.uint32, "4000000000")
        ]

        for (type, value) in cases {
            let encoded = try S7ValueCodec.encode(value, as: type)
            XCTAssertEqual(try S7ValueCodec.decode(encoded, as: type), value)
        }

        let floatData = try S7ValueCodec.encode("12.5", as: .float32)
        XCTAssertEqual(try S7ValueCodec.decode(floatData, as: .float32), "12.5")
    }

    func testHexInput() throws {
        XCTAssertEqual(try S7ValueCodec.encode("0xBEEF", as: .uint16), Data([0xBE, 0xEF]))
    }

    func testBuildsCOTPConnectionRequest() async {
        let packet = await S7Client().makeCOTPConnectionRequest(rack: 0, slot: 2)
        XCTAssertEqual(
            packet,
            Data([0x03, 0x00, 0x00, 0x16, 0x11, 0xE0, 0x00, 0x00, 0x00, 0x01, 0x00,
                  0xC1, 0x02, 0x01, 0x00, 0xC2, 0x02, 0x01, 0x02, 0xC0, 0x01, 0x0A])
        )
    }

    func testBuildsReadRequest() async throws {
        let address = try S7Address.parse("DB1.DBW2", valueType: .uint16)
        let packet = await S7Client().makeReadRequest(address: address, valueType: .uint16)
        XCTAssertEqual(
            packet,
            Data([0x03, 0x00, 0x00, 0x1F, 0x02, 0xF0, 0x80, 0x32, 0x01, 0x00, 0x00,
                  0x00, 0x01, 0x00, 0x0E, 0x00, 0x00, 0x04, 0x01, 0x12, 0x0A, 0x10,
                  0x04, 0x00, 0x01, 0x00, 0x01, 0x84, 0x00, 0x00, 0x10])
        )
    }

    func testBuildsBitWriteRequest() async throws {
        let address = try S7Address.parse("M0.0", valueType: .bool)
        let packet = await S7Client().makeWriteRequest(address: address, valueType: .bool, data: Data([1]))
        XCTAssertEqual(
            packet,
            Data([0x03, 0x00, 0x00, 0x24, 0x02, 0xF0, 0x80, 0x32, 0x01, 0x00, 0x00,
                  0x00, 0x01, 0x00, 0x0E, 0x00, 0x05, 0x05, 0x01, 0x12, 0x0A, 0x10,
                  0x01, 0x00, 0x01, 0x00, 0x00, 0x83, 0x00, 0x00, 0x00, 0x00, 0x03,
                  0x00, 0x01, 0x01])
        )
    }
}
