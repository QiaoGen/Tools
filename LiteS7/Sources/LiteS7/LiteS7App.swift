import SwiftUI

@main
struct LiteS7App: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(model)
                .frame(minWidth: 1_140, minHeight: 720)
                .preferredColorScheme(.dark)
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(after: .newItem) {
                Button("读取当前地址") {
                    Task { await model.readOnce() }
                }
                .keyboardShortcut("r", modifiers: [.command])
                Button("写入当前地址") {
                    Task { await model.writeOnce() }
                }
                .keyboardShortcut("w", modifiers: [.command, .shift])
            }
        }
    }
}
