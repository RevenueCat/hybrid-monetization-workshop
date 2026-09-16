import Foundation
import RevenueCat

struct SpoonProduct: Identifiable, Equatable {
    enum Kind: Equatable { case monthly, oneTime }
    let id: String
    let amount: Int
    let kind: Kind
    let title: String
    let detail: String
    let localizedPrice: String
}

enum SpoonClientError: LocalizedError {
    case notConfigured
    case offeringUnavailable
    case productUnavailable

    var errorDescription: String? {
        switch self {
        case .notConfigured: "RevenueCat is not configured for this build."
        case .offeringUnavailable: "The Spoons shop is unavailable. Check the offering configuration."
        case .productUnavailable: "That Spoons option is no longer available."
        }
    }
}

@MainActor
protocol SpoonClient: AnyObject {
    var isConfigured: Bool { get }
    var appUserID: String? { get }
    func cachedBalance(currencyCode: String) -> Int?
    func loadBalance(currencyCode: String, forceRefresh: Bool) async throws -> Int
    func loadProducts(offeringIdentifier: String) async throws -> [SpoonProduct]
    func purchase(productID: String) async throws -> Bool
    func restore() async throws
}

@MainActor
final class RevenueCatSpoonClient: SpoonClient {
    private var packages: [String: Package] = [:]

    var isConfigured: Bool { Purchases.isConfigured }
    var appUserID: String? { Purchases.isConfigured ? Purchases.shared.appUserID : nil }

    func cachedBalance(currencyCode: String) -> Int? {
        guard Purchases.isConfigured else { return nil }
        return Purchases.shared.cachedVirtualCurrencies?[currencyCode]?.balance
    }

    func loadBalance(currencyCode: String, forceRefresh: Bool) async throws -> Int {
        guard Purchases.isConfigured else { throw SpoonClientError.notConfigured }
        if forceRefresh { Purchases.shared.invalidateVirtualCurrenciesCache() }
        return try await Purchases.shared.virtualCurrencies()[currencyCode]?.balance ?? 0
    }

    func loadProducts(offeringIdentifier: String) async throws -> [SpoonProduct] {
        guard Purchases.isConfigured else { throw SpoonClientError.notConfigured }
        let offerings = try await Purchases.shared.offerings()
        guard let offering = offerings.offering(identifier: offeringIdentifier) else {
            throw SpoonClientError.offeringUnavailable
        }
        packages = Dictionary(uniqueKeysWithValues: offering.availablePackages.map { ($0.identifier, $0) })
        return offering.availablePackages.compactMap(Self.product(for:))
            .sorted { lhs, rhs in
                if lhs.kind != rhs.kind { return lhs.kind == .monthly }
                return lhs.amount < rhs.amount
            }
    }

    func purchase(productID: String) async throws -> Bool {
        guard let package = packages[productID] else { throw SpoonClientError.productUnavailable }
        let result = try await Purchases.shared.purchase(package: package)
        return !result.userCancelled
    }

    func restore() async throws {
        guard Purchases.isConfigured else { throw SpoonClientError.notConfigured }
        _ = try await Purchases.shared.restorePurchases()
    }

    private static func product(for package: Package) -> SpoonProduct? {
        let amount: Int
        let kind: SpoonProduct.Kind
        let detail: String
        switch package.identifier {
        case "$rc_monthly":
            amount = 100
            kind = .monthly
            detail = "100 Spoons added every month"
        case "spoons_50":
            amount = 50
            kind = .oneTime
            detail = "Enough for 2 recipe imports"
        case "spoons_200":
            amount = 200
            kind = .oneTime
            detail = "Enough for 8 recipe imports"
        default:
            return nil
        }
        return .init(
            id: package.identifier,
            amount: amount,
            kind: kind,
            title: "\(amount) Spoons",
            detail: detail,
            localizedPrice: package.localizedPriceString
        )
    }
}

@MainActor
final class PreviewSpoonClient: SpoonClient {
    private(set) var balance = 60
    var isConfigured: Bool { true }
    var appUserID: String? { "ui-test-customer" }

    func cachedBalance(currencyCode: String) -> Int? { balance }
    func loadBalance(currencyCode: String, forceRefresh: Bool) async throws -> Int { balance }
    func loadProducts(offeringIdentifier: String) async throws -> [SpoonProduct] {
        [
            .init(id: "$rc_monthly", amount: 100, kind: .monthly, title: "100 Spoons", detail: "100 Spoons added every month", localizedPrice: "$2.99"),
            .init(id: "spoons_50", amount: 50, kind: .oneTime, title: "50 Spoons", detail: "Enough for 2 recipe imports", localizedPrice: "$1.99"),
            .init(id: "spoons_200", amount: 200, kind: .oneTime, title: "200 Spoons", detail: "Enough for 8 recipe imports", localizedPrice: "$5.99")
        ]
    }
    func purchase(productID: String) async throws -> Bool {
        balance += productID == "spoons_200" ? 200 : productID == "spoons_50" ? 50 : 100
        return true
    }
    func restore() async throws {}
    func spend(_ amount: Int) { balance = max(0, balance - amount) }
}
