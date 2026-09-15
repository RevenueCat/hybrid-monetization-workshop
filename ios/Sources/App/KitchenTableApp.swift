import SwiftUI

@main
struct KitchenTableApp: App {
    @StateObject private var appearance: AppearanceStore
    @StateObject private var walkthrough: WalkthroughStore
    @StateObject private var plus: PlusAccessStore
    @StateObject private var ads: AdSupportStore
    @StateObject private var themeRewards: ThemeRewardStore
    @Environment(\.scenePhase) private var phase
    private let isUITesting: Bool
    private let result: Result<RecipeLibrary, Error>

    init() {
        CookingTimerNotifications.shared.configure()
        let launch = AppLaunchConfiguration()
        isUITesting = launch.isUITesting
        let defaults = launch.makeUserDefaults()
        _walkthrough = StateObject(wrappedValue: WalkthroughStore(defaults: defaults, skip: launch.skipsWalkthrough))
        let appearance = AppearanceStore(defaults: defaults)
        _appearance = StateObject(wrappedValue: appearance)
        RevenueCatConfiguration.configureIfAvailable(arguments: launch.arguments)
        _plus = StateObject(wrappedValue: PlusAccessStore(appearance: appearance, arguments: launch.arguments))
        _ads = StateObject(wrappedValue: AdSupportStore(arguments: launch.arguments))
        _themeRewards = StateObject(wrappedValue: ThemeRewardStore(arguments: launch.arguments))
        result = Result { try AppBootstrap.makeRecipeLibrary(launch: launch) }
    }

    var body: some Scene {
        WindowGroup {
            switch result {
            case .success(let library):
                WalkthroughRoot(library: library, walkthrough: walkthrough)
                    .environmentObject(appearance)
                    .environmentObject(plus)
                    .environmentObject(ads)
                    .preferredColorScheme(appearance.mode.scheme)
                    .plusPaywallPresenter(plus, themeRewards: themeRewards, appearance: appearance)
                    .task { await plus.observeCustomerInfo() }
                    .task(id: plus.phase) { ads.updateAccess(plus.phase) }
                    .task(id: ThemeRewardAccessContext(phase: plus.phase, hasPremiumThemes: plus.hasPremiumThemes)) {
                        themeRewards.updateAccess(phase: plus.phase, hasPremiumThemes: plus.hasPremiumThemes)
                    }
                    .task {
                        library.incoming?.setActive(phase == .active)
                        appearance.setIconsActive(phase == .active && !isUITesting)
                    }
                    .onChange(of: phase) { _, value in
                        library.incoming?.setActive(value == .active)
                        appearance.setIconsActive(value == .active && !isUITesting)
                        if value == .active {
                            Task { await plus.refreshCustomerInfo(force: true) }
                        }
                    }

            case .failure(let error): ContentUnavailableView("Recipe unavailable", systemImage: "tablecells", description: Text(error.localizedDescription))
            }
        }
    }
}
