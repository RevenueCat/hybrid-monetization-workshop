import SwiftUI

@main
struct KitchenTableApp: App {
    @StateObject private var appearance: AppearanceStore
    @StateObject private var walkthrough: WalkthroughStore
    @StateObject private var spoons: SpoonStore
    @StateObject private var rewards: SpoonRewardStore
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
        let spoonStore = SpoonStore.live(arguments: launch.arguments)
        _spoons = StateObject(wrappedValue: spoonStore)
        _rewards = StateObject(wrappedValue: SpoonRewardStore.live(spoons: spoonStore, arguments: launch.arguments))
        result = Result { try AppBootstrap.makeRecipeLibrary(launch: launch) }
    }

    var body: some Scene {
        WindowGroup {
            switch result {
            case .success(let library):
                WalkthroughRoot(library: library, walkthrough: walkthrough)
                    .environmentObject(appearance)
                    .environmentObject(spoons)
                    .environmentObject(rewards)
                    .preferredColorScheme(appearance.mode.scheme)
                    .task {
                        library.incoming?.setActive(phase == .active)
                        appearance.setIconsActive(phase == .active && !isUITesting)
                    }
                    .task { await rewards.start() }
                    .onChange(of: phase) { _, value in
                        library.incoming?.setActive(value == .active)
                        appearance.setIconsActive(value == .active && !isUITesting)
                        if value == .active {
                            Task {
                                await spoons.refresh(force: true)
                                await rewards.refreshDailyEligibility()
                            }
                        }
                    }

            case .failure(let error): ContentUnavailableView("Recipe unavailable", systemImage: "tablecells", description: Text(error.localizedDescription))
            }
        }
    }
}
