import SwiftUI

@main
struct LiteModbusApp: App {
    var body: some Scene {
        WindowGroup("LiteModbus — Modbus TCP 调试工具") {
            ContentView()
                .frame(minWidth: 1120, minHeight: 720)
        }
        .defaultSize(width: 1280, height: 800)
        .windowToolbarStyle(.unified)
    }
}
