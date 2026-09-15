import RevenueCat
import SwiftUI

enum PlusAccessPhase: Equatable {
    case loading
    case available(hasPlus: Bool, plan: PlusPlan?)
    case unavailable
}

@MainActor
final class PlusAccessStore: ObservableObject {
    static let entitlementID = "plus"
    static let offeringID = Bundle.main.object(
        forInfoDictionaryKey: "RevenueCatOfferingIdentifier"
    ) as? String ?? "plus_features"

    @Published private(set) var phase: PlusAccessPhase = .loading
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
    private var pendingAction: (() -> Void)?
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
            setPhase(.available(hasPlus: true, plan: nil))
        } else {
            updateThemeAccess(false)
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
        if hasPlus {
            action()
            return
        }
        guard client.isConfigured else {
            alertMessage = "Kitchen Table Plus isn’t available in this build."
            return
        }
        pendingAction = action
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
        guard hasPlus else { return }
        isPaywallPresented = false
        let action = pendingAction
        pendingAction = nil
        action?()
    }

    func dismissPaywall() {
        isPaywallPresented = false
        pendingAction = nil
    }

    private func update(with customerInfo: CustomerInfo) {
        let entitlement = customerInfo.entitlements.active[Self.entitlementID]
        setPhase(.available(hasPlus: entitlement != nil, plan: entitlement.map(PlusPlan.init)))
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
        updateThemeAccess(hasPlus)
    }

    private func updateThemeAccess(_ active: Bool) {
        let themes = active ? Set(AppTheme.allCases) : Set([.original])
        if appearance.availableThemes != themes {
            appearance.availableThemes = themes
        }
    }
}
