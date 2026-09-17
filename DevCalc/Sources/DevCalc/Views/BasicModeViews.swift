import SwiftUI

/// 基本模式显示区：表达式行 + 大号数字。
struct BasicDisplayView: View {
    @Environment(CalculatorViewModel.self) private var vm

    var body: some View {
        VStack(alignment: .trailing, spacing: 6) {
            if let errorMessage = vm.basic.errorMessage {
                Text(errorMessage)
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(Color(nsColor: .systemRed))
            } else {
                if let expression = vm.basicExpression {
                    Text(expression)
                        .font(.calcMono(12, weight: .medium))
                        .foregroundStyle(Theme.labelGray)
                        .lineLimit(1)
                }
                Text(vm.basicDisplay)
                    .font(.system(size: 44, weight: .light))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.25)
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .animation(.easeInOut(duration: 0.15), value: vm.basicDisplay)
    }
}
