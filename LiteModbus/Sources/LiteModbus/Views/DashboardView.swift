import SwiftUI

/// 主站·看板页：提取的点位卡片大屏。
struct DashboardView: View {
    @ObservedObject var master: MasterViewModel

    private let columns = [GridItem(.adaptive(minimum: 230, maximum: 340), spacing: 12)]

    var dashboardTags: [TagPoint] {
        master.tags.filter { $0.onDashboard }
    }

    var body: some View {
        VStack(spacing: 0) {
            if dashboardTags.isEmpty {
                EmptyHint(icon: "square.grid.2x2",
                          title: "看板还没有点位",
                          subtitle: "在点位表点击行尾的图表图标（或右键菜单）\n把关键点位加入看板，在这里实时盯数")
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(dashboardTags) { tag in
                            DashboardCard(master: master, tag: tag)
                        }
                    }
                    .padding(14)
                }
            }
        }
        .background(Theme.windowBackground)
    }
}

struct DashboardCard: View {
    @ObservedObject var master: MasterViewModel
    let tag: TagPoint

    private var value: TagValue? { master.values[tag.id] }
    private var error: String? { master.valueErrors[tag.id] }
    private var flashing: Bool { master.flashing.contains(tag.id) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(tag.name.isEmpty ? tag.displayAddress : tag.name)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(Theme.primaryText)
                        .lineLimit(1)
                    Text("\(tag.address.area.symbol) \(tag.displayAddress)\(tag.bit.map { ".\($0)" } ?? "")")
                        .font(.mono(10))
                        .foregroundColor(Theme.labelGray)
                }
                Spacer()
                statusDot
            }
            Spacer(minLength: 4)
            if let error {
                Text(error)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(Theme.error)
            } else if let value {
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(displayValue(value))
                        .font(.mono(30, weight: .semibold))
                        .foregroundColor(valueColor(value))
                        .lineLimit(1)
                        .minimumScaleFactor(0.4)
                    if value.dataType == .bool {
                        Text(boolLabel(value))
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(valueColor(value))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(valueColor(value).opacity(0.12)))
                    } else if !tag.unit.isEmpty {
                        Text(tag.unit)
                            .font(.system(size: 12))
                            .foregroundColor(Theme.labelGray)
                    }
                }
            } else {
                Text("—")
                    .font(.mono(30, weight: .semibold))
                    .foregroundColor(Theme.labelGray.opacity(0.35))
            }
            HStack(spacing: 4) {
                if let time = master.valueTimes[tag.id] {
                    Image(systemName: "clock")
                        .font(.system(size: 9))
                    Text(timeText(time))
                        .font(.mono(10))
                } else {
                    Text("等待数据")
                        .font(.system(size: 10))
                }
                Spacer()
                Text(tag.dataType.displayName)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(Theme.labelGray.opacity(0.8))
            }
            .foregroundColor(Theme.labelGray)
        }
        .padding(12)
        .frame(minHeight: 108, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(flashing ? Theme.flashBackground : Theme.cardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(Theme.hairline, lineWidth: 1)
                )
        )
        .animation(.easeOut(duration: 0.2), value: flashing)
        .contextMenu {
            Button("读取") { master.readTag(tag) }
            Divider()
            Button("从看板移除") { toggleDashboard(false) }
        }
    }

    private var statusDot: some View {
        StatusDot(kind: {
            if error != nil { return .error }
            return value != nil ? .ok : .idle
        }())
    }

    private func displayValue(_ value: TagValue) -> String {
        if case .bool(let b) = value {
            return b ? "1" : "0"
        }
        return value.displayText
    }

    private func boolLabel(_ value: TagValue) -> String {
        if case .bool(let b) = value {
            return b ? "ON" : "OFF"
        }
        return ""
    }

    private func valueColor(_ value: TagValue) -> Color {
        if case .bool(let b) = value {
            return b ? Theme.accent : Theme.labelGray
        }
        return Theme.primaryText
    }

    private func toggleDashboard(_ on: Bool) {
        if let index = master.tags.firstIndex(where: { $0.id == tag.id }) {
            master.tags[index].onDashboard = on
        }
    }

    private func timeText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: date)
    }
}
