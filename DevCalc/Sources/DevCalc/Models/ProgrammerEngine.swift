import Foundation

/// 程序员计算引擎：64 位位模式存储，按字长截断，立即执行（无括号递归）。
struct ProgrammerEngine {
    private(set) var accumulator: UInt64 = 0
    private(set) var pendingOp: BinaryOp?
    private(set) var entry: UInt64 = 0
    private(set) var isTyping = false
    private(set) var wordSize: WordSize = .bits64
    private(set) var signedMode = false
    private(set) var inputBase: BaseRadix = .hex
    private(set) var errorMessage: String?

    /// 当前显示值（正在输入的数或最近一次结果）。
    var displayValue: UInt64 { entry }

    /// 待运算表达式行，如 "7F AND"。
    var expression: String? {
        guard let op = pendingOp else { return nil }
        return CalcFormatter.programmer(accumulator, base: inputBase, word: wordSize, signed: signedMode)
            + " " + op.symbol
    }

    init(wordSize: WordSize = .bits64, signedMode: Bool = false, inputBase: BaseRadix = .hex) {
        self.wordSize = wordSize
        self.signedMode = signedMode
        self.inputBase = inputBase
    }

    mutating func inputDigit(_ digit: Int) {
        if errorMessage != nil { clearAll() }
        guard digit >= 0, digit < inputBase.rawValue else { return }
        if !isTyping {
            entry = 0
            isTyping = true
        }
        entry = ((entry &* UInt64(inputBase.rawValue)) &+ UInt64(digit)) & wordSize.mask
    }

    mutating func inputBinaryOp(_ op: BinaryOp) {
        guard errorMessage == nil else { return }
        if let pending = pendingOp {
            if isTyping {
                guard let result = pending.apply(accumulator, entry, word: wordSize) else {
                    setDivisionError()
                    return
                }
                accumulator = result
            } else {
                // 连续按运算符：替换待运算符，不重复计算
                pendingOp = op
                return
            }
        } else {
            accumulator = entry
        }
        pendingOp = op
        isTyping = false
    }

    mutating func inputEquals() {
        guard errorMessage == nil else { return }
        guard let pending = pendingOp else {
            isTyping = false
            return
        }
        guard let result = pending.apply(accumulator, entry, word: wordSize) else {
            setDivisionError()
            return
        }
        accumulator = result
        entry = result
        pendingOp = nil
        isTyping = false
    }

    mutating func inputUnary(_ op: UnaryOp) {
        guard errorMessage == nil else { return }
        entry = op.apply(entry, word: wordSize)
        isTyping = false
    }

    /// 位翻转面板：翻转第 index 位（0 为最低位）。
    mutating func toggleBit(_ index: Int) {
        guard errorMessage == nil, index >= 0, index < wordSize.rawValue else { return }
        entry ^= (1 << index)
        isTyping = false
    }

    mutating func backspace() {
        guard errorMessage == nil, isTyping else { return }
        entry = (entry / UInt64(inputBase.rawValue)) & wordSize.mask
    }

    mutating func clearEntry() {
        entry = 0
        isTyping = false
        errorMessage = nil
    }

    mutating func clearAll() {
        self = ProgrammerEngine(wordSize: wordSize, signedMode: signedMode, inputBase: inputBase)
    }

    mutating func setInputBase(_ base: BaseRadix) {
        inputBase = base
    }

    /// 切换字长时把已有值截断到新字长。
    mutating func setWordSize(_ size: WordSize) {
        wordSize = size
        entry &= size.mask
        accumulator &= size.mask
    }

    mutating func setSignedMode(_ signed: Bool) {
        signedMode = signed
    }

    private mutating func setDivisionError() {
        errorMessage = "除数不能为零"
        accumulator = 0
        pendingOp = nil
        entry = 0
        isTyping = false
    }
}
