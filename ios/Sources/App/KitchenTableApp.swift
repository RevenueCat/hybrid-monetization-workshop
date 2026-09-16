import SwiftUI

@main
struct KitchenTableApp: App {
    @StateObject private var appearance: AppearanceStore
    @StateObject private var walkthrough: WalkthroughStore
    @StateObject private var spoons: SpoonStore
    @Environment(\.scenePhase) private var phase
    private let isUITesting: Bool
    private let result: Result<RecipeLibrary, Error>

    init() {
        CookingTimerNotifications.shared.configure()
        let launch = AppLaunchConfiguration()
        RevenueCatConfiguration.configureIfAvailable(arguments: launch.arguments)
        isUITesting = launch.isUITesting
        let defaults = launch.makeUserDefaults()
        _walkthrough = StateObject(wrappedValue: WalkthroughStore(defaults: defaults, skip: launch.skipsWalkthrough))
        _appearance = StateObject(wrappedValue: AppearanceStore(defaults: defaults))
        _spoons = StateObject(wrappedValue: SpoonStore.live(arguments: launch.arguments))
        result = Result { try AppBootstrap.makeRecipeLibrary(launch: launch) }
    }

    var body: some Scene {
        WindowGroup {
            switch result {
            case .success(let library):
                WalkthroughRoot(library: library, walkthrough: walkthrough)
                    .environmentObject(appearance)
                    .environmentObject(spoons)
                    .preferredColorScheme(appearance.mode.scheme)
                    .task {
                        library.incoming?.setActive(phase == .active)
                        appearance.setIconsActive(phase == .active && !isUITesting)
                    }
                    .onChange(of: phase) { _, value in
                        library.incoming?.setActive(value == .active)
                        appearance.setIconsActive(value == .active && !isUITesting)
                        if value == .active { Task { await spoons.refresh(force: true) } }
                    }

            case .failure(let error): ContentUnavailableView("Recipe unavailable", systemImage: "tablecells", description: Text(error.localizedDescription))
            }
        }
    }
}
