import SwiftUI

struct ContentView: View {
    @Environment(CalculatorViewModel.self) private var vm

    var body: some View {
        @Bindable var bindable = vm

        VStack(spacing: 8) {
            ControlBar(modeBinding: $bindable.mode)

            Rectangle()
                .fill(Theme.hairline)
                .frame(height: 1)
                .padding(.horizontal, 14)

            switch vm.mode {
            case .programmer:
                BaseDisplayView()
                BitPanelView()
            case .basic:
                BasicDisplayView()
            }

            KeypadView()
        }
        .padding(12)
        .frame(minWidth: 600, minHeight: 740)
        .frame(idealWidth: 640, idealHeight: 760)
        .background(Theme.windowBackground.ignoresSafeArea())
    }
}

/// 顶部控制行：模式切换 +（程序员模式）字长与符号切换。
struct ControlBar: View {
    @Binding var modeBinding: CalcMode
    @Environment(CalculatorViewModel.self) private var vm

    var body: some View {
        HStack(spacing: 10) {
            Picker("模式", selection: $modeBinding) {
                ForEach(CalcMode.allCases) { mode in
                    Text(mode.label).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 170)
            .tint(Theme.accent)

            Spacer()

            if vm.mode == .programmer {
                Picker("字长", selection: bindWordSize) {
                    ForEach(WordSize.allCases) { size in
                        Text(size.label).tag(size)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 230)
                .tint(Theme.accent)

                Picker("符号", selection: bindSigned) {
                    Text("无符号").tag(false)
                    Text("有符号").tag(true)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 140)
                .tint(Theme.accent)
            }
        }
        .padding(.horizontal, 4)
    }

    private var bindWordSize: Binding<WordSize> {
        Binding(
            get: { vm.wordSize },
            set: { vm.setWordSize($0) }
        )
    }

    private var bindSigned: Binding<Bool> {
        Binding(
            get: { vm.signedMode },
            set: { vm.setSignedMode($0) }
        )
    }
}
