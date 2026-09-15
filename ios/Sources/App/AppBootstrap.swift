import Foundation

struct AppLaunchConfiguration {
    static let testSuiteName = "local.kitchentable.ui-tests"

    let arguments: [String]

    init(arguments: [String] = ProcessInfo.processInfo.arguments) {
        self.arguments = arguments
    }

    var isUITesting: Bool { arguments.contains("--ui-testing") }
    var resetsSession: Bool { isUITesting && arguments.contains("--reset-session") }
    var seedsImports: Bool { isUITesting && arguments.contains("--seed-imports") }
    var skipsWalkthrough: Bool { isUITesting && arguments.contains("--skip-walkthrough") }

    func makeUserDefaults() -> UserDefaults {
        let defaults = isUITesting ? UserDefaults(suiteName: Self.testSuiteName)! : .standard
        if resetsSession { defaults.removePersistentDomain(forName: Self.testSuiteName) }
        return defaults
    }
}

enum AppBootstrap {
    @MainActor
    static func makeRecipeLibrary(launch: AppLaunchConfiguration) throws -> RecipeLibrary {
        let directory = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ).appendingPathComponent("KitchenTable", isDirectory: true)

        let stores = try ["baba-ganoush", "banana-muffins"].map {
            try makeSessionStore(recipeID: $0, directory: directory, launch: launch)
        }
        let incomingDirectory = launch.isUITesting ? directory.appendingPathComponent("ui-test-imports") : directory
        if launch.resetsSession && launch.isUITesting {
            try? FileManager.default.removeItem(at: incomingDirectory)
        }
        let repository = try IncomingRecipeRepository(directory: incomingDirectory)
        if launch.seedsImports {
            try repository.capture(url: URL(string: "https://example.com/first")!, title: "Sunday baking")
            try repository.capture(url: URL(string: "https://example.com/second")!, title: "Dinner inspiration")
        }
        return RecipeLibrary(
            stores: stores,
            incoming: try IncomingRecipeStore(repository: repository),
            directory: incomingDirectory
        )
    }

    @MainActor
    private static func makeSessionStore(
        recipeID: String,
        directory: URL,
        launch: AppLaunchConfiguration
    ) throws -> SessionStore {
        let graph = try RecipeGraph(recipe: Recipe.bundled(id: recipeID))
        let filename = launch.isUITesting ? "ui-test-session.json" : "\(recipeID)-session.json"
        let sessionURL = directory.appendingPathComponent(filename)
        if launch.resetsSession {
            try? FileManager.default.removeItem(at: sessionURL)
            try? FileManager.default.removeItem(
                at: sessionURL.deletingPathExtension().appendingPathExtension("edits.json")
            )
        }

        let store = SessionStore(
            graph: graph,
            fileURL: sessionURL,
            layout: try RecipeTableLayout.generated(for: graph)
        )
        store.onPrepareTimerAlert = { CookingTimerNotifications.shared.prepareForegroundAlert() }
        store.onTimerAlert = { CookingTimerNotifications.shared.foregroundAlert() }
        return store
    }
}
