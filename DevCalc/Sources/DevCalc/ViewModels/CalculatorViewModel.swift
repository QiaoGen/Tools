import AppKit

/// 两种计算器模式。
enum CalcMode: String, CaseIterable, Identifiable {
    case basic
    case programmer

    var id: String { rawValue }

    var label: String {
        switch self {
        case .basic: "基本"
        case .programmer: "程序员"
        }
    }
}

@MainActor
@Observable
final class CalculatorViewModel {
    var mode: CalcMode = .programmer
    var programmer = ProgrammerEngine()
    var basic = BasicEngine()

    // MARK: - 程序员模式显示

    var wordSize: WordSize { programmer.wordSize }
    var inputBase: BaseRadix { programmer.inputBase }
    var signedMode: Bool { programmer.signedMode }

    func displayText(for base: BaseRadix) -> String {
        CalcFormatter.programmer(
            programmer.displayValue,
            base: base,
            word: programmer.wordSize,
            signed: programmer.signedMode
        )
    }

    var programmerExpression: String? { programmer.errorMessage == nil ? programmer.expression : nil }

    /// 位面板数据，MSB 在前。
    var bitArray: [Bool] {
        let word = programmer.wordSize
        return (0..<word.rawValue).reversed().map { programmer.displayValue & (1 << $0) != 0 }
    }

    // MARK: - 基本模式显示

    var basicDisplay: String { basic.display }
    var basicExpression: String? { basic.errorMessage == nil ? basic.expression : nil }

    // MARK: - 动作

    func inputDigit(_ digit: Int) {
        switch mode {
        case .programmer: programmer.inputDigit(digit)
        case .basic: basic.inputDigit(digit)
        }
    }

    func inputBinaryOp(_ op: BinaryOp) {
        switch mode {
        case .programmer: programmer.inputBinaryOp(op)
        case .basic: basic.inputBinaryOp(op)
        }
    }

    func inputUnary(_ op: UnaryOp) {
        programmer.inputUnary(op)
    }

    func inputEquals() {
        switch mode {
        case .programmer: programmer.inputEquals()
        case .basic: basic.inputEquals()
        }
    }

    func clearAll() {
        switch mode {
        case .programmer: programmer.clearAll()
        case .basic: basic.clearAll()
        }
    }

    func clearEntry() {
        switch mode {
        case .programmer: programmer.clearEntry()
        case .basic: basic.clearEntry()
        }
    }

    func backspace() {
        switch mode {
        case .programmer: programmer.backspace()
        case .basic: basic.backspace()
        }
    }

    func negate() {
        switch mode {
        case .programmer: programmer.inputUnary(.negate)
        case .basic: basic.negate()
        }
    }

    func percent() {
        basic.percent()
    }

    func inputDot() {
        basic.inputDot()
    }

    func setInputBase(_ base: BaseRadix) {
        programmer.setInputBase(base)
    }

    func setWordSize(_ size: WordSize) {
        programmer.setWordSize(size)
    }

    func setSignedMode(_ signed: Bool) {
        programmer.setSignedMode(signed)
    }

    func toggleBit(_ index: Int) {
        programmer.toggleBit(index)
    }

    /// 复制当前显示值（程序员模式复制当前进制原文，基本模式复制纯数字）。
    func copyValue() {
        let text: String
        switch mode {
        case .programmer:
            text = displayText(for: programmer.inputBase).replacing(" ", with: "")
        case .basic:
            text = basic.errorMessage == nil ? (basic.isTyping ? basic.typingText : String(basic.value)) : ""
        }
        guard !text.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
