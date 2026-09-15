enum RecipeCatalog {
    static func displayOrder(for recipe: Recipe) -> [String] {
        guard recipe.id == "baba-ganoush" else {
            return recipe.ingredients.map(\.id) + recipe.steps.map(\.id)
        }
        return [
            "preheat", "eggplant", "cut-eggplant", "roast-eggplant", "cool", "extract-flesh",
            "garlic", "peel-garlic", "olive-oil", "roast-garlic", "separate", "tahini", "lemon",
            "cumin", "salt", "sweet-paprika", "blend-base", "mix", "parsley", "serve"
        ]
    }
}
