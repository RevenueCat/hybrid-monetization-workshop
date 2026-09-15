import Combine
import Foundation
import SwiftUI

/// Owns recipe ordering, removal, and import restoration.
@MainActor
final class RecipeLibrary: ObservableObject {
    @Published private var allStores: [SessionStore]
    @Published private(set) var removedIDs: Set<String> = []
    @Published private var recipeOrder: [String] = []
    @Published var errorMessage: String?

    let incoming: IncomingRecipeStore?
    private let directory: URL?
    private var removalStorageReadable = true
    private var orderStorageReadable = true
    private var observations: Set<AnyCancellable> = []

    private var orderedStores: [SessionStore] {
        let unordered = allStores.filter { !recipeOrder.contains($0.graph.recipe.id) }
        return unordered + recipeOrder.compactMap { id in
            allStores.first { $0.graph.recipe.id == id }
        }
    }

    var stores: [SessionStore] {
        orderedStores.filter { !removedIDs.contains($0.graph.recipe.id) }
    }

    init(stores: [SessionStore], incoming: IncomingRecipeStore? = nil, directory: URL? = nil) {
        self.allStores = stores
        self.incoming = incoming
        self.directory = directory
        restoreRemovedRecipeIDs()
        restoreRecipeOrder()

        stores.forEach { $0.setRecipeRemoved(removedIDs.contains($0.graph.recipe.id)) }
        incoming?.currentRecipeTitles = { [weak self] in
            self?.stores.map { $0.graph.recipe.title } ?? []
        }
        incoming?.onChange = { [weak self] in self?.restoreImports() }
        incoming?.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &observations)
        stores.forEach(observe)
        restoreImports()
    }

    func moveRecipes(from source: IndexSet, to destination: Int) {
        guard orderStorageReadable else { return }
        var visible = stores.map { $0.graph.recipe.id }
        guard source.allSatisfy({ visible.indices.contains($0) }),
              (0...visible.count).contains(destination) else { return }
        visible.move(fromOffsets: source, toOffset: destination)
        var iterator = visible.makeIterator()
        let updated = orderedStores.map { store in
            let id = store.graph.recipe.id
            return removedIDs.contains(id) ? id : iterator.next() ?? id
        }
        do {
            try write(updated, filename: "recipe-order.json")
            recipeOrder = updated
            errorMessage = nil
        } catch {
            errorMessage = "Couldn’t save recipe order. \(error.localizedDescription)"
        }
    }

    @discardableResult
    func setRemoved(_ id: String, removed: Bool) -> Bool {
        guard removalStorageReadable,
              let store = allStores.first(where: { $0.graph.recipe.id == id }) else { return false }
        var updated = removedIDs
        if removed { updated.insert(id) } else { updated.remove(id) }
        do {
            try write(updated, filename: "removed-recipes.json")
            removedIDs = updated
            store.setRecipeRemoved(removed)
            errorMessage = nil
            return true
        } catch {
            errorMessage = "Couldn’t update your recipe book. \(error.localizedDescription)"
            return false
        }
    }

    func store(for id: String) -> SessionStore? {
        stores.first { $0.graph.recipe.id == id }
    }

    private func restoreRemovedRecipeIDs() {
        guard let url = directory?.appendingPathComponent("removed-recipes.json"),
              FileManager.default.fileExists(atPath: url.path) else { return }
        do {
            removedIDs = try JSONDecoder().decode(Set<String>.self, from: Data(contentsOf: url))
        } catch {
            removalStorageReadable = false
            errorMessage = "Couldn’t read removed recipes. \(error.localizedDescription)"
        }
    }

    private func restoreRecipeOrder() {
        guard let url = directory?.appendingPathComponent("recipe-order.json"),
              FileManager.default.fileExists(atPath: url.path) else { return }
        do {
            let saved = try JSONDecoder().decode([String].self, from: Data(contentsOf: url))
            var seen = Set<String>()
            recipeOrder = saved.filter { seen.insert($0).inserted }
        } catch {
            orderStorageReadable = false
            errorMessage = "Couldn’t read recipe order. \(error.localizedDescription)"
        }
    }

    private func restoreImports() {
        guard let incoming, let directory else { return }
        let missing = incoming.items.filter { item in
            item.status == .complete && !allStores.contains(where: { $0.graph.recipe.id == item.recipeID })
        }
        for item in missing {
            do {
                let store = try makeImportedStore(item, directory: directory)
                observe(store)
                store.setRecipeRemoved(removedIDs.contains(store.graph.recipe.id))
                allStores.insert(store, at: 0)
            } catch {
                incoming.errorMessage = "Couldn’t open a prepared recipe. \(error.localizedDescription)"
            }
        }
    }

    private func makeImportedStore(_ item: IncomingRecipe, directory: URL) throws -> SessionStore {
        guard let data = item.preparedRecipe else {
            throw RecipeError.invalid("The prepared recipe is missing.")
        }
        let recipe = try JSONDecoder().decode(Recipe.self, from: data)
        let template = try Recipe.bundled(id: item.mockTemplateID ?? "banana-muffins")
        let graph = try RecipeGraph(recipe: recipe, displayOrder: RecipeGraph(recipe: template).order)
        let store = SessionStore(
            graph: graph,
            fileURL: directory.appendingPathComponent("\(recipe.id)-session.json"),
            layout: try RecipeTableLayout.generated(for: graph)
        )
        store.onPrepareTimerAlert = { CookingTimerNotifications.shared.prepareForegroundAlert() }
        store.onTimerAlert = { CookingTimerNotifications.shared.foregroundAlert() }
        return store
    }

    private func observe(_ store: SessionStore) {
        store.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &observations)
    }

    private func write<Value: Encodable>(_ value: Value, filename: String) throws {
        guard let directory else { return }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONEncoder().encode(value).write(
            to: directory.appendingPathComponent(filename),
            options: .atomic
        )
    }
}
