import SwiftUI

private enum Palette {
    static let canvas = Color(red: 0.045, green: 0.065, blue: 0.075)
    static let panel = Color(red: 0.075, green: 0.105, blue: 0.115)
    static let raised = Color(red: 0.095, green: 0.135, blue: 0.145)
    static let line = Color.white.opacity(0.11)
    static let text = Color(red: 0.90, green: 0.93, blue: 0.90)
    static let muted = Color(red: 0.55, green: 0.62, blue: 0.61)
    static let cyan = Color(red: 0.24, green: 0.84, blue: 0.78)
    static let amber = Color(red: 0.98, green: 0.67, blue: 0.20)
    static let red = Color(red: 0.98, green: 0.35, blue: 0.31)
}

struct ContentView: View {
    @EnvironmentObject private var model: AppModel
    @State private var showingAddressHelp = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(Palette.line)
            connectionStrip
            Divider().overlay(Palette.line)
            HSplitView {
                VStack(spacing: 0) {
                    operationPanel
                    Divider().overlay(Palette.line)
                    resultPanel
                    Divider().overlay(Palette.line)
                    framePanel
                }
                .frame(minWidth: 740)

                historyPanel
                    .frame(minWidth: 310, idealWidth: 340, maxWidth: 420)
            }
            footer
        }
        .background(Palette.canvas)
        .foregroundStyle(Palette.text)
        .fontDesign(.monospaced)
        .sheet(isPresented: $showingAddressHelp) { addressHelp }
    }

    private var header: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 5)
                    .fill(Palette.cyan)
                    .frame(width: 31, height: 31)
                Text("S7")
                    .font(.system(size: 13, weight: .black, design: .rounded))
                    .foregroundStyle(Palette.canvas)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text("LITE S7")
                    .font(.system(size: 17, weight: .black, design: .rounded))
                    .tracking(1.4)
                Text("PLC MEMORY CONSOLE")
                    .font(.system(size: 9, weight: .semibold))
                    .tracking(2.2)
                    .foregroundStyle(Palette.muted)
            }
            Spacer()
            statusPill
            Button {
                showingAddressHelp = true
            } label: {
                Label("地址说明", systemImage: "questionmark.circle")
            }
            .buttonStyle(.plain)
            .foregroundStyle(Palette.muted)
        }
        .padding(.horizontal, 18)
        .frame(height: 58)
        .background(Palette.panel)
    }

    private var statusPill: some View {
        HStack(spacing: 7) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
                .shadow(color: statusColor.opacity(0.8), radius: 5)
            Text(model.connectionState.title.uppercased())
                .font(.system(size: 11, weight: .bold))
                .tracking(0.7)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(statusColor.opacity(0.09), in: Capsule())
        .overlay(Capsule().stroke(statusColor.opacity(0.4)))
    }

    private var connectionStrip: some View {
        HStack(spacing: 14) {
            fieldLabel("PLC 地址")
            TextField("192.168.0.1", text: $model.configuration.host)
                .textFieldStyle(ConsoleFieldStyle())
                .frame(minWidth: 150, idealWidth: 190, maxWidth: 240)
                .disabled(model.connectionState == .connected)

            fieldLabel("端口")
            TextField("102", value: $model.configuration.port, format: .number.grouping(.never))
                .textFieldStyle(ConsoleFieldStyle())
                .frame(width: 72)
                .disabled(model.connectionState == .connected)

            fieldLabel("Rack")
            Stepper(value: $model.configuration.rack, in: 0...7) {
                Text("\(model.configuration.rack)").frame(width: 20)
            }
            .disabled(model.connectionState == .connected)

            fieldLabel("Slot")
            Stepper(value: $model.configuration.slot, in: 0...31) {
                Text("\(model.configuration.slot)").frame(width: 24)
            }
            .disabled(model.connectionState == .connected)

            Spacer()

            if model.connectionState == .connected {
                Button("断开连接") { model.disconnect() }
                    .buttonStyle(ConsoleSecondaryButtonStyle())
            } else {
                Button {
                    Task { await model.connect() }
                } label: {
                    Label("建立连接", systemImage: "bolt.horizontal.fill")
                }
                .buttonStyle(ConsolePrimaryButtonStyle())
                .disabled(model.isBusy)
            }
        }
        .padding(.horizontal, 18)
        .frame(height: 66)
        .background(Palette.canvas)
    }

    private var operationPanel: some View {
        VStack(alignment: .leading, spacing: 15) {
            sectionTitle(index: "01", title: "MEMORY OPERATION", subtitle: "单点读写")

            HStack(alignment: .bottom, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    fieldLabel("S7 地址")
                    TextField("DB1.DBW0", text: $model.addressText)
                        .textFieldStyle(ConsoleFieldStyle(accent: Palette.cyan))
                        .font(.system(size: 18, weight: .bold, design: .monospaced))
                }
                .frame(minWidth: 180)

                VStack(alignment: .leading, spacing: 6) {
                    fieldLabel("数据类型")
                    Picker("", selection: $model.valueType) {
                        ForEach(S7ValueType.allCases) { type in
                            Text(type.rawValue).tag(type)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 106)
                }

                VStack(alignment: .leading, spacing: 6) {
                    fieldLabel("写入值")
                    TextField(model.valueType.placeholder, text: $model.writeValue)
                        .textFieldStyle(ConsoleFieldStyle(accent: Palette.amber))
                }
                .frame(minWidth: 125)

                Button {
                    Task { await model.readOnce() }
                } label: {
                    Label("读取", systemImage: "arrow.down.to.line.compact")
                        .frame(minWidth: 58)
                }
                .buttonStyle(ConsolePrimaryButtonStyle())
                .disabled(model.connectionState != .connected || model.isBusy)

                Button {
                    Task { await model.writeOnce() }
                } label: {
                    Label("写入", systemImage: "arrow.up.to.line.compact")
                        .frame(minWidth: 58)
                }
                .buttonStyle(ConsoleWarningButtonStyle())
                .disabled(model.connectionState != .connected || model.isBusy)
            }

            HStack(spacing: 10) {
                Text("快速：")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Palette.muted)
                quickAddress("DB1.DBW0", type: .uint16)
                quickAddress("DB1.DBD0", type: .float32)
                quickAddress("M0.0", type: .bool)
                quickAddress("MW0", type: .uint16)
                quickAddress("IB0", type: .uint8)
                quickAddress("IW0", type: .uint16)
                Spacer()
                Toggle("连续读取", isOn: Binding(
                    get: { model.isPolling },
                    set: { model.setPolling($0) }
                ))
                .toggleStyle(.switch)
                .controlSize(.small)
                Stepper(value: $model.pollIntervalMilliseconds, in: 100...5000, step: 100) {
                    Text("\(model.pollIntervalMilliseconds) ms")
                        .foregroundStyle(Palette.muted)
                        .frame(width: 72, alignment: .trailing)
                }
                .disabled(model.isPolling)
            }
        }
        .padding(18)
        .background(Palette.panel)
    }

    private var resultPanel: some View {
        VStack(alignment: .leading, spacing: 13) {
            sectionTitle(index: "02", title: "LIVE VALUE", subtitle: "实时结果")
            if let result = model.currentRead {
                HStack(spacing: 0) {
                    metric(label: "ADDRESS", value: result.address, color: Palette.cyan)
                    metricDivider
                    metric(label: "VALUE", value: result.value, color: Palette.text, large: true)
                    metricDivider
                    metric(label: "HEX", value: result.hex, color: Palette.amber)
                    metricDivider
                    metric(label: "BINARY", value: result.binary, color: Palette.muted)
                    metricDivider
                    metric(label: "LATENCY", value: "\(result.elapsedMilliseconds) ms", color: Palette.cyan)
                }
                .padding(.vertical, 13)
                .background(Palette.raised, in: RoundedRectangle(cornerRadius: 7))
                .overlay(RoundedRectangle(cornerRadius: 7).stroke(Palette.line))
            } else {
                HStack(spacing: 10) {
                    Image(systemName: "waveform.path.ecg")
                    Text("待读取数据")
                }
                .foregroundStyle(Palette.muted)
                .frame(maxWidth: .infinity, minHeight: 64)
                .background(Palette.raised.opacity(0.55), in: RoundedRectangle(cornerRadius: 7))
            }
        }
        .padding(18)
        .background(Palette.panel)
    }

    private var framePanel: some View {
        VStack(spacing: 0) {
            HStack {
                sectionTitle(index: "03", title: "PROTOCOL FRAMES", subtitle: "协议帧")
                Spacer()
                Text("\(model.frames.count) FRAMES")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Palette.muted)
                Button("清空") { model.clearFrames() }
                    .buttonStyle(.plain)
                    .foregroundStyle(Palette.muted)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 7) {
                    ForEach(model.frames.reversed()) { frame in
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Text(frame.direction.rawValue)
                                .font(.system(size: 10, weight: .black))
                                .foregroundStyle(frameColor(frame.direction))
                                .frame(width: 32, alignment: .leading)
                            Text(frame.timestamp, format: .dateTime.hour().minute().second())
                                .font(.system(size: 10))
                                .foregroundStyle(Palette.muted)
                            Text(frame.bytes)
                                .font(.system(size: 11, design: .monospaced))
                                .textSelection(.enabled)
                                .foregroundStyle(Palette.text.opacity(0.88))
                        }
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Color.black.opacity(0.18))
        }
        .frame(minHeight: 170)
        .background(Palette.canvas)
    }

    private var historyPanel: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("QUICK HISTORY")
                        .font(.system(size: 13, weight: .black))
                        .tracking(1)
                    Text("最近操作 · 点击即可复用")
                        .font(.system(size: 10))
                        .foregroundStyle(Palette.muted)
                }
                Spacer()
                Button("清空") { model.clearHistory() }
                    .buttonStyle(.plain)
                    .foregroundStyle(Palette.muted)
                    .disabled(model.history.isEmpty)
            }
            .padding(16)
            .background(Palette.raised)

            if model.history.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 28, weight: .light))
                    Text("完成读写后，操作会保留在这里")
                        .font(.system(size: 11))
                }
                .foregroundStyle(Palette.muted)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(model.history) { item in
                            historyRow(item)
                        }
                    }
                    .padding(10)
                }
            }
        }
        .background(Palette.panel)
    }

    private var footer: some View {
        HStack(spacing: 9) {
            Image(systemName: model.statusMessage.contains("失败") || model.statusMessage.contains("错误") ? "exclamationmark.triangle.fill" : "terminal.fill")
                .foregroundStyle(statusColor)
            Text(model.statusMessage)
                .lineLimit(1)
            Spacer()
            Text("S7COMM · RFC1006 · TCP/102")
                .tracking(0.6)
                .foregroundStyle(Palette.muted)
        }
        .font(.system(size: 10, weight: .medium))
        .padding(.horizontal, 14)
        .frame(height: 30)
        .background(Palette.raised)
        .overlay(alignment: .top) { Rectangle().fill(Palette.line).frame(height: 1) }
    }

    private var addressHelp: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("S7 地址速查")
                .font(.system(size: 22, weight: .black, design: .rounded))
            Text("地址本身决定存储位置，数据类型决定读取和解释的字节数。BOOL 必须包含位号。")
                .foregroundStyle(Palette.muted)
            Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 12) {
                helpRow("DB1.DBX0.0", "DB1 的第 0 字节第 0 位", "BOOL")
                helpRow("DB1.DBB0", "DB1 的第 0 字节", "BYTE")
                helpRow("DB1.DBW2", "DB1 从第 2 字节开始", "INT / WORD")
                helpRow("DB1.DBD4", "DB1 从第 4 字节开始", "DINT / DWORD / REAL")
                helpRow("M0.0 / MB0", "M 区位 / 字节", "BOOL / BYTE")
                helpRow("IW0 / ID0", "输入区，只读", "WORD / DWORD")
                helpRow("QW0 / QD0", "输出区，只读", "WORD / DWORD")
            }
            Text("提示：S7-1200/1500 需要关闭“优化的块访问”，并在保护设置中允许 PUT/GET 通信。")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Palette.amber)
            HStack {
                Spacer()
                Button("知道了") { showingAddressHelp = false }
                    .buttonStyle(ConsolePrimaryButtonStyle())
            }
        }
        .padding(28)
        .frame(width: 620)
        .background(Palette.panel)
        .foregroundStyle(Palette.text)
    }

    @ViewBuilder
    private func helpRow(_ address: String, _ meaning: String, _ type: String) -> some View {
        GridRow {
            Text(address).foregroundStyle(Palette.cyan)
            Text(meaning)
            Text(type).foregroundStyle(Palette.muted)
        }
    }

    private func historyRow(_ item: OperationHistory) -> some View {
        Button {
            model.loadHistory(item)
        } label: {
            VStack(alignment: .leading, spacing: 9) {
                HStack {
                    Text(item.kind.rawValue)
                        .font(.system(size: 9, weight: .black))
                        .foregroundStyle(item.kind == .read ? Palette.cyan : Palette.amber)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background((item.kind == .read ? Palette.cyan : Palette.amber).opacity(0.1), in: Capsule())
                    Text(item.address)
                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                    Spacer()
                    Circle()
                        .fill(item.success ? Palette.cyan : Palette.red)
                        .frame(width: 6, height: 6)
                }
                HStack {
                    Text(item.valueType.rawValue)
                        .foregroundStyle(Palette.muted)
                    Text(item.value)
                        .foregroundStyle(Palette.text)
                        .lineLimit(1)
                    Spacer()
                    Text("\(item.elapsedMilliseconds) ms")
                        .foregroundStyle(Palette.muted)
                }
                .font(.system(size: 10))
                Text(item.timestamp, format: .dateTime.month().day().hour().minute().second())
                    .font(.system(size: 9))
                    .foregroundStyle(Palette.muted.opacity(0.8))
            }
            .padding(11)
            .background(Palette.raised, in: RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(Palette.line))
        }
        .buttonStyle(.plain)
    }

    private func quickAddress(_ address: String, type: S7ValueType) -> some View {
        Button(address) {
            model.addressText = address
            model.valueType = type
        }
        .buttonStyle(.plain)
        .font(.system(size: 10, weight: .semibold))
        .foregroundStyle(Palette.muted)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(Palette.raised, in: RoundedRectangle(cornerRadius: 4))
        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Palette.line))
    }

    private func metric(label: String, value: String, color: Color, large: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(label)
                .font(.system(size: 8, weight: .bold))
                .tracking(1.3)
                .foregroundStyle(Palette.muted)
            Text(value)
                .font(.system(size: large ? 21 : 13, weight: large ? .black : .semibold, design: .monospaced))
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .textSelection(.enabled)
        }
        .padding(.horizontal, 15)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var metricDivider: some View {
        Rectangle().fill(Palette.line).frame(width: 1, height: 43)
    }

    private func sectionTitle(index: String, title: String, subtitle: String) -> some View {
        HStack(spacing: 9) {
            Text(index)
                .font(.system(size: 9, weight: .black))
                .foregroundStyle(Palette.canvas)
                .frame(width: 23, height: 18)
                .background(Palette.cyan, in: RoundedRectangle(cornerRadius: 3))
            Text(title)
                .font(.system(size: 11, weight: .black))
                .tracking(1.3)
            Text("/ \(subtitle)")
                .font(.system(size: 10))
                .foregroundStyle(Palette.muted)
        }
    }

    private func fieldLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 9, weight: .bold))
            .tracking(0.8)
            .foregroundStyle(Palette.muted)
    }

    private var statusColor: Color {
        switch model.connectionState {
        case .connected: Palette.cyan
        case .connecting: Palette.amber
        case .failed: Palette.red
        case .disconnected: Palette.muted
        }
    }

    private func frameColor(_ direction: ProtocolFrame.Direction) -> Color {
        switch direction {
        case .transmit: Palette.amber
        case .receive: Palette.cyan
        case .info: Palette.muted
        }
    }
}

private struct ConsoleFieldStyle: TextFieldStyle {
    var accent: Color = Palette.line

    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .textFieldStyle(.plain)
            .padding(.horizontal, 10)
            .frame(height: 34)
            .background(Color.black.opacity(0.2), in: RoundedRectangle(cornerRadius: 5))
            .overlay(RoundedRectangle(cornerRadius: 5).stroke(accent.opacity(accent == Palette.line ? 1 : 0.42)))
    }
}

private struct ConsolePrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .bold))
            .padding(.horizontal, 14)
            .frame(height: 34)
            .foregroundStyle(Palette.canvas)
            .background(Palette.cyan.opacity(configuration.isPressed ? 0.72 : 1), in: RoundedRectangle(cornerRadius: 5))
    }
}

private struct ConsoleWarningButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .bold))
            .padding(.horizontal, 14)
            .frame(height: 34)
            .foregroundStyle(Palette.canvas)
            .background(Palette.amber.opacity(configuration.isPressed ? 0.72 : 1), in: RoundedRectangle(cornerRadius: 5))
    }
}

private struct ConsoleSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .bold))
            .padding(.horizontal, 14)
            .frame(height: 34)
            .foregroundStyle(Palette.text)
            .background(Palette.raised, in: RoundedRectangle(cornerRadius: 5))
            .overlay(RoundedRectangle(cornerRadius: 5).stroke(Palette.line))
    }
}
