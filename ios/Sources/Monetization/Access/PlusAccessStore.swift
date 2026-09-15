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
    @Published private(set) var offering: Offering?
    @Published private(set) var isRestoring = false
    @Published var isPaywallPresented = false
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
            update(with: try await client.customerInfo())
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
        let entitlement = customerInfo.entitlements.active[Self.entitlementID]
        hasPremiumThemes = customerInfo.entitlements.active[Self.premiumThemesEntitlementID] != nil
        setPhase(.available(hasPlus: entitlement != nil, plan: entitlement.map(PlusPlan.init)))
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
}
