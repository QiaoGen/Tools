import SwiftUI

// MARK: - 通用小组件

/// 8px 状态圆点。
struct StatusDot: View {
    enum StateKind { case ok, idle, error, warning }
    var kind: StateKind

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 8, height: 8)
    }

    private var color: Color {
        switch kind {
        case .ok: return Theme.success
        case .idle: return Theme.labelGray.opacity(0.6)
        case .error: return Theme.error
        case .warning: return Theme.warning
        }
    }
}

/// 表头标签。
struct ColumnHeader: View {
    var text: String
    var alignment: Alignment = .leading

    init(_ text: String, alignment: Alignment = .leading) {
        self.text = text
        self.alignment = alignment
    }

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(Theme.labelGray)
            .frame(maxWidth: .infinity, alignment: alignment)
    }
}

/// 数值文本（等宽、可选 flash 底色）。
struct ValueText: View {
    var text: String
    var flashing: Bool = false
    var isError: Bool = false
    var color: Color? = nil

    var body: some View {
        Text(text)
            .font(.mono(13))
            .foregroundColor(isError ? Theme.error : (color ?? Theme.primaryText))
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .frame(maxWidth: .infinity, minHeight: 20, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(flashing ? Theme.flashBackground : Color.clear)
            )
    }
}

/// 小号工具栏风格按钮。
struct SmallButton: View {
    var title: String
    var icon: String? = nil
    var role: Role = .normal
    var action: () -> Void

    enum Role { case normal, destructive, prominent }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let icon {
                    Image(systemName: icon).font(.system(size: 11, weight: .medium))
                }
                Text(title).font(.system(size: 12, weight: .medium))
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(background)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(Theme.hairline, lineWidth: 1)
                    )
            )
            .foregroundColor(foreground)
        }
        .buttonStyle(.plain)
    }

    private var background: Color {
        switch role {
        case .normal: return Theme.insetBackground
        case .destructive: return Theme.error.opacity(0.12)
        case .prominent: return Theme.accent
        }
    }

    private var foreground: Color {
        switch role {
        case .normal: return Theme.primaryText
        case .destructive: return Theme.error
        case .prominent: return .white
        }
    }
}

/// 行内可编辑文本（用于表格单元格）。
struct InlineEditField: View {
    @Binding var text: String
    var monospaced = false
    var alignment: Alignment = .leading
    var onSubmit: (() -> Void)? = nil

    @State private var draft = ""
    @State private var isEditing = false
    @FocusState private var focused: Bool

    var body: some View {
        Group {
            if isEditing {
                TextField("", text: $draft)
                    .font(monospaced ? .mono(13) : .system(size: 13))
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Theme.panelBackground)
                            .overlay(
                                RoundedRectangle(cornerRadius: 4)
                                    .strokeBorder(Theme.accent, lineWidth: 1.5)
                            )
                    )
                    .focused($focused)
                    .onSubmit(commit)
                    .onExitCommand { cancel() }
            } else {
                Text(text.isEmpty ? " " : text)
                    .font(monospaced ? .mono(13) : .system(size: 13))
                    .foregroundColor(text.isEmpty ? Theme.labelGray : Theme.primaryText)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .frame(maxWidth: .infinity, minHeight: 20, alignment: alignment)
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) {
                        draft = text
                        isEditing = true
                        focused = true
                    }
            }
        }
    }

    private func commit() {
        text = draft
        isEditing = false
        onSubmit?()
    }

    private func cancel() {
        isEditing = false
    }
}

/// 16 位位格行（bit0 在最右，LSB 右对齐约定）。
struct BitCellsRow: View {
    var bits: [Bool]
    var enabled: Bool
    var toggle: (Int) -> Void

    var body: some View {
        HStack(spacing: 1.5) {
            ForEach((0..<16).reversed(), id: \.self) { bit in
                let on = bits.indices.contains(bit) ? bits[bit] : false
                Text(on ? "1" : "0")
                    .font(.mono(9, weight: .medium))
                    .foregroundColor(on ? .white : Theme.labelGray.opacity(0.7))
                    .frame(width: 13, height: 13)
                    .background(
                        RoundedRectangle(cornerRadius: 2.5)
                            .fill(on ? Theme.accent : Theme.insetBackground)
                    )
                    .onTapGesture { toggle(bit) }
            }
        }
        .opacity(enabled ? 1 : 0.55)
        .help(enabled ? "点击切换位（bit15 ← bit0）" : "该区只读")
    }
}

/// 空状态提示。
struct EmptyHint: View {
    var icon: String
    var title: String
    var subtitle: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 34, weight: .light))
                .foregroundColor(Theme.labelGray.opacity(0.55))
            Text(title)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(Theme.labelGray)
            Text(subtitle)
                .font(.system(size: 12))
                .foregroundColor(Theme.labelGray.opacity(0.75))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// 表格容器：表头 + 滚动行区。
struct TableShell<Header: View, Rows: View>: View {
    @ViewBuilder var header: () -> Header
    @ViewBuilder var rows: () -> Rows

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                header()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Theme.insetBackground)
            Divider().overlay(Theme.hairline)
            ScrollView {
                LazyVStack(spacing: 0) {
                    rows()
                }
                .padding(.horizontal, 10)
            }
        }
        .background(Theme.panelBackground)
    }
}
