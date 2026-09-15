import Foundation

/// Runtime model for the bundled workshop recipes.
struct Recipe: Codable {
    struct Ingredient: Codable {
        let id: String
        let name: String
        let quantity: String?
        let clarification: String?
        let instruction: String?
    }
    struct Step: Codable {
        struct Input: Codable {
            let ingredient: String?
            let output: String?
            let allocation: String?
            let optional: Bool?
        }
        struct Output: Codable { let id: String; let name: String }
        struct Duration: Codable {
            let min: Double
            let max: Double
            let unit: String
            let approximate: Bool?
            var display: String {
                let start = min.formatted(.number.precision(.fractionLength(0...1)))
                let end = max.formatted(.number.precision(.fractionLength(0...1)))
                return (approximate == true ? "≈" : "") + (min == max ? start : "\(start)–\(end)") + " \(unit)"
            }
        }
        let id: String
        let action: String
        let inputs: [Input]
        let outputs: [Output]
        let after: [String]?
        let clarification: String?
        let duration: Duration?
        let instruction: String?
    }
    let schemaVersion: Int
    let id: String
    let title: String
    let yield: String?
    let photo: String?
    let sourceUrl: String?
    let ingredients: [Ingredient]
    let steps: [Step]

    static func bundled(id: String = "baba-ganoush") throws -> Recipe {
        let subdirectory = id == "baba-ganoush" ? nil : id
        guard let url = Bundle.main.url(forResource: "recipe", withExtension: "json", subdirectory: subdirectory) else {
            throw RecipeError.invalid("The bundled recipe is missing.")
        }
        let recipe = try decode(Data(contentsOf: url))
        guard recipe.id == id else { throw RecipeError.invalid("The bundled recipe identifier does not match its catalog entry.") }
        if let photo = recipe.photo, !FileManager.default.fileExists(atPath: url.deletingLastPathComponent().appendingPathComponent(photo).path) {
            throw RecipeError.invalid("The bundled recipe photo is missing.")
        }
        return recipe
    }
    static func decode(_ data: Data) throws -> Recipe {
        // Codable enforces types; this rejects unknown properties and explicit nulls
        // instead of silently accepting a misspelled field or a legacy review document.
        try validateShape(JSONSerialization.jsonObject(with: data))
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let recipe = try decoder.decode(Recipe.self, from: data)
        try recipe.validateFields()
        return recipe
    }
    private static func validateShape(_ raw: Any) throws {
        func object(_ raw: Any, required: [String], optional: [String] = []) throws -> [String: Any] {
            guard let value = raw as? [String: Any], Set(required).isSubset(of: Set(value.keys)),
                  Set(value.keys).isSubset(of: Set(required + optional)), !value.values.contains(where: { $0 is NSNull }) else {
                throw RecipeError.invalid("Recipe fields do not match the runtime format.")
            }
            return value
        }
        func array(_ raw: Any?) throws -> [Any] {
            guard let value = raw as? [Any] else { throw RecipeError.invalid("Expected a recipe array.") }
            return value
        }
        let root = try object(raw, required: ["schema_version", "id", "title", "ingredients", "steps"], optional: ["yield", "photo", "source_url"])
        for item in try array(root["ingredients"]) {
            _ = try object(item, required: ["id", "name"], optional: ["quantity", "clarification", "instruction"])
        }
        for item in try array(root["steps"]) {
            let step = try object(item, required: ["id", "action", "inputs", "outputs"], optional: ["after", "duration", "clarification", "instruction"])
            for input in try array(step["inputs"]) {
                let value = try object(input, required: [], optional: ["ingredient", "output", "allocation", "optional"])
                guard (value["ingredient"] != nil) != (value["output"] != nil) else {
                    throw RecipeError.invalid("Each input must identify either an ingredient or an output.")
                }
            }
            for output in try array(step["outputs"]) { _ = try object(output, required: ["id", "name"]) }
            if let duration = step["duration"] {
                _ = try object(duration, required: ["min", "max", "unit"], optional: ["approximate"])
            }
        }
    }
    private func validateFields() throws {
        guard schemaVersion == 1, !steps.isEmpty else { throw RecipeError.invalid("Unsupported recipe version or empty step list.") }
        func identifier(_ value: String) throws {
            guard value.range(of: "^[a-z0-9]+(?:-[a-z0-9]+)*$", options: .regularExpression)?.upperBound == value.endIndex else {
                throw RecipeError.invalid("Invalid recipe identifier: \(value)")
            }
        }
        func text(_ value: String?, compact: Bool = true) throws {
            guard let value else { return }
            guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !compact || (!value.contains("\n") && !value.contains("\r")) else {
                throw RecipeError.invalid("Recipe text must be nonblank; compact fields must be a single phrase.")
            }
        }
        try identifier(id); try text(title); try text(yield)
        if let photo, photo.range(of: "^[A-Za-z0-9_-][A-Za-z0-9._-]*(/[A-Za-z0-9_-][A-Za-z0-9._-]*)*$", options: .regularExpression)?.upperBound != photo.endIndex {
            throw RecipeError.invalid("Recipe photo must be a relative asset path.")
        }
        if let sourceUrl {
            guard let url = URL(string: sourceUrl), ["http", "https"].contains(url.scheme ?? ""), let host = url.host, !host.isEmpty else {
                throw RecipeError.invalid("Recipe source must be an HTTP(S) URL.")
            }
        }
        for ingredient in ingredients {
            try identifier(ingredient.id); try text(ingredient.name); try text(ingredient.quantity)
            try text(ingredient.clarification); try text(ingredient.instruction, compact: false)
        }
        for step in steps {
            try identifier(step.id); try text(step.action); try text(step.clarification); try text(step.instruction, compact: false)
            for input in step.inputs {
                if let ingredient = input.ingredient { try identifier(ingredient) }
                if let output = input.output { try identifier(output) }
                try text(input.allocation)
            }
            for output in step.outputs { try identifier(output.id); try text(output.name) }
            for dependency in step.after ?? [] { try identifier(dependency) }
            if let duration = step.duration {
                guard duration.min.isFinite, duration.max.isFinite, duration.min >= 0, duration.max >= duration.min,
                      ["sec", "min", "h"].contains(duration.unit) else { throw RecipeError.invalid("Invalid recipe duration.") }
            }
        }
    }
}

enum RecipeError: LocalizedError {
    case invalid(String)
    var errorDescription: String? { switch self { case .invalid(let message): return message } }
}

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

    init(recipe: Recipe) throws {
        let recipeOrder = recipe.ingredients.map(\.id) + recipe.steps.map(\.id)
        // Keep the established cooking traversal for the original bundled
        // recipe. Layout geometry is still generated solely from this graph.
        let displayOrder = recipe.id == "baba-ganoush" ? [
            "preheat", "eggplant", "cut-eggplant", "roast-eggplant", "cool", "extract-flesh",
            "garlic", "peel-garlic", "olive-oil", "roast-garlic", "separate", "tahini", "lemon",
            "cumin", "salt", "sweet-paprika", "blend-base", "mix", "parsley", "serve"
        ] : recipeOrder
        try self.init(recipe: recipe, displayOrder: displayOrder)
    }

    init(recipe: Recipe, displayOrder: [String]) throws {
        let ingredientIDs = recipe.ingredients.map(\.id)
        let stepIDs = recipe.steps.map(\.id)
        let ids = ingredientIDs + stepIDs
        guard Set(ids).count == ids.count, Set(displayOrder) == Set(ids), displayOrder.count == ids.count else {
            throw RecipeError.invalid("Recipe identifiers and grid placements must match exactly.")
        }
        var producers: [String: String] = [:]
        for step in recipe.steps {
            for output in step.outputs {
                guard producers[output.id] == nil, !ids.contains(output.id) else {
                    throw RecipeError.invalid("Duplicate recipe output: \(output.id)")
                }
                producers[output.id] = step.id
            }
        }
        var cells: [String: RecipeCell] = [:]
        for ingredient in recipe.ingredients {
            cells[ingredient.id] = RecipeCell(id: ingredient.id, label: ingredient.name,
                amount: ingredient.quantity?.replacingOccurrences(of: "1/4", with: "¼"), cue: ingredient.clarification,
                instruction: ingredient.instruction ?? "", isIngredient: true, dependencies: [])
        }
        var usedIngredients = Set<String>()
        for step in recipe.steps {
            var dependencies: [String] = []
            var seenInputs = Set<String>()
            for input in step.inputs {
                let dependency: String
                let reference: String
                if let ingredient = input.ingredient, input.output == nil, ingredientIDs.contains(ingredient) {
                    dependency = ingredient; reference = "ingredient:\(ingredient)"; usedIngredients.insert(ingredient)
                } else if let output = input.output, input.ingredient == nil, let producer = producers[output] {
                    dependency = producer; reference = "output:\(output)"
                } else { throw RecipeError.invalid("Unresolved or ambiguous input in \(step.id).") }
                guard seenInputs.insert(reference).inserted else { throw RecipeError.invalid("Repeated input in \(step.id).") }
                if !dependencies.contains(dependency) { dependencies.append(dependency) }
            }
            let ordering = step.after ?? []
            guard Set(ordering).count == ordering.count else { throw RecipeError.invalid("Repeated ordering dependency in \(step.id).") }
            for dependency in ordering {
                guard stepIDs.contains(dependency) else { throw RecipeError.invalid("Unresolved operation: \(dependency)") }
                if !dependencies.contains(dependency) { dependencies.append(dependency) }
            }
            dependencies.sort { displayOrder.firstIndex(of: $0)! < displayOrder.firstIndex(of: $1)! }
            cells[step.id] = RecipeCell(id: step.id, label: step.action, amount: step.duration?.display,
                cue: step.clarification, instruction: step.instruction ?? "", isIngredient: false, dependencies: dependencies)
        }
        guard usedIngredients == Set(ingredientIDs) else { throw RecipeError.invalid("Recipe ingredients have no destination.") }
        var visiting = Set<String>(), visited = Set<String>()
        func visit(_ id: String) throws {
            if visited.contains(id) { return }
            guard visiting.insert(id).inserted else { throw RecipeError.invalid("Recipe dependencies contain a cycle.") }
            for input in cells[id]!.dependencies { try visit(input) }
            visiting.remove(id); visited.insert(id)
        }
        for id in ids { try visit(id) }
        self.recipe = recipe; self.cells = cells; self.order = displayOrder
        self.ingredientOrder = displayOrder.filter { cells[$0]!.isIngredient }
    }
    func dependents(of id: String) -> [String] { order.filter { cells[$0]!.dependencies.contains(id) } }
}
