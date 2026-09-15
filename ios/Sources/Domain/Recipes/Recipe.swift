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
        // instead of silently accepting malformed recipe data.
        try RecipeValidator.validateShape(JSONSerialization.jsonObject(with: data))
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let recipe = try decoder.decode(Recipe.self, from: data)
        try RecipeValidator.validateFields(in: recipe)
        return recipe
    }
}

enum RecipeError: LocalizedError {
    case invalid(String)
    var errorDescription: String? { switch self { case .invalid(let message): return message } }
}
