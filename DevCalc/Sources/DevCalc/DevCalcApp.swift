import SwiftUI

@main
struct DevCalcApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var viewModel = CalculatorViewModel()

    var body: some Scene {
        WindowGroup("DevCalc") {
            ContentView()
                .environment(viewModel)
                .onAppear { appDelegate.viewModel = viewModel }
        }
        .windowResizability(.contentMinSize)
        .defaultSize(width: 640, height: 760)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var viewModel: CalculatorViewModel?
    private var keyMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleKeyEvent(event) ?? event
        }
    }

    /// 物理键盘映射：数字 / A–F（HEX 进制）/ 运算符 / 回车 / 退格 / Esc。
    private func handleKeyEvent(_ event: NSEvent) -> NSEvent? {
        guard let viewModel, event.window != nil else { return event }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

        if flags.contains(.command) {
            if flags.intersection([.shift, .control, .option]).isEmpty,
               event.charactersIgnoringModifiers == "c" {
                MainActor.assumeIsolated { viewModel.copyValue() }
                return nil
            }
            return event
        }
        guard !flags.contains(.control), !flags.contains(.option) else { return event }

        let key = event.charactersIgnoringModifiers?.lowercased() ?? ""
        let keyCode = event.keyCode

        // 功能键
        switch keyCode {
        case 36, 76: // Return / 小键盘 Enter
            MainActor.assumeIsolated { viewModel.inputEquals() }
            return nil
        case 51: // Delete（退格）
            MainActor.assumeIsolated { viewModel.backspace() }
            return nil
        case 117: // Forward Delete → CE
            MainActor.assumeIsolated { viewModel.clearEntry() }
            return nil
        case 53: // Esc → C
            MainActor.assumeIsolated { viewModel.clearAll() }
            return nil
        default:
            break
        }

        // 字符键
        let handled: Bool = MainActor.assumeIsolated {
            switch key {
            case "0"..."9":
                viewModel.inputDigit(Int(key)!)
                return true
            case "a", "b", "c", "d", "e", "f":
                if viewModel.mode == .programmer, viewModel.inputBase == .hex {
                    viewModel.inputDigit(Int(key.unicodeScalars.first!.value - UnicodeScalar("a").value) + 10)
                    return true
                }
                if viewModel.mode == .basic, key == "c" {
                    viewModel.clearAll()
                    return true
                }
                return false
            case "+":
                viewModel.inputBinaryOp(.add)
                return true
            case "-":
                viewModel.inputBinaryOp(.sub)
                return true
            case "*":
                viewModel.inputBinaryOp(.mul)
                return true
            case "/":
                viewModel.inputBinaryOp(.div)
                return true
            case "%":
                if viewModel.mode == .programmer {
                    viewModel.inputBinaryOp(.mod)
                } else {
                    viewModel.percent()
                }
                return true
            case "=", "\r":
                viewModel.inputEquals()
                return true
            case ".", ",":
                if viewModel.mode == .basic {
                    viewModel.inputDot()
                    return true
                }
                return false
            default:
                return false
            }
        }
        return handled ? nil : event
    }
}
