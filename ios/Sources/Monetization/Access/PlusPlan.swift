import Foundation
import RevenueCat

struct PlusPlan: Equatable {
    enum BillingPeriod: String {
        case monthly = "Plus Monthly"
        case yearly = "Plus Yearly"
        case unknown = "Kitchen Table Plus"
    }

    let billingPeriod: BillingPeriod
    let expirationDate: Date?
    let willRenew: Bool

    init(entitlement: EntitlementInfo) {
        billingPeriod = Self.billingPeriod(for: entitlement.productIdentifier)
        expirationDate = entitlement.expirationDate
        willRenew = entitlement.willRenew
    }

    static func billingPeriod(for productIdentifier: String) -> BillingPeriod {
        switch productIdentifier {
        case "kitchen_table_plus_monthly": .monthly
        case "kitchen_table_plus_yearly": .yearly
        default: .unknown
        }
    }
}
