import RevenueCat

/// Keeps RevenueCat SDK calls at the edge of the access model.
protocol PlusAccessClient {
    var isConfigured: Bool { get }
    var customerInfoStream: AsyncStream<CustomerInfo> { get }
    func customerInfo() async throws -> CustomerInfo
    func offerings() async throws -> Offerings
    func restorePurchases() async throws -> CustomerInfo
}

struct LivePlusAccessClient: PlusAccessClient {
    var isConfigured: Bool { Purchases.isConfigured }
    var customerInfoStream: AsyncStream<CustomerInfo> { Purchases.shared.customerInfoStream }

    func customerInfo() async throws -> CustomerInfo {
        try await Purchases.shared.customerInfo()
    }

    func offerings() async throws -> Offerings {
        try await Purchases.shared.offerings()
    }

    func restorePurchases() async throws -> CustomerInfo {
        try await Purchases.shared.restorePurchases()
    }
}
