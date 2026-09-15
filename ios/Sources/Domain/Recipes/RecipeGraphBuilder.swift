struct RecipeGraphBuilder {
    private enum ResolvedInput: Hashable {
        case ingredient(String)
        case output(String, producer: String)

        var dependency: String {
            switch self {
            case .ingredient(let id): id
            case .output(_, let producer): producer
            }
        }
    }

    let recipe: Recipe
    let displayOrder: [String]

    func build() throws -> RecipeGraph {
        let ingredientIDs = Set(recipe.ingredients.map(\.id))
        let stepIDs = Set(recipe.steps.map(\.id))
        let allIDs = ingredientIDs.union(stepIDs)
        try validateDisplayOrder(allIDs: allIDs)

        let producers = try makeOutputProducers(allIDs: allIDs)
        let orderRank = Dictionary(uniqueKeysWithValues: displayOrder.enumerated().map { ($1, $0) })
        var usedIngredients = Set<String>()
        var cells = makeIngredientCells()

        for step in recipe.steps {
            let cell = try makeStepCell(
                step,
                ingredientIDs: ingredientIDs,
                stepIDs: stepIDs,
                producers: producers,
                orderRank: orderRank,
                usedIngredients: &usedIngredients
            )
            cells[step.id] = cell
        }

        guard usedIngredients == ingredientIDs else {
            throw RecipeError.invalid("Recipe ingredients have no destination.")
        }
        try validateAcyclic(cells: cells)
        return RecipeGraph(recipe: recipe, cells: cells, order: displayOrder)
    }

    private func validateDisplayOrder(allIDs: Set<String>) throws {
        let recipeIDCount = recipe.ingredients.count + recipe.steps.count
        guard allIDs.count == recipeIDCount,
              Set(displayOrder) == allIDs,
              displayOrder.count == recipeIDCount else {
            throw RecipeError.invalid("Recipe identifiers and grid placements must match exactly.")
        }
    }

    private func makeOutputProducers(allIDs: Set<String>) throws -> [String: String] {
        var producers: [String: String] = [:]
        for step in recipe.steps {
            for output in step.outputs {
                guard producers[output.id] == nil, !allIDs.contains(output.id) else {
                    throw RecipeError.invalid("Duplicate recipe output: \(output.id)")
                }
                producers[output.id] = step.id
            }
        }
        return producers
    }

    private func makeIngredientCells() -> [String: RecipeCell] {
        Dictionary(uniqueKeysWithValues: recipe.ingredients.map { ingredient in
            (ingredient.id, RecipeCell(
                id: ingredient.id,
                label: ingredient.name,
                amount: ingredient.quantity?.replacingOccurrences(of: "1/4", with: "¼"),
                cue: ingredient.clarification,
                instruction: ingredient.instruction ?? "",
                isIngredient: true,
                dependencies: []
            ))
        })
    }

    private func makeStepCell(
        _ step: Recipe.Step,
        ingredientIDs: Set<String>,
        stepIDs: Set<String>,
        producers: [String: String],
        orderRank: [String: Int],
        usedIngredients: inout Set<String>
    ) throws -> RecipeCell {
        var dependencies: [String] = []
        var seenInputs = Set<ResolvedInput>()

        for input in step.inputs {
            let resolved = try resolve(input, in: step.id, ingredientIDs: ingredientIDs, producers: producers)
            guard seenInputs.insert(resolved).inserted else {
                throw RecipeError.invalid("Repeated input in \(step.id).")
            }
            if case .ingredient(let id) = resolved { usedIngredients.insert(id) }
            appendUnique(resolved.dependency, to: &dependencies)
        }

        let ordering = step.after ?? []
        guard Set(ordering).count == ordering.count else {
            throw RecipeError.invalid("Repeated ordering dependency in \(step.id).")
        }
        for dependency in ordering {
            guard stepIDs.contains(dependency) else {
                throw RecipeError.invalid("Unresolved operation: \(dependency)")
            }
            appendUnique(dependency, to: &dependencies)
        }
        dependencies.sort { orderRank[$0, default: .max] < orderRank[$1, default: .max] }

        return RecipeCell(
            id: step.id,
            label: step.action,
            amount: step.duration?.display,
            cue: step.clarification,
            instruction: step.instruction ?? "",
            isIngredient: false,
            dependencies: dependencies
        )
    }

    private func resolve(
        _ input: Recipe.Step.Input,
        in stepID: String,
        ingredientIDs: Set<String>,
        producers: [String: String]
    ) throws -> ResolvedInput {
        if let ingredient = input.ingredient,
           input.output == nil,
           ingredientIDs.contains(ingredient) {
            return .ingredient(ingredient)
        }
        if let output = input.output,
           input.ingredient == nil,
           let producer = producers[output] {
            return .output(output, producer: producer)
        }
        throw RecipeError.invalid("Unresolved or ambiguous input in \(stepID).")
    }

    private func appendUnique(_ id: String, to values: inout [String]) {
        if !values.contains(id) { values.append(id) }
    }

    private func validateAcyclic(cells: [String: RecipeCell]) throws {
        var visiting = Set<String>()
        var visited = Set<String>()

        func visit(_ id: String) throws {
            guard !visited.contains(id) else { return }
            guard visiting.insert(id).inserted else {
                throw RecipeError.invalid("Recipe dependencies contain a cycle.")
            }
            guard let cell = cells[id] else {
                throw RecipeError.invalid("Unresolved recipe dependency: \(id)")
            }
            try cell.dependencies.forEach(visit)
            visiting.remove(id)
            visited.insert(id)
        }

        try displayOrder.forEach(visit)
    }
}
