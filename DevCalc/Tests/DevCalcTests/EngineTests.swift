import XCTest
@testable import DevCalc

final class ProgrammerEngineTests: XCTestCase {

    // MARK: - 进制输入

    func testHexEntry() {
        var e = ProgrammerEngine()
        [7, 3].forEach { e.inputDigit($0) }
        XCTAssertEqual(e.displayValue, 0x73)
    }

    func testBaseSwitchPreservesValue() {
        var e = ProgrammerEngine()
        e.setInputBase(.dec)
        [1, 5].forEach { e.inputDigit($0) }  // 十进制输入 15
        e.setInputBase(.hex)
        XCTAssertEqual(CalcFormatter.programmer(e.displayValue, base: .hex, word: .bits64, signed: false), "F")
    }

    func testDigitIgnoredInWrongBase() {
        var e = ProgrammerEngine()
        e.setInputBase(.dec)
        e.inputDigit(15) // F 在十进制下无效
        XCTAssertEqual(e.displayValue, 0)
    }

    // MARK: - 字长与截断

    func testWordSizeMasking() {
        var e = ProgrammerEngine(wordSize: .bits8)
        [15, 15].forEach { e.inputDigit($0) }  // FF
        e.inputBinaryOp(.add)
        [1].forEach { e.inputDigit($0) }
        e.inputEquals()
        XCTAssertEqual(e.displayValue, 0x100 & 0xFF)  // 溢出回绕为 0
    }

    func testSwitchWordSizeTruncates() {
        var e = ProgrammerEngine()
        [1, 2, 3, 4].forEach { e.inputDigit($0) }  // 0x1234
        e.setWordSize(.bits8)
        XCTAssertEqual(e.displayValue, 0x34)
    }

    func testSignedDecimalDisplay() {
        let e = ProgrammerEngine(wordSize: .bits8, signedMode: true)
        let text = CalcFormatter.programmer(0xFF, base: .dec, word: .bits8, signed: e.signedMode)
        XCTAssertEqual(text, "-1")
        let unsigned = CalcFormatter.programmer(0xFF, base: .dec, word: .bits8, signed: false)
        XCTAssertEqual(unsigned, "255")
    }

    // MARK: - 位运算

    func testAnd() {
        var e = ProgrammerEngine(wordSize: .bits8)
        e.inputDigit(0xF)
        e.inputBinaryOp(.and)
        e.inputDigit(3)
        e.inputEquals()
        XCTAssertEqual(e.displayValue, 0xF & 3)
    }

    func testNand() {
        var e = ProgrammerEngine(wordSize: .bits8)
        e.inputDigit(0xF)
        e.inputBinaryOp(.nand)
        e.inputDigit(3)
        e.inputEquals()
        XCTAssertEqual(e.displayValue, ~(0xF & 0xF3) & 0xFF)  // 0xFC
    }

    func testRotateLeft8Bit() {
        var e = ProgrammerEngine(wordSize: .bits8)
        e.inputUnary(.not) // entry = FF
        e.toggleBit(7)     // 7F
        e.inputBinaryOp(.rol)
        e.inputDigit(1)
        e.inputEquals()    // RoL(7F,1) = FE
        XCTAssertEqual(e.displayValue, 0xFE)
    }

    func testRotateWrapsWithinWord() {
        let word = WordSize.bits8
        XCTAssertEqual(word.rotateLeft(0x81, by: 1), 0x03)
        XCTAssertEqual(word.rotateRight(0x03, by: 1), 0x81)
    }

    func testShiftBeyondWordWidth() {
        var e = ProgrammerEngine(wordSize: .bits8)
        e.inputDigit(1)
        e.inputBinaryOp(.shl)
        e.inputDigit(9)
        e.inputEquals()
        XCTAssertEqual(e.displayValue, 0)
    }

    func testNot() {
        var e = ProgrammerEngine(wordSize: .bits8)
        e.inputDigit(0)
        e.inputUnary(.not)
        XCTAssertEqual(e.displayValue, 0xFF)
    }

    // MARK: - 连续运算与错误

    func testOperatorReplace() {
        var e = ProgrammerEngine()
        e.inputDigit(5)
        e.inputBinaryOp(.add)
        e.inputBinaryOp(.mul)  // 替换 +
        e.inputDigit(3)
        e.inputEquals()
        XCTAssertEqual(e.displayValue, 15)
    }

    func testChainedOps() {
        var e = ProgrammerEngine()
        e.inputDigit(2)
        e.inputBinaryOp(.add)
        e.inputDigit(3)
        e.inputBinaryOp(.add)
        e.inputDigit(4)
        e.inputEquals()
        XCTAssertEqual(e.displayValue, 9)
    }

    func testDivisionByZero() {
        var e = ProgrammerEngine()
        e.inputDigit(5)
        e.inputBinaryOp(.div)
        e.inputDigit(0)
        e.inputEquals()
        XCTAssertNotNil(e.errorMessage)
        XCTAssertEqual(e.displayValue, 0)
    }

    func testRecoversFromErrorOnDigit() {
        var e = ProgrammerEngine()
        e.inputDigit(5)
        e.inputBinaryOp(.div)
        e.inputDigit(0)
        e.inputEquals()
        XCTAssertNotNil(e.errorMessage)
        e.inputDigit(7)
        XCTAssertNil(e.errorMessage)
        XCTAssertEqual(e.displayValue, 7)
    }

    // MARK: - 位翻转

    func testToggleBit() {
        var e = ProgrammerEngine()
        e.toggleBit(0)
        XCTAssertEqual(e.displayValue, 1)
        e.toggleBit(63)
        XCTAssertEqual(e.displayValue, 0x8000_0000_0000_0001)
    }

    func testToggleBitRespectsWordSize() {
        var e = ProgrammerEngine(wordSize: .bits8)
        e.toggleBit(63) // 超出字长，无效
        XCTAssertEqual(e.displayValue, 0)
    }

    // MARK: - 格式化

    func testHexGrouping() {
        let text = CalcFormatter.programmer(0x73BD5A2C, base: .hex, word: .bits64, signed: false)
        XCTAssertEqual(text, "73 BD 5A 2C")
    }

    func testDecGrouping() {
        let text = CalcFormatter.programmer(1_941_509_676, base: .dec, word: .bits64, signed: false)
        XCTAssertEqual(text, "1 941 509 676")
    }

    func testBinGrouping() {
        let text = CalcFormatter.programmer(0b11_1111, base: .bin, word: .bits64, signed: false)
        XCTAssertEqual(text, "11 1111")
    }

    func testOctGrouping() {
        let text = CalcFormatter.programmer(0o777, base: .oct, word: .bits64, signed: false)
        XCTAssertEqual(text, "777")
    }

    func testNegativeSignedDisplay() {
        let text = CalcFormatter.programmer(0xFFFF_FFFF_FFFF_FFF6, base: .dec, word: .bits64, signed: true)
        XCTAssertEqual(text, "-10")
    }
}

final class BasicEngineTests: XCTestCase {

    func testAddition() {
        var e = BasicEngine()
        e.inputDigit(1)
        e.inputDigit(2)
        e.inputBinaryOp(.add)
        e.inputDigit(3)
        e.inputEquals()
        XCTAssertEqual(e.value, 15)
    }

    func testDivisionByZero() {
        var e = BasicEngine()
        e.inputDigit(5)
        e.inputBinaryOp(.div)
        e.inputDigit(0)
        e.inputEquals()
        XCTAssertNotNil(e.errorMessage)
    }

    func testPercent() {
        var e = BasicEngine()
        e.inputDigit(5)
        e.inputDigit(0)
        e.percent()
        XCTAssertEqual(e.value, 0.5, accuracy: 1e-9)
    }

    func testDecimalDisplayGrouping() {
        XCTAssertEqual(CalcFormatter.decimal(1234567), "1 234 567")
        XCTAssertEqual(CalcFormatter.decimal(0.5), "0.5")
    }

    func testTypingGrouping() {
        XCTAssertEqual(CalcFormatter.typing("12345.6"), "12 345.6")
    }

    func testChainOps() {
        var e = BasicEngine()
        e.inputDigit(2)
        e.inputBinaryOp(.mul)
        e.inputDigit(3)
        e.inputBinaryOp(.add)
        e.inputDigit(1)
        e.inputEquals()
        XCTAssertEqual(e.value, 7, accuracy: 1e-9)
    }
}
