import Foundation

/// 基本计算引擎：双精度浮点，标准四则。
struct BasicEngine {
    private(set) var value: Double = 0
    private(set) var accumulator: Double = 0
    private(set) var pendingOp: BinaryOp?
    private(set) var isTyping = false
    private(set) var typingText = "0"
    private(set) var errorMessage: String?

    var display: String {
        if let message = errorMessage { return message }
        return isTyping ? CalcFormatter.typing(typingText) : CalcFormatter.decimal(value)
    }

    /// 待运算表达式行，如 "12 ×"。
    var expression: String? {
        guard let op = pendingOp else { return nil }
        return CalcFormatter.decimal(accumulator) + " " + op.symbol
    }

    mutating func inputDigit(_ digit: Int) {
        if errorMessage != nil { clearAll() }
        if !isTyping {
            typingText = "0"
            isTyping = true
        }
        if typingText == "0" {
            typingText = String(digit)
        } else if typingText == "-0" {
            typingText = "-" + String(digit)
        } else if typingText.count < 16 {
            typingText += String(digit)
        }
    }

    mutating func inputDot() {
        if errorMessage != nil { clearAll() }
        if !isTyping {
            typingText = "0"
            isTyping = true
        }
        if !typingText.contains(".") {
            typingText += "."
        }
    }

    mutating func negate() {
        if errorMessage != nil { return }
        if isTyping {
            typingText = typingText.hasPrefix("-") ? String(typingText.dropFirst()) : "-" + typingText
        } else {
            value = -value
        }
    }

    mutating func percent() {
        if errorMessage != nil { clearAll() }
        finishTyping()
        value /= 100
        isTyping = false
    }

    mutating func backspace() {
        guard errorMessage == nil, isTyping else { return }
        typingText.removeLast()
        if typingText.isEmpty || typingText == "-" {
            typingText = "0"
        }
    }

    mutating func inputBinaryOp(_ op: BinaryOp) {
        guard op.isBasicOp, errorMessage == nil else { return }
        finishTyping()
        if let pending = pendingOp {
            guard let result = pending.applyDouble(accumulator, value) else {
                setDivisionError()
                return
            }
            accumulator = result
        } else {
            accumulator = value
        }
        pendingOp = op
        isTyping = false
    }

    mutating func inputEquals() {
        guard errorMessage == nil else { return }
        finishTyping()
        if let pending = pendingOp {
            guard let result = pending.applyDouble(accumulator, value) else {
                setDivisionError()
                return
            }
            value = result
            pendingOp = nil
        }
        isTyping = false
    }

    mutating func clearEntry() {
        value = 0
        isTyping = false
        typingText = "0"
        errorMessage = nil
    }

    mutating func clearAll() {
        value = 0
        accumulator = 0
        pendingOp = nil
        isTyping = false
        typingText = "0"
        errorMessage = nil
    }

    private mutating func finishTyping() {
        if isTyping {
            value = Double(typingText) ?? value
            isTyping = false
        }
    }

    private mutating func setDivisionError() {
        errorMessage = "除数不能为零"
        value = 0
        accumulator = 0
        pendingOp = nil
        isTyping = false
        typingText = "0"
    }
}
