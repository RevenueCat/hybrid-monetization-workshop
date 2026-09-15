import RevenueCat
import SwiftUI

enum PlusAccessPhase: Equatable {
    case loading
    case available(hasPlus: Bool, plan: PlusPlan?)
    case unavailable
}

@MainActor
final class PlusAccessStore: ObservableObject {
    static let entitlementID = Bundle.main.object(
        forInfoDictionaryKey: "RevenueCatPlusEntitlementIdentifier"
    ) as? String ?? "plus"
    static let premiumThemesEntitlementID = Bundle.main.object(
        forInfoDictionaryKey: "RevenueCatPremiumThemesEntitlementIdentifier"
    ) as? String ?? "premium_themes"
    static let offeringID = Bundle.main.object(
        forInfoDictionaryKey: "RevenueCatOfferingIdentifier"
    ) as? String ?? "plus_ad_free"

    @Published private(set) var phase: PlusAccessPhase = .loading
    @Published private(set) var hasPremiumThemes = false
    @Published private(set) var premiumThemesExpirationDate: Date?
    @Published private(set) var offering: Offering?
    @Published private(set) var isRestoring = false
    @Published var isPaywallPresented = false
    @Published var requestedPremiumTheme: AppTheme?
    @Published var alertMessage: String?

    var hasPlus: Bool {
        guard case .available(let hasPlus, _) = phase else { return false }
        return hasPlus
    }

    var plan: PlusPlan? {
        guard case .available(_, let plan) = phase else { return nil }
        return plan
    }

    var isCustomerInfoLoaded: Bool { phase != .loading }

    private let appearance: AppearanceStore
    private let client: PlusAccessClient
    private enum Requirement { case plus, premiumThemes }
    private var pendingAction: (requirement: Requirement, action: () -> Void)?
    private let testingBypass: Bool
    private var presentPaywallAfterThemeUnlock = false
    private var expirationTask: Task<Void, Never>?

    init(
        appearance: AppearanceStore,
        client: PlusAccessClient = LivePlusAccessClient(),
        arguments: [String] = ProcessInfo.processInfo.arguments
    ) {
        self.appearance = appearance
        self.client = client
        testingBypass = arguments.contains("--ui-testing") && !arguments.contains("--revenuecat-test-user")

        if testingBypass {
            hasPremiumThemes = true
            setPhase(.available(hasPlus: true, plan: nil))
        } else {
            updateThemeAccess()
        }
    }

    func observeCustomerInfo() async {
        guard !testingBypass else { return }
        guard client.isConfigured else {
            setPhase(.unavailable)
            return
        }

        await loadOffering()
        do {
            update(with: try await client.customerInfo(forceRefresh: false))
        } catch {
            setPhase(.unavailable)
            alertMessage = "Kitchen Table Plus couldn’t be checked. Please try again."
        }

        for await customerInfo in client.customerInfoStream {
            update(with: customerInfo)
        }
    }

    func requireAccess(perform action: @escaping () -> Void) {
        require(.plus, unavailableMessage: "Kitchen Table Plus isn’t available in this build.", action: action)
    }

    func requirePremiumThemeAccess(perform action: @escaping () -> Void) {
        require(.premiumThemes, unavailableMessage: "Premium themes aren’t available in this build.", action: action)
    }

    func requestPremiumTheme(_ theme: AppTheme) {
        if theme == .original || hasPremiumThemes {
            appearance.theme = theme
            return
        }
        guard client.isConfigured else {
            alertMessage = "Premium themes aren’t available in this build."
            return
        }
        requestedPremiumTheme = theme
    }

    func choosePlusForRequestedTheme() {
        guard let theme = requestedPremiumTheme else { return }
        pendingAction = (.premiumThemes, { [weak appearance] in appearance?.theme = theme })
        presentPaywallAfterThemeUnlock = true
        requestedPremiumTheme = nil
    }

    func themeUnlockSheetDidDismiss() {
        guard presentPaywallAfterThemeUnlock else { return }
        presentPaywallAfterThemeUnlock = false
        presentPreparedPaywall()
    }

    func completeVerifiedThemeReward() async {
        await refreshCustomerInfo(force: true)
        guard hasPremiumThemes else {
            alertMessage = "The theme reward couldn’t be confirmed. Please try again."
            return
        }
        applyRequestedPremiumTheme()
    }

    func presentPaywall() {
        requireAccess {}
    }

    func restorePurchases() async {
        guard !isRestoring else { return }
        guard client.isConfigured else {
            alertMessage = "Kitchen Table Plus isn’t available in this build."
            return
        }
        isRestoring = true
        defer { isRestoring = false }
        do {
            update(with: try await client.restorePurchases())
            alertMessage = hasPlus
                ? "Kitchen Table Plus has been restored."
                : "No Kitchen Table Plus purchase was found."
        } catch {
            alertMessage = "Purchases couldn’t be restored. Please try again."
        }
    }

    func refresh(with customerInfo: CustomerInfo) {
        update(with: customerInfo)
    }

    func refreshCustomerInfo(force: Bool = false) async {
        guard !testingBypass, client.isConfigured else { return }
        do {
            update(with: try await client.customerInfo(forceRefresh: force))
        } catch {
            alertMessage = "Kitchen Table Plus couldn’t be checked. Please try again."
        }
    }

    func reportCustomerCenterError() {
        alertMessage = "Subscription details couldn’t be updated. Please try again."
    }

    func complete(with customerInfo: CustomerInfo) {
        update(with: customerInfo)
        guard let pendingAction,
              satisfies(pendingAction.requirement) else { return }
        isPaywallPresented = false
        self.pendingAction = nil
        pendingAction.action()
    }

    func dismissPaywall() {
        isPaywallPresented = false
        pendingAction = nil
    }

    private func update(with customerInfo: CustomerInfo) {
        let previouslyHadPremiumThemes = hasPremiumThemes
        let entitlement = customerInfo.entitlements.active[Self.entitlementID]
        let themesEntitlement = customerInfo.entitlements.active[Self.premiumThemesEntitlementID]
        hasPremiumThemes = themesEntitlement != nil
        premiumThemesExpirationDate = entitlement == nil ? themesEntitlement?.expirationDate : nil
        setPhase(.available(hasPlus: entitlement != nil, plan: entitlement.map(PlusPlan.init)))
        scheduleExpirationRefresh()
        if !previouslyHadPremiumThemes, hasPremiumThemes {
            applyRequestedPremiumTheme()
        } else if previouslyHadPremiumThemes, !hasPremiumThemes, entitlement == nil {
            alertMessage = "Your theme preview has ended. Original is active again."
        }
    }

    private func require(
        _ requirement: Requirement,
        unavailableMessage: String,
        action: @escaping () -> Void
    ) {
        if satisfies(requirement) {
            action()
            return
        }
        guard client.isConfigured else {
            alertMessage = unavailableMessage
            return
        }
        pendingAction = (requirement, action)
        presentPreparedPaywall()
    }

    private func presentPreparedPaywall() {
        if offering != nil {
            isPaywallPresented = true
        } else {
            Task {
                await loadOffering()
                if offering != nil {
                    isPaywallPresented = true
                } else {
                    pendingAction = nil
                }
            }
        }
    }

    private func satisfies(_ requirement: Requirement) -> Bool {
        switch requirement {
        case .plus: hasPlus
        case .premiumThemes: hasPremiumThemes
        }
    }

    private func loadOffering() async {
        guard offering == nil, client.isConfigured else { return }
        do {
            let offerings = try await client.offerings()
            guard let configured = offerings.offering(identifier: Self.offeringID) else {
                alertMessage = "Kitchen Table Plus isn’t available right now."
                return
            }
            offering = configured
        } catch {
            alertMessage = "Kitchen Table Plus couldn’t be loaded. Please try again."
        }
    }

    private func setPhase(_ phase: PlusAccessPhase) {
        self.phase = phase
        updateThemeAccess()
    }

    private func updateThemeAccess() {
        let themes = hasPremiumThemes ? Set(AppTheme.allCases) : Set([.original])
        if appearance.availableThemes != themes {
            appearance.availableThemes = themes
        }
    }

    private func scheduleExpirationRefresh() {
        expirationTask?.cancel()
        guard let expiration = premiumThemesExpirationDate, expiration > Date() else { return }
        expirationTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(expiration.timeIntervalSinceNow))
            guard !Task.isCancelled else { return }
            await self?.refreshCustomerInfo(force: true)
        }
    }

    private func applyRequestedPremiumTheme() {
        guard let theme = requestedPremiumTheme else { return }
        requestedPremiumTheme = nil
        appearance.theme = theme
    }
}
