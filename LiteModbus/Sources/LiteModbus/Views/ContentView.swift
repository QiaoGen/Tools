import SwiftUI

/// 侧栏页面。
enum AppPage: String, Hashable, CaseIterable {
    case dashboard = "看板"
    case tags = "点位表"
    case recipes = "配方"
    case traffic = "报文日志"
    case slave = "寄存器仿真"

    var icon: String {
        switch self {
        case .dashboard: return "square.grid.2x2"
        case .tags: return "list.bullet.rectangle"
        case .recipes: return "doc.badge.gearshape"
        case .traffic: return "waveform.path.ecg"
        case .slave: return "server.rack"
        }
    }
}

struct ContentView: View {
    @StateObject private var master = MasterViewModel()
    @StateObject private var slaveVM = SlaveViewModel()
    @StateObject private var recipes = RecipeStore()
    @State private var page: AppPage = .dashboard

    var body: some View {
        NavigationSplitView {
            List(selection: $page) {
                Section("主站") {
                    ForEach([AppPage.dashboard, .tags, .recipes, .traffic], id: \.self) { p in
                        label(p)
                    }
                }
                Section("从站") {
                    label(.slave)
                }
            }
            .listStyle(.sidebar)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                sidebarFooter
            }
            .scrollContentBackground(.hidden)
            .background(Theme.sidebarBackground)
        } detail: {
            detail
                .background(Theme.windowBackground)
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    statusBar
                }
        }
        .navigationSplitViewStyle(.balanced)
    }

    /// 底部状态条：连接状态、周期耗时、计数、数据目录。
    private var statusBar: some View {
        HStack(spacing: 14) {
            HStack(spacing: 5) {
                StatusDot(kind: master.isConnecting ? .warning
                            : master.isConnected ? .ok
                            : master.connectionError != nil ? .error : .idle)
                Text(master.isConnecting ? "连接中…"
                        : master.isConnected ? "已连接 \(master.config.host):\(master.config.port)"
                        : (master.connectionError ?? "未连接"))
                    .font(.mono(10))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            if master.isConnected {
                Text(String(format: "周期 %.0fms", master.cycleTimeMs))
                    .font(.mono(10))
                Text("Tx \(master.txCount) · Rx \(master.rxCount) · Err \(master.errCount)")
                    .font(.mono(10))
                    .foregroundColor(master.errCount > 0 ? Theme.warning : Theme.labelGray)
            }
            if page == .slave {
                Text(slaveVM.isRunning
                        ? "从站已监听 :\(slaveVM.port) · 请求 \(slaveVM.requests) · 异常 \(slaveVM.exceptions)"
                        : "从站未监听")
                    .font(.mono(10))
                    .foregroundColor(slaveVM.isRunning ? Theme.success : Theme.labelGray)
            }
            Spacer()
            Text("数据 \(JSONStore.shared.displayPath)")
                .font(.mono(10))
                .foregroundColor(Theme.labelGray.opacity(0.8))
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .background(Theme.insetBackground)
    }

    private func label(_ p: AppPage) -> Label<Text, Image> {
        Label {
            Text(p.rawValue)
        } icon: {
            Image(systemName: p.icon)
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch page {
        case .dashboard:
            DashboardView(master: master)
                .masterToolbar(master: master)
        case .tags:
            TagTableView(master: master)
                .masterToolbar(master: master)
        case .recipes:
            RecipeView(master: master, store: recipes)
                .masterToolbar(master: master, showPollControls: false)
        case .traffic:
            TrafficLogView(log: master.log)
                .masterToolbar(master: master, showPollControls: false)
        case .slave:
            SlaveView(viewModel: slaveVM)
        }
    }

    /// 边栏底部连接状态。
    private var sidebarFooter: some View {
        HStack(spacing: 6) {
            if master.isConnecting {
                ProgressView().controlSize(.small)
            } else {
                StatusDot(kind: master.isConnected ? (master.isPolling ? .ok : .ok) : (master.connectionError != nil ? .error : .idle))
            }
            Text(statusText)
                .font(.mono(11))
                .foregroundColor(Theme.labelGray)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Theme.sidebarBackground)
    }

    private var statusText: String {
        if master.isConnecting { return "连接中…" }
        if master.isConnected {
            return "\(master.config.host):\(master.config.port) · unit \(master.config.unitId)"
        }
        if let error = master.connectionError { return error }
        return "未连接"
    }
}

// MARK: - 主站工具栏

/// 主站页面共用的连接与轮询控制（置于窗口工具栏）。
struct MasterToolbarItems: View {
    @ObservedObject var master: MasterViewModel
    var showPollControls: Bool

    var body: some View {
        HStack(spacing: 8) {
            connectionCluster
            if showPollControls {
                Divider().frame(height: 16)
                pollCluster
            }
        }
    }

    private var connectionCluster: some View {
        HStack(spacing: 6) {
            TextField("主机", text: $master.config.host)
                .font(.mono(12))
                .textFieldStyle(.roundedBorder)
                .frame(width: 130)
                .disabled(master.isConnected)
            TextField("端口", value: $master.config.port, format: .number)
                .font(.mono(12))
                .textFieldStyle(.roundedBorder)
                .frame(width: 58)
                .disabled(master.isConnected)
            TextField("Unit", value: $master.config.unitId, format: .number)
                .font(.mono(12))
                .textFieldStyle(.roundedBorder)
                .frame(width: 44)
                .disabled(master.isConnected)
            Button {
                master.toggleConnection()
            } label: {
                Text(master.isConnected ? "断开" : "连接")
                    .frame(width: 46)
            }
            .buttonStyle(.borderedProminent)
            .tint(master.isConnected ? Color(nsColor: .controlColor) : Theme.accent)
            .foregroundColor(master.isConnected ? Theme.primaryText : .white)
        }
    }

    private var pollCluster: some View {
        HStack(spacing: 6) {
            TextField("ms", value: $master.config.pollIntervalMs, format: .number)
                .font(.mono(12))
                .textFieldStyle(.roundedBorder)
                .frame(width: 62)
                .help("轮询间隔 (ms)")
            Button {
                master.isPolling ? master.stopPolling() : master.startPolling()
            } label: {
                Label(master.isPolling ? "停止轮询" : "开始轮询",
                      systemImage: master.isPolling ? "stop.fill" : "play.fill")
            }
            .buttonStyle(.bordered)
            .disabled(!master.isConnected)
            if master.isPolling {
                HStack(spacing: 4) {
                    StatusDot(kind: .ok)
                    Text(String(format: "%.0fms", master.cycleTimeMs))
                        .font(.mono(11))
                        .foregroundColor(Theme.labelGray)
                }
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(Capsule().fill(Theme.insetBackground))
            }
        }
    }
}

extension View {
    func masterToolbar(master: MasterViewModel, showPollControls: Bool = true) -> some View {
        toolbar {
            ToolbarItem(placement: .principal) {
                MasterToolbarItems(master: master, showPollControls: showPollControls)
            }
        }
    }
}
