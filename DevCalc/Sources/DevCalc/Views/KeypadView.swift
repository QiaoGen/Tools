import SwiftUI

/// 键盘按键描述。
struct KeySpec: Identifiable {
    let label: String
    let role: KeyRole
    var small: Bool = false
    var span: Int = 1
    let perform: (CalculatorViewModel) -> Void
    var isEnabled: (CalculatorViewModel) -> Bool = { _ in true }

    var id: String { label }
}

struct KeypadView: View {
    @Environment(CalculatorViewModel.self) private var vm

    var body: some View {
        switch vm.mode {
        case .programmer: ProgrammerKeypad()
        case .basic: BasicKeypad()
        }
    }
}

// MARK: - 程序员键盘

struct ProgrammerKeypad: View {
    @Environment(CalculatorViewModel.self) private var vm

    var body: some View {
        VStack(spacing: 6) {
            KeyGrid(rows: hexAndBitwiseRows)
            KeyGrid(rows: mainRows, expands: true)
        }
    }

    private var hexAndBitwiseRows: [[KeySpec]] {
        let hexEnabled: (CalculatorViewModel) -> Bool = { $0.inputBase == .hex }
        return [
            ["A", "B", "C", "D", "E", "F"].enumerated().map { offset, label in
                KeySpec(label: label, role: .hex, perform: { $0.inputDigit(10 + offset) }, isEnabled: hexEnabled)
            },
            [
                KeySpec(label: "AND", role: .function, small: true, perform: { $0.inputBinaryOp(.and) }),
                KeySpec(label: "OR", role: .function, small: true, perform: { $0.inputBinaryOp(.or) }),
                KeySpec(label: "XOR", role: .function, small: true, perform: { $0.inputBinaryOp(.xor) }),
                KeySpec(label: "NAND", role: .function, small: true, perform: { $0.inputBinaryOp(.nand) }),
                KeySpec(label: "NOR", role: .function, small: true, perform: { $0.inputBinaryOp(.nor) }),
                KeySpec(label: "NOT", role: .function, small: true, perform: { $0.inputUnary(.not) }),
            ],
            [
                KeySpec(label: "<<", role: .function, small: true, perform: { $0.inputBinaryOp(.shl) }),
                KeySpec(label: ">>", role: .function, small: true, perform: { $0.inputBinaryOp(.shr) }),
                KeySpec(label: "RoL", role: .function, small: true, perform: { $0.inputBinaryOp(.rol) }),
                KeySpec(label: "RoR", role: .function, small: true, perform: { $0.inputBinaryOp(.ror) }),
                KeySpec(label: "Mod", role: .function, small: true, perform: { $0.inputBinaryOp(.mod) }),
                KeySpec(label: "±", role: .function, small: true, perform: { $0.negate() }),
            ],
        ]
    }

    private var mainRows: [[KeySpec]] {
        let digit: (Int) -> KeySpec = { d in
            KeySpec(label: "\(d)", role: .digit, perform: { $0.inputDigit(d) })
        }
        return [
            [
                KeySpec(label: "CE", role: .function, perform: { $0.clearEntry() }),
                KeySpec(label: "C", role: .function, perform: { $0.clearAll() }),
                KeySpec(label: "⌫", role: .function, perform: { $0.backspace() }),
                KeySpec(label: "÷", role: .op, perform: { $0.inputBinaryOp(.div) }),
            ],
            [digit(7), digit(8), digit(9),
             KeySpec(label: "×", role: .op, perform: { $0.inputBinaryOp(.mul) })],
            [digit(4), digit(5), digit(6),
             KeySpec(label: "−", role: .op, perform: { $0.inputBinaryOp(.sub) })],
            [digit(1), digit(2), digit(3),
             KeySpec(label: "+", role: .op, perform: { $0.inputBinaryOp(.add) })],
            [
                KeySpec(label: "0", role: .digit, span: 2, perform: { $0.inputDigit(0) }),
                KeySpec(label: "=", role: .equals, span: 2, perform: { $0.inputEquals() }),
            ],
        ]
    }
}

// MARK: - 基本键盘

struct BasicKeypad: View {
    @Environment(CalculatorViewModel.self) private var vm

    var body: some View {
        KeyGrid(rows: rows, expands: true)
    }

    private var rows: [[KeySpec]] {
        let digit: (Int) -> KeySpec = { d in
            KeySpec(label: "\(d)", role: .digit, perform: { $0.inputDigit(d) })
        }
        return [
            [
                KeySpec(label: "C", role: .function, perform: { $0.clearAll() }),
                KeySpec(label: "±", role: .function, perform: { $0.negate() }),
                KeySpec(label: "%", role: .function, perform: { $0.percent() }),
                KeySpec(label: "÷", role: .op, perform: { $0.inputBinaryOp(.div) }),
            ],
            [digit(7), digit(8), digit(9),
             KeySpec(label: "×", role: .op, perform: { $0.inputBinaryOp(.mul) })],
            [digit(4), digit(5), digit(6),
             KeySpec(label: "−", role: .op, perform: { $0.inputBinaryOp(.sub) })],
            [digit(1), digit(2), digit(3),
             KeySpec(label: "+", role: .op, perform: { $0.inputBinaryOp(.add) })],
            [
                KeySpec(label: "0", role: .digit, perform: { $0.inputDigit(0) }),
                KeySpec(label: ".", role: .digit, perform: { $0.inputDot() }),
                KeySpec(label: "⌫", role: .function, perform: { $0.backspace() }),
                KeySpec(label: "=", role: .equals, perform: { $0.inputEquals() }),
            ],
        ]
    }
}

// MARK: - 通用部件

struct KeyButton: View {
    @Environment(CalculatorViewModel.self) private var vm
    let key: KeySpec
    var expands = false

    var body: some View {
        let enabled = key.isEnabled(vm)
        Button {
            key.perform(vm)
        } label: {
            Text(key.label)
                .font(key.small ? .system(size: 12, weight: .semibold) : .system(size: 18, weight: .medium))
                .foregroundStyle(Theme.keyForeground(for: key.role))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .frame(maxWidth: .infinity)
                .frame(minHeight: key.small ? 36 : 46, maxHeight: expands ? .infinity : nil)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Theme.keyBackground(for: key.role))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(Theme.hairline, lineWidth: 1)
                )
                .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(KeyPressStyle())
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.35)
    }
}

struct KeyPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .opacity(configuration.isPressed ? 0.8 : 1)
            .animation(.easeOut(duration: 0.06), value: configuration.isPressed)
    }
}

struct KeyGrid: View {
    @Environment(CalculatorViewModel.self) private var vm
    let rows: [[KeySpec]]
    var expands = false

    var body: some View {
        Grid(horizontalSpacing: 6, verticalSpacing: 6) {
            ForEach(rows.indices, id: \.self) { rowIndex in
                GridRow {
                    ForEach(rows[rowIndex]) { key in
                        KeyButton(key: key, expands: expands)
                            .gridCellColumns(key.span)
                    }
                }
            }
        }
        .frame(maxHeight: expands ? .infinity : nil)
    }
}
