import Foundation
import SwiftUI
import UniformTypeIdentifiers

/// 配方仓库：CRUD + JSON 持久化 + 导入导出。
@MainActor
final class RecipeStore: ObservableObject {
    @Published var recipes: [Recipe] = [] {
        didSet { scheduleSave() }
    }
    @Published var selectionID: UUID?

    var selectedRecipe: Recipe? {
        get { recipes.first { $0.id == selectionID } ?? recipes.first }
        set {
            if let newValue {
                selectionID = newValue.id
            }
        }
    }

    init() {
        if let doc: [Recipe] = JSONStore.shared.load([Recipe].self, from: JSONStore.recipesFile) {
            recipes = doc
        }
        selectionID = recipes.first?.id
    }

    func create() {
        var recipe = Recipe()
        let used = recipes.count + 1
        recipe.name = "配方 \(used)"
        recipes.append(recipe)
        selectionID = recipe.id
    }

    func delete(_ recipe: Recipe) {
        recipes.removeAll { $0.id == recipe.id }
        if selectionID == recipe.id {
            selectionID = recipes.first?.id
        }
    }

    func duplicate(_ recipe: Recipe) {
        var copy = recipe
        copy.id = UUID()
        copy.name = recipe.name + " 副本"
        copy.createdAt = Date()
        copy.updatedAt = Date()
        for i in copy.entries.indices {
            copy.entries[i].id = UUID()
        }
        recipes.append(copy)
        selectionID = copy.id
    }

    func update(_ recipe: Recipe) {
        guard let index = recipes.firstIndex(where: { $0.id == recipe.id }) else { return }
        var updated = recipe
        updated.updatedAt = Date()
        recipes[index] = updated
    }

    func updateEntries(recipeID: UUID, entries: [RecipeEntry]) {
        guard var recipe = recipes.first(where: { $0.id == recipeID }) else { return }
        recipe.entries = entries
        update(recipe)
    }

    // MARK: - 导入导出

    func export(_ recipe: Recipe, to url: URL) throws {
        try JSONStore.shared.export(recipe, to: url)
    }

    func importRecipe(from url: URL) throws {
        let recipe = try JSONStore.shared.importJSON(Recipe.self, from: url)
        var imported = recipe
        imported.id = UUID()
        imported.createdAt = Date()
        imported.updatedAt = Date()
        recipes.append(imported)
        selectionID = imported.id
    }

    private func scheduleSave() {
        JSONStore.shared.save(recipes, as: JSONStore.recipesFile)
    }
}

/// 配方 JSON 文件包装（用于系统导入/导出对话框）。
struct RecipeDocument: FileDocument {
    static let readableContentTypes = [UTType.json]
    var recipe: Recipe

    init(recipe: Recipe) {
        self.recipe = recipe
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        recipe = try decoder.decode(Recipe.self, from: data)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(recipe)
        return FileWrapper(regularFileWithContents: data)
    }
}

/// 从站内存快照 JSON 文件包装。
struct SnapshotDocument: FileDocument {
    static let readableContentTypes = [UTType.json]
    var entries: [SlaveDataStore.SparseEntry]

    init(entries: [SlaveDataStore.SparseEntry]) {
        self.entries = entries
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        entries = try JSONDecoder().decode([SlaveDataStore.SparseEntry].self, from: data)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return FileWrapper(regularFileWithContents: try encoder.encode(entries))
    }
}
