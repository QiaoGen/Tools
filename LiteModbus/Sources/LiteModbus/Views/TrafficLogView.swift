import SwiftUI
import UniformTypeIdentifiers

/// 主站·报文日志页。
struct TrafficLogView: View {
    @ObservedObject var log: TrafficLog
    @State private var filter: DirectionFilter = .all
    @State private var onlyErrors = false
    @State private var paused = false
    @State private var exportTarget: TrafficLogExport?

    enum DirectionFilter: String, CaseIterable {
        case all = "全部"
        case tx = "TX"
        case rx = "RX"
    }

    struct TrafficLogExport: FileDocument {
        static let readableContentTypes = [UTType.plainText]

        var text: String

        init(text: String) { self.text = text }

        init(configuration: ReadConfiguration) throws {
            text = configuration.file.regularFileContents.map {
                String(decoding: $0, as: UTF8.self)
            } ?? ""
        }

        func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
            FileWrapper(regularFileWithContents: Data(text.utf8))
        }
    }

    var filtered: [TrafficLogEntry] {
        log.entries.filter { entry in
            if filter == .tx && entry.direction != .tx { return false }
            if filter == .rx && entry.direction != .rx { return false }
            if onlyErrors && entry.error == nil { return false }
            return true
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            controlBar
            Divider().overlay(Theme.hairline)
            tableHeader
            Divider().overlay(Theme.hairline)
            if filtered.isEmpty {
                EmptyHint(icon: "waveform.path.ecg",
                          title: "暂无报文",
                          subtitle: "连接设备并通信后，这里会记录每一帧\nTX = 发出请求，RX = 收到响应")
            } else {
                logList
            }
            footerBar
        }
        .background(Theme.panelBackground)
        .fileExporter(isPresented: Binding(
            get: { exportTarget != nil },
            set: { if !$0 { exportTarget = nil } }
        ), document: exportTarget, contentType: .plainText, defaultFilename: "modbus-traffic.log") { result in
            if case .success(let url) = result {
                exportTarget = nil
                _ = url
            }
        }
    }

    private var controlBar: some View {
        HStack(spacing: 10) {
            Picker("", selection: $filter) {
                ForEach(DirectionFilter.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .frame(width: 170)
            .labelsHidden()

            Toggle("仅异常", isOn: $onlyErrors)
                .toggleStyle(.checkbox)
                .font(.system(size: 12))

            Spacer()

            Toggle("暂停滚动", isOn: $paused)
                .toggleStyle(.checkbox)
                .font(.system(size: 12))

            SmallButton(title: "导出", icon: "square.and.arrow.up") { exportLog() }
            SmallButton(title: "清空", icon: "trash", role: .destructive) { log.clear() }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
    }

    private var tableHeader: some View {
        HStack(spacing: 0) {
            headerText("#", 46, .leading)
            headerText("方向", 44)
            headerText("时间", 78)
            headerText("功能码", 110)
            headerText("摘要", 210)
            headerText("耗时", 62, .trailing)
            ColumnHeader("原始报文 (HEX)")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Theme.insetBackground)
    }

    private func headerText(_ text: String, _ width: CGFloat, _ alignment: HorizontalAlignment = .leading) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(Theme.labelGray)
            .frame(width: width, alignment: Alignment(horizontal: alignment, vertical: .center))
    }

    private var logList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(filtered) { entry in
                        row(entry)
                        Divider().overlay(Theme.hairline.opacity(0.5))
                    }
                }
                .padding(.horizontal, 10)
            }
            .onChange(of: paused) { _ in }
            .onChange(of: log.entries.count) { _ in
                guard !paused, let last = filtered.last else { return }
                proxy.scrollTo(last.id, anchor: .bottom)
            }
            .onAppear {
                if let last = filtered.last {
                    proxy.scrollTo(last.id, anchor: .bottom)
                }
            }
        }
    }

    private func row(_ entry: TrafficLogEntry) -> some View {
        let isTx = entry.direction == .tx
        return HStack(spacing: 0) {
            Text("\(log.entries.firstIndex(where: { $0.id == entry.id }).map { $0 + 1 } ?? 0)")
                .font(.mono(11))
                .foregroundColor(Theme.labelGray)
                .frame(width: 46, alignment: .leading)
            Text(entry.direction.rawValue)
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 1.5)
                .background(Capsule().fill(isTx ? Theme.accent : Theme.success))
                .frame(width: 44, alignment: .leading)
            Text(timeText(entry.time))
                .font(.mono(11))
                .foregroundColor(Theme.labelGray)
                .frame(width: 78, alignment: .leading)
            Text(entry.functionText)
                .font(.mono(11))
                .foregroundColor(Theme.primaryText)
                .frame(width: 110, alignment: .leading)
            Text(entry.error ?? entry.summary)
                .font(.system(size: 11))
                .foregroundColor(entry.error != nil ? Theme.error : Theme.labelGray)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(width: 210, alignment: .leading)
            Text(entry.durationMs.map { String(format: "%.1fms", $0) } ?? "—")
                .font(.mono(11))
                .foregroundColor(Theme.labelGray)
                .frame(width: 62, alignment: .trailing)
            Text(entry.hexText)
                .font(.mono(11))
                .foregroundColor(entry.error != nil ? Theme.error : Theme.primaryText)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
        .frame(minHeight: 24)
        .padding(.vertical, 1)
    }

    private var footerBar: some View {
        HStack(spacing: 12) {
            Text("\(log.entries.count) 帧")
                .font(.mono(11))
            Text("容量上限 2000 帧，超出自动丢弃最旧")
                .font(.system(size: 10))
                .foregroundColor(Theme.labelGray.opacity(0.7))
            Spacer()
        }
        .foregroundColor(Theme.labelGray)
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .background(Theme.insetBackground)
    }

    private func timeText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter.string(from: date)
    }

    private func exportLog() {
        let lines = filtered.map { entry in
            "\(entry.direction.rawValue) \(timeText(entry.time)) \(entry.functionText) \(entry.summary) \(entry.error ?? "") \(entry.hexText)"
        }
        exportTarget = TrafficLogExport(text: lines.joined(separator: "\n"))
    }
}
