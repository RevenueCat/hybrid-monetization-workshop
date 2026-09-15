import Foundation
import Combine

@MainActor
final class IncomingRecipeStore: ObservableObject {
    private static let mockTemplateIDs = ["baba-ganoush", "banana-muffins", "pickled-onion", "coca-de-recapte", "coconut-chickpea-soup"]
    @Published private(set) var items: [IncomingRecipe] = []
    @Published private(set) var completedThisVisit: Set<String> = []
    @Published var errorMessage: String?
    var onChange: (() -> Void)?
    var currentRecipeTitles: (() -> [String])?


    private let repository: IncomingRecipeRepository
    private let delay: Duration
    private var active = false
    private var worker: Task<Void, Never>?
    private var generation = UUID()

    init(repository: IncomingRecipeRepository, delay: Duration = .seconds(2)) throws {
        self.repository = repository
        self.delay = delay
        items = try repository.load().items
    }
    var visibleItems: [IncomingRecipe] {
        items.reversed().filter { $0.status != .complete || completedThisVisit.contains($0.id) }
    }
    @discardableResult
    func capture(_ url: URL) throws -> String {
        let source = try RecipeSource.web(url)
        try repository.capture(url: url, title: nil)
        items = try repository.load().items
        onChange?()
        guard let item = items.first(where: { $0.source == source && $0.status != .complete }) else {
            throw IncomingRecipeError.unavailable
        }
        return item.id
    }
    func beginBookVisit() { completedThisVisit = [] }
    func refresh() {
        do { items = try repository.load().items; onChange?() }
        catch { errorMessage = error.localizedDescription }
    }
    func setActive(_ value: Bool) {
        guard active != value else { if value { refresh() }; return }
        active = value
        generation = UUID()
        worker?.cancel(); worker = nil
        // A killed/suspended worker owns no irreversible work in this mock. Requeue it.
        mutate { document in
            for index in document.items.indices where document.items[index].status == .preparing {
                document.items[index].status = .waiting
            }
        }
        if value { startWorker() }
    }
    func prepare(_ id: String) {
        guard mutate({ document in
            guard let index = document.items.firstIndex(where: { $0.id == id }),
                  [.ready, .failed].contains(document.items[index].status) else { return }
            document.items[index].status = .waiting
            document.items[index].requestedAt = Date()
        }) else { return }
        startWorker()
    }
    struct DiscardedImport {
        let item: IncomingRecipe
        let index: Int
    }

    @discardableResult
    func remove(_ id: String) -> DiscardedImport? {
        var discarded: DiscardedImport?
        guard mutate({ document in
            guard let index = document.items.firstIndex(where: { $0.id == id && $0.status != .complete }) else { return }
            discarded = DiscardedImport(item: document.items.remove(at: index), index: index)
        }), let discarded else { return nil }
        if discarded.item.status == .preparing {
            generation = UUID()
            worker?.cancel()
            worker = nil
            startWorker()
        }
        return discarded
    }

    @discardableResult
    func restore(_ discarded: DiscardedImport) -> Bool {
        guard mutate({ document in
            // The same link may have been added again before Undo.
            guard !document.items.contains(where: {
                $0.id == discarded.item.id || ($0.source == discarded.item.source && $0.status != .complete)
            }) else { return }
            var item = discarded.item
            if item.status == .preparing { item.status = .waiting }
            document.items.insert(item, at: min(discarded.index, document.items.count))
        }) else { return false }
        startWorker()
        return true
    }
    @discardableResult
    private func mutate(_ change: (inout IncomingRecipeDocument) throws -> Void) -> Bool {
        do { items = try repository.update(change).items; onChange?(); return true }
        catch { errorMessage = error.localizedDescription; return false }
    }
    /// Count numbered copies together, but only count recipes still visible in the book.
    static func selectMockRecipe(templates: [Recipe], titles: [String], startingAt: Int) -> (index: Int, title: String) {
        func normalized(_ title: String) -> String {
            title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        }
        func baseTitle(_ title: String) -> String {
            normalized(title).replacingOccurrences(of: #" \([2-9][0-9]*\)$| \(1[0-9]+\)$"#,
                                                  with: "", options: .regularExpression)
        }
        let counts = templates.map { template in titles.filter { baseTitle($0) == normalized(template.title) }.count }
        let least = counts.min()!
        let index = (0..<templates.count).map { (startingAt + $0) % templates.count }
            .first { counts[$0] == least }!
        let title = templates[index].title
        guard least > 0 else { return (index, title) }
        let usedTitles = Set(titles.map(normalized))
        var number = 2
        while usedTitles.contains(normalized("\(title) (\(number))")) { number += 1 }
        return (index, "\(title) (\(number))")
    }

    private func startWorker() {
        guard active, worker == nil else { return }
        let token = generation
        worker = Task { [weak self] in
            guard let self else { return }
            defer { if self.generation == token { self.worker = nil } }
            while !Task.isCancelled && self.active && self.generation == token {
                guard let next = self.items.filter({ $0.status == .waiting }).sorted(by: {
                    ($0.requestedAt ?? $0.createdAt) < ($1.requestedAt ?? $1.createdAt)
                }).first else { return }
                guard self.mutate({ document in
                    guard let i = document.items.firstIndex(where: { $0.id == next.id && $0.status == .waiting }) else { return }
                    document.items[i].status = .preparing
                }) else { return }
                do {
                    try await Task.sleep(for: self.delay)
                    try Task.checkCancellation()
                    guard self.active && self.generation == token else { return }
                    // Template choice and completion commit together: relaunch cannot duplicate a result.
                    guard self.mutate({ document in
                        guard let i = document.items.firstIndex(where: { $0.id == next.id && $0.status == .preparing }) else { return }
                        let templates = try Self.mockTemplateIDs.map { try Recipe.bundled(id: $0) }
                        let titles = try self.currentRecipeTitles?() ?? document.items.compactMap { item in
                            guard item.status == .complete, let data = item.preparedRecipe else { return nil }
                            return try JSONDecoder().decode(Recipe.self, from: data).title
                        }
                        let selection = Self.selectMockRecipe(templates: templates, titles: titles,
                                                             startingAt: document.nextMockTemplateIndex)
                        let templateIndex = selection.index
                        let templateID = Self.mockTemplateIDs[templateIndex]
                        let template = templates[templateIndex]
                        let recipe = Recipe(schemaVersion: template.schemaVersion, id: next.recipeID,
                                            title: selection.title, yield: template.yield,
                                            photo: nil, sourceUrl: next.source.value,
                                            ingredients: template.ingredients, steps: template.steps)
                        let graph = try RecipeGraph(recipe: recipe,
                                                    displayOrder: RecipeGraph(recipe: template).order)
                        _ = try RecipeTableLayout.generated(for: graph)
                        document.items[i].preparedRecipe = try JSONEncoder().encode(recipe)
                        document.items[i].mockTemplateID = templateID
                        document.items[i].status = .complete
                        document.nextMockTemplateIndex = (templateIndex + 1) % Self.mockTemplateIDs.count
                    }) else { return }
                    if self.items.contains(where: { $0.id == next.id && $0.status == .complete }) {
                        self.completedThisVisit.insert(next.id)
                    }
                } catch is CancellationError { return }
                catch {
                    guard self.mutate({ document in
                        if let i = document.items.firstIndex(where: { $0.id == next.id && $0.status == .preparing }) {
                            document.items[i].status = .failed
                        }
                    }) else { return }
                }
            }
        }
    }

}
