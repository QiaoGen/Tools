import SwiftUI

/// 位翻转面板：每个 bit 一个可点击格子，MSB 在左上；16 位一行（8 位字长单行 8 格）。
struct BitPanelView: View {
    @Environment(CalculatorViewModel.self) private var vm

    var body: some View {
        let word = vm.wordSize
        let bits = vm.bitArray
        let perRow = word == .bits8 ? 8 : 16
        let rowCount = (bits.count + perRow - 1) / perRow

        VStack(spacing: 5) {
            ForEach(0..<rowCount, id: \.self) { row in
                bitRow(bits: bits, start: row * perRow, count: min(perRow, bits.count - row * perRow))
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 8)
        .animation(.easeInOut(duration: 0.12), value: vm.programmer.displayValue)
    }

    private func bitRow(bits: [Bool], start: Int, count: Int) -> some View {
        HStack(spacing: 10) {
            let msbIndex = vm.wordSize.rawValue - 1 - start
            Text("\(msbIndex)")
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(Theme.labelGray.opacity(0.6))
                .frame(width: 18, alignment: .trailing)
            HStack(spacing: 10) {
                ForEach(0..<((count + 7) / 8), id: \.self) { byteIndex in
                    HStack(spacing: 3) {
                        ForEach(0..<min(8, count - byteIndex * 8), id: \.self) { i in
                            bitCell(position: start + byteIndex * 8 + i, isSet: bits[start + byteIndex * 8 + i])
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity)
            Spacer(minLength: 18)
        }
    }

    private func bitCell(position: Int, isSet: Bool) -> some View {
        let bitIndex = vm.wordSize.rawValue - 1 - position
        return Button {
            vm.toggleBit(bitIndex)
        } label: {
            Text(isSet ? "1" : "0")
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(isSet ? .white : Theme.labelGray.opacity(0.7))
                .frame(width: 24, height: 22)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(isSet ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(Theme.bitCellClear))
                )
        }
        .buttonStyle(.plain)
        .help("点击翻转 bit \(bitIndex)")
    }
}
