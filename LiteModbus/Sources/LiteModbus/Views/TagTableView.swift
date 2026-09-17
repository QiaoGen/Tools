import SwiftUI

/// 主站·点位表页。
struct TagTableView: View {
    @ObservedObject var master: MasterViewModel
    @State private var searchText = ""
    @State private var onlyDashboard = false
    @State private var selectedID: UUID?
    @State private var showAddSheet = false
    @State private var showBatchSheet = false
    @State private var editTarget: TagPoint?
    @State private var writeTarget: TagPoint?

    private enum Col {
        static let addr: CGFloat = 92
        static let bit: CGFloat = 44
        static let type: CGFloat = 76
        static let order: CGFloat = 60
        static let value: CGFloat = 140
        static let time: CGFloat = 78
        static let dash: CGFloat = 44
        static let ops: CGFloat = 92
    }

    var filteredTags: [TagPoint] {
        master.tags.filter { tag in
            if onlyDashboard && !tag.onDashboard { return false }
            if searchText.isEmpty { return true }
            return tag.name.localizedCaseInsensitiveContains(searchText)
                || tag.displayAddress.contains(searchText)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            controlBar
            Divider().overlay(Theme.hairline)
            tableHeader
            Divider().overlay(Theme.hairline)
            if filteredTags.isEmpty {
                EmptyHint(icon: "list.bullet.rectangle",
                          title: master.tags.isEmpty ? "还没有点位" : "没有匹配的点位",
                          subtitle: "点击右上角「添加点位」或「批量添加」建立变量表\n例如 40001、40001.1（位细分）")
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(filteredTags) { tag in
                            row(tag)
                            Divider().overlay(Theme.hairline.opacity(0.6))
                        }
                    }
                    .padding(.horizontal, 10)
                }
            }
        }
        .background(Theme.panelBackground)
        .sheet(item: $editTarget) { target in
            TagEditSheet(master: master, existing: target)
        }
        .sheet(item: $writeTarget) { target in
            WriteSheet(master: master, tag: target)
        }
        .sheet(isPresented: $showAddSheet) {
            TagEditSheet(master: master, existing: nil)
        }
        .sheet(isPresented: $showBatchSheet) {
            BatchAddSheet(master: master)
        }
    }

    // MARK: - 控制条

    private var controlBar: some View {
        HStack(spacing: 8) {
            HStack(spacing: 5) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11))
                    .foregroundColor(Theme.labelGray)
                TextField("搜索名称或地址", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 6).fill(Theme.insetBackground))
            .frame(width: 190)

            Toggle("仅看板", isOn: $onlyDashboard)
                .toggleStyle(.checkbox)
                .font(.system(size: 12))
                .foregroundColor(Theme.labelGray)

            Spacer()

            SmallButton(title: "添加点位", icon: "plus") { showAddSheet = true }
            SmallButton(title: "批量添加", icon: "square.stack.3d.up") { showBatchSheet = true }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
    }

    // MARK: - 表头

    private var tableHeader: some View {
        HStack(spacing: 0) {
            ColumnHeader("变量名称")
            headerCell(Col.addr, "地址", .trailing)
            headerCell(Col.bit, "位", .center)
            headerCell(Col.type, "类型")
            headerCell(Col.order, "字节序")
            headerCell(Col.value, "读值")
            headerCell(Col.time, "更新时间")
            headerCell(Col.dash, "看板", .center)
            headerCell(Col.ops, "操作")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Theme.insetBackground)
    }

    private func headerCell(_ width: CGFloat, _ text: String, _ alignment: HorizontalAlignment = .leading) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(Theme.labelGray)
            .frame(width: width, alignment: Alignment(horizontal: alignment, vertical: .center))
    }

    // MARK: - 行

    private func row(_ tag: TagPoint) -> some View {
        let value = master.values[tag.id]
        let error = master.valueErrors[tag.id]
        let isSelected = selectedID == tag.id
        return HStack(spacing: 0) {
            // 变量名称（双击重命名）
            InlineEditField(text: nameBinding(tag))
                .frame(maxWidth: .infinity, alignment: .leading)
            cell(Col.addr, .trailing) {
                Text(tag.displayAddress)
                    .font(.mono(13))
                    .foregroundColor(Theme.labelGray)
            }
            cell(Col.bit, .center) {
                Text(tag.bit.map(String.init) ?? "-")
                    .font(.mono(12))
                    .foregroundColor(Theme.labelGray)
            }
            cell(Col.type) {
                Text(tag.dataType.displayName)
                    .font(.system(size: 12))
            }
            cell(Col.order) {
                Text(tag.dataType.registerCount > 1 ? tag.byteOrder.rawValue : "-")
                    .font(.mono(11))
                    .foregroundColor(Theme.labelGray)
            }
            // 读值
            cell(Col.value) {
                if let error {
                    Text(error)
                        .font(.mono(12))
                        .foregroundColor(Theme.error)
                } else if let value {
                    HStack(alignment: .firstTextBaseline, spacing: 3) {
                        Text(value.displayText)
                            .font(.mono(13, weight: .medium))
                            .foregroundColor(Theme.primaryText)
                        if !tag.unit.isEmpty {
                            Text(tag.unit)
                                .font(.system(size: 10))
                                .foregroundColor(Theme.labelGray)
                        }
                    }
                } else {
                    Text("—")
                        .font(.mono(12))
                        .foregroundColor(Theme.labelGray.opacity(0.5))
                }
            }
            cell(Col.time) {
                Text(timeText(master.valueTimes[tag.id]))
                    .font(.mono(10))
                    .foregroundColor(Theme.labelGray)
            }
            cell(Col.dash, .center) {
                Button {
                    toggleDashboard(tag)
                } label: {
                    Image(systemName: tag.onDashboard ? "chart.bar.fill" : "chart.bar")
                        .font(.system(size: 12))
                        .foregroundColor(tag.onDashboard ? Theme.accent : Theme.labelGray.opacity(0.6))
                }
                .buttonStyle(.plain)
                .help(tag.onDashboard ? "从看板移除" : "加入看板")
            }
            // 操作
            HStack(spacing: 4) {
                if tag.isWritable {
                    SmallButton(title: "写入") { writeTarget = tag }
                }
                Image(systemName: "trash")
                    .font(.system(size: 11))
                    .foregroundColor(Theme.labelGray.opacity(0.55))
                    .padding(4)
                    .contentShape(Rectangle())
                    .onTapGesture { master.remove(tag) }
                    .help("删除点位")
            }
            .frame(width: Col.ops, alignment: .trailing)
        }
        .frame(minHeight: 28)
        .padding(.vertical, 2)
        .background(
            HStack(spacing: 0) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(isSelected ? Theme.accent : Color.clear)
                    .frame(width: 3)
                Color.clear
            }
            .background(isSelected ? Theme.selectedRow : Color.clear)
        )
        .contentShape(Rectangle())
        .onTapGesture { selectedID = tag.id }
        .contextMenu {
            Button("读取") { master.readTag(tag) }
            if tag.isWritable {
                Button("写入…") { writeTarget = tag }
            }
            Divider()
            Button(tag.onDashboard ? "从看板移除" : "加入看板") { toggleDashboard(tag) }
            Button("编辑…") { editTarget = tag }
            Button("复制点位") { master.duplicate(tag) }
            Divider()
            Button("删除", role: .destructive) { master.remove(tag) }
        }
    }

    private func cell(_ width: CGFloat, _ alignment: HorizontalAlignment = .leading,
                      @ViewBuilder content: () -> some View) -> some View {
        content()
            .frame(width: width, alignment: Alignment(horizontal: alignment, vertical: .center))
            .padding(.horizontal, 4)
    }

    private func nameBinding(_ tag: TagPoint) -> Binding<String> {
        Binding(
            get: { master.tags.first { $0.id == tag.id }?.name ?? tag.name },
            set: { newValue in
                if let index = master.tags.firstIndex(where: { $0.id == tag.id }) {
                    master.tags[index].name = newValue
                }
            }
        )
    }

    private func toggleDashboard(_ tag: TagPoint) {
        if let index = master.tags.firstIndex(where: { $0.id == tag.id }) {
            master.tags[index].onDashboard.toggle()
        }
    }

    private func timeText(_ date: Date?) -> String {
        guard let date else { return "—" }
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: date)
    }
}

// MARK: - 添加 / 编辑点位

struct TagEditSheet: View {
    @ObservedObject var master: MasterViewModel
    let existing: TagPoint?
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var addressText = "40001"
    @State private var bitText = ""
    @State private var dataType: TagDataType = .uint16
    @State private var byteOrder: ByteOrder = .abcd
    @State private var unit = ""
    @State private var comment = ""
    @State private var pollEnabled = true
    @State private var onDashboard = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            Text(existing == nil ? "添加点位" : "编辑点位")
                .font(.system(size: 14, weight: .semibold))
                .padding(.top, 16)
                .padding(.bottom, 10)
            Form {
                TextField("变量名称（如：电机温度）", text: $name)
                HStack(spacing: 8) {
                    TextField("地址（如 40001）", text: $addressText)
                        .font(.mono(13))
                    TextField("位 0-15（如 1，可空）", text: $bitText)
                        .font(.mono(13))
                        .frame(width: 150)
                }
                Picker("数据类型", selection: $dataType) {
                    ForEach(TagDataType.allCases) { Text($0.displayName).tag($0) }
                }
                Picker("字节序（多寄存器）", selection: $byteOrder) {
                    ForEach(ByteOrder.allCases) { Text($0.rawValue).tag($0) }
                }
                .disabled(dataType.registerCount == 1)
                TextField("工程单位（如 °C、kPa）", text: $unit)
                TextField("备注", text: $comment)
                Toggle("参与轮询", isOn: $pollEnabled)
                Toggle("加入看板", isOn: $onDashboard)
            }
            .formStyle(.grouped)
            if let errorMessage {
                Text(errorMessage)
                    .font(.system(size: 12))
                    .foregroundColor(Theme.error)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 24)
            }
            HStack {
                Spacer()
                Button("取消") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(existing == nil ? "添加" : "保存") { save() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
        }
        .frame(width: 430)
        .onAppear(perform: fill)
    }

    private func fill() {
        guard let tag = existing else { return }
        name = tag.name
        addressText = String(tag.addressNumber)
        bitText = tag.bit.map(String.init) ?? ""
        dataType = tag.dataType
        byteOrder = tag.byteOrder
        unit = tag.unit
        comment = tag.comment
        pollEnabled = tag.pollEnabled
        onDashboard = tag.onDashboard
    }

    private func save() {
        errorMessage = nil
        var address: TagAddress
        do {
            address = try TagAddress.parse(addressText)
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "地址无效"
            return
        }
        if bitText.trimmingCharacters(in: .whitespaces).isEmpty {
            address.bit = nil
        } else if let b = Int(bitText), (0...15).contains(b) {
            address.bit = b
        } else {
            errorMessage = "位号须为 0–15"
            return
        }
        if dataType.isBitType == false && address.bit != nil {
            errorMessage = "只有 Bool 类型支持位访问；寄存器类型请留空位号"
            return
        }
        if dataType.registerCount == 1 {
            byteOrder = .abcd
        }
        var tag = existing ?? TagPoint()
        tag.name = name
        tag.addressNumber = address.area.displayAddress(offset: address.offset)
        tag.bit = address.bit
        tag.dataType = dataType
        tag.byteOrder = byteOrder
        tag.unit = unit
        tag.comment = comment
        tag.pollEnabled = pollEnabled
        tag.onDashboard = onDashboard
        if existing == nil {
            master.add(tag)
        } else {
            if let index = master.tags.firstIndex(where: { $0.id == existing!.id }) {
                master.tags[index] = tag
            }
        }
        dismiss()
    }
}

// MARK: - 批量添加

struct BatchAddSheet: View {
    @ObservedObject var master: MasterViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var prefix = ""
    @State private var addressText = "40001"
    @State private var count = 8
    @State private var dataType: TagDataType = .uint16
    @State private var byteOrder: ByteOrder = .abcd
    @State private var bitEnabled = false
    @State private var bitIndex = 0
    @State private var unit = ""
    @State private var onDashboard = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            Text("批量添加点位")
                .font(.system(size: 14, weight: .semibold))
                .padding(.top, 16)
                .padding(.bottom, 10)
            Form {
                TextField("名称前缀（如：温度，生成 温度1…温度N）", text: $prefix)
                HStack(spacing: 8) {
                    TextField("起始地址", text: $addressText)
                        .font(.mono(13))
                    Stepper("数量 \(count)", value: $count, in: 1...128)
                }
                Picker("数据类型", selection: $dataType) {
                    ForEach(TagDataType.allCases) { Text($0.displayName).tag($0) }
                }
                Picker("字节序", selection: $byteOrder) {
                    ForEach(ByteOrder.allCases) { Text($0.rawValue).tag($0) }
                }
                .disabled(dataType.registerCount == 1)
                if dataType == .bool {
                    Toggle("寄存器位访问", isOn: $bitEnabled)
                    if bitEnabled {
                        Stepper("位号 \(bitIndex)", value: $bitIndex, in: 0...15)
                    }
                }
                TextField("工程单位", text: $unit)
                Toggle("全部加入看板", isOn: $onDashboard)
            }
            .formStyle(.grouped)
            if let errorMessage {
                Text(errorMessage)
                    .font(.system(size: 12))
                    .foregroundColor(Theme.error)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 24)
            }
            HStack {
                Spacer()
                Button("取消") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("生成 \(count) 个点位") { add() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
        }
        .frame(width: 430)
    }

    private func add() {
        errorMessage = nil
        guard let address = try? TagAddress.parse(addressText) else {
            errorMessage = "起始地址无效"
            return
        }
        let bit: Int? = (dataType == .bool && bitEnabled) ? bitIndex : nil
        let tags = MasterViewModel.makeBatch(
            prefix: prefix,
            addressNumber: address.area.displayAddress(offset: address.offset),
            count: count, bit: bit, dataType: dataType, byteOrder: byteOrder,
            unit: unit, onDashboard: onDashboard)
        tags.forEach { master.add($0) }
        dismiss()
    }
}

// MARK: - 写入

struct WriteSheet: View {
    @ObservedObject var master: MasterViewModel
    let tag: TagPoint
    @Environment(\.dismiss) private var dismiss

    @State private var text = ""
    @State private var boolValue = false
    @State private var resultMessage: String?
    @State private var isError = false
    @State private var isWriting = false

    private var isBoolWrite: Bool { tag.dataType == .bool }

    var body: some View {
        VStack(spacing: 14) {
            Text("写入点位")
                .font(.system(size: 14, weight: .semibold))
                .padding(.top, 18)

            VStack(spacing: 5) {
                Text(tag.name.isEmpty ? tag.displayAddress : tag.name)
                    .font(.system(size: 13, weight: .medium))
                Text("\(tag.displayAddress) · \(tag.dataType.displayName)\(tag.dataType.registerCount > 1 ? " · \(tag.byteOrder.rawValue)" : "")")
                    .font(.mono(11))
                    .foregroundColor(Theme.labelGray)
            }

            if isBoolWrite {
                Picker("", selection: $boolValue) {
                    Text("0 / OFF").tag(false)
                    Text("1 / ON").tag(true)
                }
                .pickerStyle(.segmented)
                .frame(width: 220)
                .labelsHidden()
            } else {
                TextField("新值（支持 0x 十六进制）", text: $text)
                    .font(.mono(14))
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 220)
                    .onSubmit(write)
            }
            if let current = master.values[tag.id] {
                Text("当前值：\(current.displayText)\(tag.unit.isEmpty ? "" : " \(tag.unit)")")
                    .font(.mono(11))
                    .foregroundColor(Theme.labelGray)
            }
            if let resultMessage {
                Text(resultMessage)
                    .font(.system(size: 12))
                    .foregroundColor(isError ? Theme.error : Theme.success)
            }
            HStack {
                Button("取消") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(isWriting ? "写入中…" : "写入") { write() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(isWriting || !master.isConnected)
            }
            .padding(.bottom, 18)
        }
        .frame(width: 320)
        .onAppear {
            if let current = master.values[tag.id] {
                text = current.displayText
                if case .bool(let b) = current { boolValue = b }
            }
        }
    }

    private func write() {
        isWriting = true
        resultMessage = nil
        let value: TagValue?
        if isBoolWrite {
            value = .bool(boolValue)
        } else {
            value = TagValue.parse(text, type: tag.dataType)
        }
        guard let value else {
            isError = true
            resultMessage = "值无法解析（类型 \(tag.dataType.displayName)）"
            isWriting = false
            return
        }
        Task { [weak master] in
            guard let master else { return }
            let outcome = await master.write(tag: tag, value: value)
            isWriting = false
            switch outcome {
            case .ok:
                isError = false
                resultMessage = "写入成功"
                dismissAfterSuccess()
            case .failed(let message):
                isError = true
                resultMessage = message
            }
        }
    }

    private func dismissAfterSuccess() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
            dismiss()
        }
    }
}
