import SwiftUI

/// 进制显示区：HEX / DEC / OCT / BIN 四行同屏，点击行切换输入进制。
struct BaseDisplayView: View {
    @Environment(CalculatorViewModel.self) private var vm

    private struct RowConfig: Identifiable {
        let base: BaseRadix
        let fontSize: CGFloat
        let weight: Font.Weight
        var id: BaseRadix { base }
    }

    private static let rows: [RowConfig] = [
        RowConfig(base: .hex, fontSize: 24, weight: .semibold),
        RowConfig(base: .dec, fontSize: 36, weight: .light),
        RowConfig(base: .oct, fontSize: 17, weight: .regular),
        RowConfig(base: .bin, fontSize: 15, weight: .regular),
    ]

    var body: some View {
        VStack(alignment: .trailing, spacing: 2) {
            if let errorMessage = vm.programmer.errorMessage {
                Text(errorMessage)
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(Color(nsColor: .systemRed))
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.vertical, 20)
            } else {
                if let expression = vm.programmerExpression {
                    Text(expression)
                        .font(.calcMono(12, weight: .medium))
                        .foregroundStyle(Theme.labelGray)
                        .lineLimit(1)
                }
                ForEach(Self.rows) { row in
                    baseRow(row)
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 6)
        .padding(.bottom, 10)
        .animation(.easeInOut(duration: 0.15), value: vm.programmer.displayValue)
    }

    @ViewBuilder
    private func baseRow(_ row: RowConfig) -> some View {
        let isActive = vm.inputBase == row.base
        HStack(spacing: 8) {
            Capsule()
                .fill(isActive ? Theme.accent : .clear)
                .frame(width: 3, height: row.fontSize * 0.7)
            Text(row.base.label)
                .font(.system(size: 11, weight: isActive ? .bold : .medium, design: .monospaced))
                .foregroundStyle(isActive ? Theme.accent : Theme.labelGray)
                .frame(width: 34, alignment: .leading)
            Text(vm.displayText(for: row.base))
                .font(.calcMono(row.fontSize, weight: row.weight))
                .foregroundStyle(Color.primary.opacity(row.base == .dec ? 1 : 0.92))
                .lineLimit(1)
                .minimumScaleFactor(0.3)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .contentShape(Rectangle())
        .onTapGesture { vm.setInputBase(row.base) }
    }
}
