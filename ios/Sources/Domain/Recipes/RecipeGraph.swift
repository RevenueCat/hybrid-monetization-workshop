struct RecipeCell: Identifiable {
    let id: String
    let label: String
    let amount: String?
    let cue: String?
    let instruction: String
    let isIngredient: Bool
    let dependencies: [String]
    // Derived presentation, never serialized into recipe JSON or local edits.
    var inputReferences: [String] = []
}

struct RecipeGraph {
    let recipe: Recipe
    let cells: [String: RecipeCell]
    let order: [String]
    let ingredientOrder: [String]
    private let dependentsByID: [String: [String]]

    init(recipe: Recipe) throws {
        try self.init(recipe: recipe, displayOrder: RecipeCatalog.displayOrder(for: recipe))
    }

    init(recipe: Recipe, displayOrder: [String]) throws {
        self = try RecipeGraphBuilder(recipe: recipe, displayOrder: displayOrder).build()
    }

    init(recipe: Recipe, cells: [String: RecipeCell], order: [String]) {
        self.recipe = recipe
        self.cells = cells
        self.order = order
        ingredientOrder = order.filter { cells[$0]?.isIngredient == true }
        dependentsByID = Dictionary(grouping: order.flatMap { target in
            (cells[target]?.dependencies ?? []).map { (source: $0, target: target) }
        }, by: { $0.source }).mapValues { $0.map { $0.target } }
    }

    func dependents(of id: String) -> [String] {
        dependentsByID[id] ?? []
    }
}
