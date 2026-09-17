import SwiftUI
import UniformTypeIdentifiers

/// 从站·寄存器仿真页。
struct SlaveView: View {
    @ObservedObject var viewModel: SlaveViewModel

    @State private var exportDocument: SnapshotDocument?
    @State private var showImporter = false
    @State private var importError: String?

    private enum Col {
        static let addr: CGFloat = 76
        static let name: CGFloat = 170
        static let word: CGFloat = 84
        static let hex: CGFloat = 78
        static let unsigned: CGFloat = 84
        static let signed: CGFloat = 84
        static let float: CGFloat = 84
    }

    var body: some View {
        VStack(spacing: 0) {
            statsBar
            Divider().overlay(Theme.hairline)
            controlBar
            Divider().overlay(Theme.hairline)
            areaPicker
            Divider().overlay(Theme.hairline)
            table
        }
        .background(Theme.panelBackground)
        .toolbar {
            ToolbarItem(placement: .principal) {
                HStack(spacing: 6) {
                    Text("从站监听")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(Theme.labelGray)
                    TextField("端口", value: $viewModel.port, format: .number)
                        .font(.mono(12))
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 58)
                        .disabled(viewModel.isRunning)
                    TextField("Unit ID（如 1 或 1-247）", text: $viewModel.unitIdsText)
                        .font(.mono(12))
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 110)
                        .disabled(viewModel.isRunning)
                    Button {
                        viewModel.toggleRun()
                    } label: {
                        Label(viewModel.isRunning ? "停止监听" : "启动监听",
                              systemImage: viewModel.isRunning ? "stop.fill" : "play.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(viewModel.isRunning ? Theme.error : Theme.accent)
                    .foregroundColor(viewModel.isRunning ? .white : .white)
                    TextField("响应延迟 ms", value: $viewModel.responseDelayMs, format: .number)
                        .font(.mono(12))
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 58)
                        .help("模拟响应延迟，调试主站超时")
                }
            }
        }
        .fileExporter(isPresented: Binding(
            get: { exportDocument != nil },
            set: { if !$0 { exportDocument = nil } }
        ), document: exportDocument, contentType: .json, defaultFilename: "slave-snapshot.json") { _ in
            exportDocument = nil
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.json]) { result in
            if case .success(let url) = result {
                let accessible = url.startAccessingSecurityScopedResource()
                defer { if accessible { url.stopAccessingSecurityScopedResource() } }
                do {
                    let data = try Data(contentsOf: url)
                    let entries = try JSONDecoder().decode([SlaveDataStore.SparseEntry].self, from: data)
                    viewModel.importSnapshot(entries)
                    importError = nil
                } catch {
                    importError = "快照导入失败：\(error.localizedDescription)"
                }
            }
        }
        .alert("快照导入失败", isPresented: Binding(
            get: { importError != nil },
            set: { if !$0 { importError = nil } }
        )) {
            Button("好的", role: .cancel) {}
        } message: {
            Text(importError ?? "")
        }
    }

    // MARK: - 统计条

    private var statsBar: some View {
        HStack(spacing: 12) {
            statCard("活动连接", "\(viewModel.activeConnections)", icon: "link")
            statCard("总请求数", "\(viewModel.requests)", icon: "number")
            statCard("异常响应", "\(viewModel.exceptions)", icon: "exclamationmark.triangle",
                     color: viewModel.exceptions > 0 ? Theme.warning : Theme.labelGray)
            statCard("每秒请求", String(format: "%.0f", viewModel.ratePerSecond), icon: "speedometer")
            Spacer()
            if let importError = importError {
                Text(importError).font(.system(size: 10)).foregroundColor(Theme.error)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func statCard(_ title: String, _ value: String, icon: String, color: Color? = nil) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundColor(Theme.accent.opacity(0.8))
            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .font(.system(size: 10))
                    .foregroundColor(Theme.labelGray)
                Text(value)
                    .font(.mono(14, weight: .semibold))
                    .foregroundColor(color ?? Theme.primaryText)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 8).fill(Theme.cardBackground)
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.hairline, lineWidth: 1)))
    }

    // MARK: - 控制条

    private var controlBar: some View {
        HStack(spacing: 8) {
            Text("显示范围")
                .font(.system(size: 12))
                .foregroundColor(Theme.labelGray)
            TextField("起始", text: startBinding)
                .font(.mono(12))
                .textFieldStyle(.roundedBorder)
                .frame(width: 84)
            Text("×")
                .font(.system(size: 12))
                .foregroundColor(Theme.labelGray)
            Stepper("数量 \(viewModel.rangeCount[viewModel.selectedArea] ?? 16)",
                    value: Binding(
                        get: { viewModel.rangeCount[viewModel.selectedArea] ?? 16 },
                        set: { viewModel.rangeCount[viewModel.selectedArea] = $0; viewModel.rebuildRows() }
                    ), in: 1...500)
                .font(.system(size: 12))
            Spacer()
            SmallButton(title: "导出快照", icon: "square.and.arrow.up") {
                exportDocument = SnapshotDocument(entries: viewModel.exportSnapshot())
            }
            SmallButton(title: "导入快照", icon: "square.and.arrow.down") { showImporter = true }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
    }

    private var startBinding: Binding<String> {
        Binding(
            get: { "\(viewModel.rangeStart[viewModel.selectedArea] ?? viewModel.selectedArea.fiveDigitBase)" },
            set: { text in
                if let n = Int(text.trimmingCharacters(in: .whitespaces)),
                   let parsed = try? TagAddress.parse("\(n)"), parsed.area == viewModel.selectedArea {
                    viewModel.rangeStart[viewModel.selectedArea] = n
                    viewModel.rebuildRows()
                }
            }
        )
    }

    private var areaPicker: some View {
        HStack(spacing: 10) {
            Picker("", selection: $viewModel.selectedArea) {
                ForEach(ModbusArea.allCases) { area in
                    Text(area.name).tag(area)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 480)
            .onChange(of: viewModel.selectedArea) { _ in
                viewModel.rebuildRows()
            }
            Spacer()
            if viewModel.selectedArea.isRegisterArea {
                Text("双击值可修改 · 位格可点击")
                    .font(.system(size: 11))
                    .foregroundColor(Theme.labelGray.opacity(0.7))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    // MARK: - 表格

    private var table: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                headerCell(Col.addr, "地址", .trailing)
                headerCell(Col.name, "变量名称")
                headerCell(Col.word, viewModel.selectedArea.isRegisterArea ? "Word (2Byte)" : "值")
                if viewModel.selectedArea.isRegisterArea {
                    headerCell(Col.hex, "Hex")
                    headerCell(Col.unsigned, "无符号")
                    headerCell(Col.signed, "有符号")
                    headerCell(Col.float, "Float (AB CD)")
                }
                ColumnHeader(viewModel.selectedArea.isRegisterArea ? "位 (bit15 ← bit0)" : "开关")
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Theme.insetBackground)
            Divider().overlay(Theme.hairline)

            if viewModel.rows.isEmpty {
                EmptyHint(icon: "server.rack", title: "没有可显示的寄存器",
                          subtitle: "调整上方显示范围")
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(viewModel.rows) { row in
                            SlaveRowView(viewModel: viewModel, row: row,
                                         showFormats: viewModel.selectedArea.isRegisterArea)
                            Divider().overlay(Theme.hairline.opacity(0.5))
                        }
                    }
                    .padding(.horizontal, 10)
                }
            }
        }
    }

    private func headerCell(_ width: CGFloat, _ text: String, _ alignment: HorizontalAlignment = .leading) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(Theme.labelGray)
            .frame(width: width, alignment: Alignment(horizontal: alignment, vertical: .center))
    }
}

/// 寄存器行：多格式显示 + 双击修改 + 位格。
struct SlaveRowView: View {
    @ObservedObject var viewModel: SlaveViewModel
    let row: SlaveViewModel.SlaveRow
    let showFormats: Bool

    @State private var editingValue: Int?
    @State private var editDraft = ""
    @State private var editError = false
    @FocusState private var editFocused: Bool

    var body: some View {
        HStack(spacing: 0) {
            // 地址
            Text("\(row.displayNumber)")
                .font(.mono(12, weight: .medium))
                .foregroundColor(Theme.labelGray)
                .frame(width: 76, alignment: .trailing)
                .padding(.horizontal, 4)
            // 变量名称
            TextField("未命名", text: nameBinding)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .foregroundColor(row.name.isEmpty ? Theme.labelGray.opacity(0.5) : Theme.primaryText)
                .frame(width: 170, alignment: .leading)
                .padding(.horizontal, 4)
            // 值 / Word
            valueCell
                .frame(width: 84, alignment: .leading)
                .padding(.horizontal, 4)
            if showFormats {
                Text(String(format: "0x%04X", row.word))
                    .font(.mono(12))
                    .foregroundColor(Theme.labelGray)
                    .frame(width: 78, alignment: .leading)
                    .padding(.horizontal, 4)
                Text("\(row.word)")
                    .font(.mono(12))
                    .foregroundColor(Theme.primaryText)
                    .frame(width: 84, alignment: .leading)
                    .padding(.horizontal, 4)
                Text("\(Int16(bitPattern: row.word))")
                    .font(.mono(12))
                    .foregroundColor(Theme.primaryText)
                    .frame(width: 84, alignment: .leading)
                    .padding(.horizontal, 4)
                Text(floatText)
                    .font(.mono(12))
                    .foregroundColor(Theme.primaryText)
                    .frame(width: 84, alignment: .leading)
                    .padding(.horizontal, 4)
                // 位格
                HStack(spacing: 1.5) {
                    ForEach((0..<16).reversed(), id: \.self) { bit in
                        BitCell(on: row.bits[bit], enabled: viewModel.selectedArea != .discreteInputs) {
                            viewModel.toggleBit(offset: row.offset, bit: bit)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                // 线圈 / 离散输入
                if viewModel.selectedArea == .coils {
                    Toggle("", isOn: coilBinding)
                        .toggleStyle(.switch)
                        .controlSize(.mini)
                        .labelsHidden()
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Text(row.word == 1 ? "1 (ON)" : "0 (OFF)")
                        .font(.mono(12))
                        .foregroundColor(Theme.labelGray)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .frame(minHeight: 30)
        .padding(.vertical, 2)
        .background(editFocused ? Theme.selectedRow : Color.clear)
    }

    private var valueCell: some View {
        Group {
            if let editing = editingValue, editing == row.offset {
                TextField("", text: $editDraft)
                    .font(.mono(12))
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 74)
                    .focused($editFocused)
                    .onSubmit(commitEdit)
                    .onExitCommand { editingValue = nil }
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .strokeBorder(editError ? Theme.error : Color.clear, lineWidth: 1)
                    )
            } else {
                Text(showFormats ? "\(row.word)" : (row.word == 1 ? "1" : "0"))
                    .font(.mono(12, weight: .medium))
                    .foregroundColor(Theme.primaryText)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(RoundedRectangle(cornerRadius: 4).fill(Theme.insetBackground))
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) {
                        guard showFormats else { return }
                        editDraft = "\(row.word)"
                        editError = false
                        editingValue = row.offset
                        editFocused = true
                    }
                    .help(showFormats ? "双击修改（0-65535 或 0x 十六进制）" : "")
            }
        }
    }

    private var floatText: String {
        let rows = viewModel.rows
        guard let index = rows.firstIndex(where: { $0.offset == row.offset }),
              index + 1 < rows.count else { return "-" }
        // 行末寄存器与下一行组成 Float；孤行显示 -
        return viewModel.floatText(row.word, rows[index + 1].word)
    }

    private var nameBinding: Binding<String> {
        Binding(
            get: { row.name },
            set: { viewModel.setName($0, offset: row.offset) }
        )
    }

    private var coilBinding: Binding<Bool> {
        Binding(
            get: { row.word == 1 },
            set: { viewModel.setCoil($0, offset: row.offset) }
        )
    }

    private func commitEdit() {
        if let message = viewModel.setRegisterText(editDraft, offset: row.offset) {
            editError = true
            _ = message
        } else {
            editError = false
            editingValue = nil
        }
    }
}

/// 单个位格。
struct BitCell: View {
    var on: Bool
    var enabled: Bool
    var toggle: () -> Void

    var body: some View {
        Text(on ? "1" : "0")
            .font(.mono(9, weight: .medium))
            .foregroundColor(on ? .white : Theme.labelGray.opacity(0.7))
            .frame(width: 13, height: 13)
            .background(
                RoundedRectangle(cornerRadius: 2.5)
                    .fill(on ? Theme.accent : Theme.insetBackground)
            )
            .onTapGesture { if enabled { toggle() } }
    }
}
