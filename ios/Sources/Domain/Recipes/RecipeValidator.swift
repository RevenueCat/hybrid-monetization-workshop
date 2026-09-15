import Foundation

enum RecipeValidator {
    static func validateShape(_ raw: Any) throws {
        let root = try object(
            raw,
            required: ["schema_version", "id", "title", "ingredients", "steps"],
            optional: ["yield", "photo", "source_url"]
        )
        try array(root["ingredients"]).forEach {
            _ = try object($0, required: ["id", "name"], optional: ["quantity", "clarification", "instruction"])
        }
        try array(root["steps"]).forEach(validateStepShape)
    }

    static func validateFields(in recipe: Recipe) throws {
        guard recipe.schemaVersion == 1, !recipe.steps.isEmpty else {
            throw RecipeError.invalid("Unsupported recipe version or empty step list.")
        }
        try identifier(recipe.id)
        try text(recipe.title)
        try text(recipe.yield)
        try validatePhoto(recipe.photo)
        try validateSourceURL(recipe.sourceUrl)
        try recipe.ingredients.forEach(validateIngredient)
        try recipe.steps.forEach(validateStep)
    }

    private static func validateStepShape(_ raw: Any) throws {
        let step = try object(
            raw,
            required: ["id", "action", "inputs", "outputs"],
            optional: ["after", "duration", "clarification", "instruction"]
        )
        try array(step["inputs"]).forEach { rawInput in
            let input = try object(rawInput, required: [], optional: ["ingredient", "output", "allocation", "optional"])
            guard (input["ingredient"] != nil) != (input["output"] != nil) else {
                throw RecipeError.invalid("Each input must identify either an ingredient or an output.")
            }
        }
        try array(step["outputs"]).forEach {
            _ = try object($0, required: ["id", "name"])
        }
        if let duration = step["duration"] {
            _ = try object(duration, required: ["min", "max", "unit"], optional: ["approximate"])
        }
    }

    private static func validateIngredient(_ ingredient: Recipe.Ingredient) throws {
        try identifier(ingredient.id)
        try text(ingredient.name)
        try text(ingredient.quantity)
        try text(ingredient.clarification)
        try text(ingredient.instruction, compact: false)
    }

    private static func validateStep(_ step: Recipe.Step) throws {
        try identifier(step.id)
        try text(step.action)
        try text(step.clarification)
        try text(step.instruction, compact: false)
        for input in step.inputs {
            if let ingredient = input.ingredient { try identifier(ingredient) }
            if let output = input.output { try identifier(output) }
            try text(input.allocation)
        }
        for output in step.outputs {
            try identifier(output.id)
            try text(output.name)
        }
        try (step.after ?? []).forEach(identifier)
        if let duration = step.duration {
            guard duration.min.isFinite,
                  duration.max.isFinite,
                  duration.min >= 0,
                  duration.max >= duration.min,
                  ["sec", "min", "h"].contains(duration.unit) else {
                throw RecipeError.invalid("Invalid recipe duration.")
            }
        }
    }

    private static func validatePhoto(_ photo: String?) throws {
        guard let photo else { return }
        let pattern = "^[A-Za-z0-9_-][A-Za-z0-9._-]*(/[A-Za-z0-9_-][A-Za-z0-9._-]*)*$"
        guard photo.range(of: pattern, options: .regularExpression)?.upperBound == photo.endIndex else {
            throw RecipeError.invalid("Recipe photo must be a relative asset path.")
        }
    }

    private static func validateSourceURL(_ source: String?) throws {
        guard let source else { return }
        guard let url = URL(string: source),
              ["http", "https"].contains(url.scheme ?? ""),
              url.host?.isEmpty == false else {
            throw RecipeError.invalid("Recipe source must be an HTTP(S) URL.")
        }
    }

    private static func identifier(_ value: String) throws {
        let pattern = "^[a-z0-9]+(?:-[a-z0-9]+)*$"
        guard value.range(of: pattern, options: .regularExpression)?.upperBound == value.endIndex else {
            throw RecipeError.invalid("Invalid recipe identifier: \(value)")
        }
    }

    private static func text(_ value: String?, compact: Bool = true) throws {
        guard let value else { return }
        guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !compact || (!value.contains("\n") && !value.contains("\r")) else {
            throw RecipeError.invalid("Recipe text must be nonblank; compact fields must be a single phrase.")
        }
    }

    private static func object(
        _ raw: Any,
        required: [String],
        optional: [String] = []
    ) throws -> [String: Any] {
        guard let value = raw as? [String: Any] else {
            throw RecipeError.invalid("Recipe fields do not match the runtime format.")
        }
        let keys = Set(value.keys)
        guard Set(required).isSubset(of: keys),
              keys.isSubset(of: Set(required + optional)),
              !value.values.contains(where: { $0 is NSNull }) else {
            throw RecipeError.invalid("Recipe fields do not match the runtime format.")
        }
        return value
    }

    private static func array(_ raw: Any?) throws -> [Any] {
        guard let value = raw as? [Any] else {
            throw RecipeError.invalid("Expected a recipe array.")
        }
        return value
    }
}
