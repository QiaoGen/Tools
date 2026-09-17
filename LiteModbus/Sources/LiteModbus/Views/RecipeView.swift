import SwiftUI
import UniformTypeIdentifiers

/// 主站·配方管理页。
struct RecipeView: View {
    @ObservedObject var master: MasterViewModel
    @ObservedObject var store: RecipeStore

    @State private var applyStatus: [UUID: String] = [:]
    @State private var isApplying = false
    @State private var showImporter = false
    @State private var exportDocument: RecipeDocument?

    var body: some View {
        HSplitView {
            // 左：配方列表
            VStack(spacing: 0) {
                HStack {
                    Text("配方")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(Theme.labelGray)
                    Spacer()
                    SmallButton(title: "新建", icon: "plus") { store.create() }
                    SmallButton(title: "导入", icon: "square.and.arrow.down") { showImporter = true }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)

                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(store.recipes) { recipe in
                            recipeCard(recipe)
                        }
                    }
                    .padding(.horizontal, 10)
                }
            }
            .frame(minWidth: 230, idealWidth: 270, maxWidth: 360)
            .background(Theme.sidebarBackground)

            // 右：配方详情
            detail
        }
        .background(Theme.panelBackground)
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.json]) { result in
            if case .success(let url) = result {
                let accessible = url.startAccessingSecurityScopedResource()
                defer { if accessible { url.stopAccessingSecurityScopedResource() } }
                do {
                    try store.importRecipe(from: url)
                } catch {
                    applyStatus[recipePlaceholderID] = "导入失败：\(error.localizedDescription)"
                }
            }
        }
        .fileExporter(isPresented: Binding(
            get: { exportDocument != nil },
            set: { if !$0 { exportDocument = nil } }
        ), document: exportDocument, contentType: .json, defaultFilename: "\(exportDocument?.recipe.name ?? "配方").json") { _ in
            exportDocument = nil
        }
    }

    private let recipePlaceholderID = UUID()

    private func recipeCard(_ recipe: Recipe) -> some View {
        let isSelected = store.selectedRecipe?.id == recipe.id
        return VStack(alignment: .leading, spacing: 4) {
            Text(recipe.name)
                .font(.system(size: 13, weight: .medium))
                .lineLimit(1)
            Text("\(recipe.entries.count) 条 · \(dateText(recipe.updatedAt))")
                .font(.system(size: 10))
                .foregroundColor(Theme.labelGray)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Theme.cardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(isSelected ? Theme.accent : Theme.hairline,
                                      lineWidth: isSelected ? 1.5 : 1)
                )
        )
        .contentShape(Rectangle())
        .onTapGesture { store.selectionID = recipe.id }
        .contextMenu {
            Button("复制配方") { store.duplicate(recipe) }
            Button("导出 JSON…") { exportDocument = RecipeDocument(recipe: recipe) }
            Divider()
            Button("删除", role: .destructive) { store.delete(recipe) }
        }
    }

    @ViewBuilder
    private var detail: some View {
        if let recipe = store.selectedRecipe {
            RecipeDetailView(
                master: master,
                store: store,
                recipe: recipe,
                applyStatus: $applyStatus,
                isApplying: $isApplying,
                onExport: { exportDocument = RecipeDocument(recipe: recipe) }
            )
        } else {
            EmptyHint(icon: "doc.badge.gearshape",
                      title: "没有配方",
                      subtitle: "配方把一组点位 + 目标值存成 JSON\n可从当前设备值捕获，或手动建一条后一键下写")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func dateText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM-dd HH:mm"
        return formatter.string(from: date)
    }
}

struct RecipeDetailView: View {
    @ObservedObject var master: MasterViewModel
    @ObservedObject var store: RecipeStore
    let recipe: Recipe
    @Binding var applyStatus: [UUID: String]
    @Binding var isApplying: Bool
    var onExport: () -> Void

    private enum Col {
        static let name: CGFloat = 170
        static let addr: CGFloat = 92
        static let bit: CGFloat = 40
        static let type: CGFloat = 74
        static let value: CGFloat = 130
        static let status: CGFloat = 150
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(Theme.hairline)
            if recipe.entries.isEmpty {
                EmptyHint(icon: "doc.badge.gearshape",
                          title: "配方为空",
                          subtitle: "「从点位表捕获」把所有可写点位的当前值收进来\n或「添加条目」手动指定")
            } else {
                tableHeader
                Divider().overlay(Theme.hairline)
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(entries) { entry in
                            entryRow(entry)
                            Divider().overlay(Theme.hairline.opacity(0.5))
                        }
                    }
                    .padding(.horizontal, 10)
                }
            }
        }
        .background(Theme.panelBackground)
    }

    private var entries: [RecipeEntry] {
        recipe.entries
    }

    private var header: some View {
        HStack(spacing: 8) {
            TextField("配方名称", text: nameBinding)
                .textFieldStyle(.plain)
                .font(.system(size: 15, weight: .semibold))
            Spacer()
            SmallButton(title: isApplying ? "写入中…" : "应用到设备",
                        icon: "paperplane.fill", role: .prominent) {
                apply()
            }
            .disabled(isApplying || !master.isConnected || recipe.entries.isEmpty)
            SmallButton(title: "从点位表捕获", icon: "square.and.arrow.down.on.square") {
                let captured = master.captureRecipeEntries()
                guard !captured.isEmpty else { return }
                store.updateEntries(recipeID: recipe.id, entries: captured)
            }
            SmallButton(title: "添加条目", icon: "plus") {
                var entries = recipe.entries
                entries.append(RecipeEntry())
                store.updateEntries(recipeID: recipe.id, entries: entries)
            }
            SmallButton(title: "导出", icon: "square.and.arrow.up") { onExport() }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var nameBinding: Binding<String> {
        Binding(
            get: { recipe.name },
            set: { var r = recipe; r.name = $0; store.update(r) }
        )
    }

    private var tableHeader: some View {
        HStack(spacing: 0) {
            headerCell(Col.name, "变量名称")
            headerCell(Col.addr, "地址", .trailing)
            headerCell(Col.bit, "位", .center)
            headerCell(Col.type, "类型")
            headerCell(Col.value, "写入值")
            headerCell(Col.status, "状态")
            headerCell(32, "", .center)
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

    private func entryRow(_ entry: RecipeEntry) -> some View {
        HStack(spacing: 0) {
            Text(entry.name)
                .font(.system(size: 13))
                .lineLimit(1)
                .frame(width: Col.name, alignment: .leading)
            Text(entry.displayAddress)
                .font(.mono(12))
                .foregroundColor(Theme.labelGray)
                .frame(width: Col.addr, alignment: .trailing)
                .padding(.horizontal, 4)
            Text(entry.bit.map(String.init) ?? "-")
                .font(.mono(11))
                .foregroundColor(Theme.labelGray)
                .frame(width: Col.bit, alignment: .center)
            Text(entry.dataType.displayName)
                .font(.system(size: 12))
                .frame(width: Col.type, alignment: .leading)
            InlineEditField(text: valueBinding(entry), monospaced: true)
                .frame(width: Col.value)
            // 状态
            HStack(spacing: 5) {
                if let status = applyStatus[entry.id] {
                    if status == "ok" {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(Theme.success)
                        Text("已写入")
                            .foregroundColor(Theme.success)
                    } else {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(Theme.error)
                        Text(status)
                            .foregroundColor(Theme.error)
                            .lineLimit(1)
                    }
                } else {
                    Text("待写入")
                        .foregroundColor(Theme.labelGray.opacity(0.7))
                }
            }
            .font(.system(size: 11))
            .frame(width: Col.status, alignment: .leading)
            Image(systemName: "trash")
                .font(.system(size: 11))
                .foregroundColor(Theme.labelGray.opacity(0.55))
                .frame(width: 32, alignment: .center)
                .contentShape(Rectangle())
                .onTapGesture {
                    let remaining = recipe.entries.filter { $0.id != entry.id }
                    store.updateEntries(recipeID: recipe.id, entries: remaining)
                }
        }
        .frame(minHeight: 28)
        .padding(.vertical, 2)
    }

    private func valueBinding(_ entry: RecipeEntry) -> Binding<String> {
        Binding(
            get: {
                store.recipes.first { $0.id == recipe.id }?
                    .entries.first { $0.id == entry.id }?.valueText ?? entry.valueText
            },
            set: { newValue in
                var entries = recipe.entries
                if let index = entries.firstIndex(where: { $0.id == entry.id }) {
                    entries[index].valueText = newValue
                    store.updateEntries(recipeID: recipe.id, entries: entries)
                }
            }
        )
    }

    private func apply() {
        isApplying = true
        applyStatus = [:]
        Task { [weak master] in
            guard let master else { return }
            let results = await master.applyRecipe(recipe.entries)
            var status: [UUID: String] = [:]
            for (id, outcome) in results {
                switch outcome {
                case .ok: status[id] = "ok"
                case .failed(let message): status[id] = message
                }
            }
            applyStatus = status
            isApplying = false
        }
    }
}
