import Foundation
import Combine

@MainActor
final class SpoonStore: ObservableObject {
    enum ImportResult { case imported, needsSpoons, failed }

    @Published private(set) var balance: Int?
    @Published private(set) var products: [SpoonProduct] = []
    @Published private(set) var isLoading = false
    @Published private(set) var purchasingProductID: String?
    @Published private(set) var spendingImportID: String?
    @Published var message: String?

    let configuration: SpoonConfiguration
    private let client: SpoonClient
    private let spendingClient: SpoonSpendingClient

    init(configuration: SpoonConfiguration, client: SpoonClient, spendingClient: SpoonSpendingClient) {
        self.configuration = configuration
        self.client = client
        self.spendingClient = spendingClient
        balance = client.cachedBalance(currencyCode: configuration.currencyCode)
    }

    static func live(arguments: [String] = ProcessInfo.processInfo.arguments) -> SpoonStore {
        let configuration = SpoonConfiguration.current()
        if arguments.contains("--ui-testing") {
            let startingBalance = arguments.first(where: { $0.hasPrefix("--spoons-balance=") })
                .flatMap { Int($0.dropFirst("--spoons-balance=".count)) } ?? 60
            let client = PreviewSpoonClient(balance: startingBalance)
            return .init(
                configuration: configuration,
                client: client,
                spendingClient: PreviewSpoonSpendingClient(client: client, importCost: configuration.importCost)
            )
        }
        return .init(
            configuration: configuration,
            client: RevenueCatSpoonClient(),
            spendingClient: LocalSpoonSpendingClient(serviceURL: configuration.serviceURL)
        )
    }

    var balanceLabel: String { balance.map(String.init) ?? "—" }
    var appUserID: String? { client.appUserID }

    func refreshBalance(force: Bool = false) async {
        guard client.isConfigured else { return }
        do {
            balance = try await client.loadBalance(currencyCode: configuration.currencyCode, forceRefresh: force)
        } catch {
            message = error.localizedDescription
        }
    }

    func applyPreviewReward(_ amount: Int) {
        guard let preview = client as? PreviewSpoonClient else { return }
        preview.credit(amount)
        balance = preview.balance
    }

    func refresh(force: Bool = false) async {
        guard client.isConfigured else {
            message = SpoonClientError.notConfigured.localizedDescription
            return
        }
        isLoading = true
        defer { isLoading = false }
        do {
            balance = try await client.loadBalance(currencyCode: configuration.currencyCode, forceRefresh: force)
            products = try await client.loadProducts(offeringIdentifier: configuration.offeringIdentifier)
            message = nil
        } catch {
            message = error.localizedDescription
        }
    }

    func purchase(_ product: SpoonProduct) async {
        purchasingProductID = product.id
        defer { purchasingProductID = nil }
        do {
            guard try await client.purchase(productID: product.id) else { return }
            balance = try await client.loadBalance(currencyCode: configuration.currencyCode, forceRefresh: true)
            message = "Your Spoons are ready."
        } catch {
            message = error.localizedDescription
        }
    }

    func restore() async {
        isLoading = true
        defer { isLoading = false }
        do {
            try await client.restore()
            balance = try await client.loadBalance(currencyCode: configuration.currencyCode, forceRefresh: true)
            message = "Purchases restored."
        } catch {
            message = error.localizedDescription
        }
    }

    func importRecipe(_ id: String, incoming: IncomingRecipeStore) async -> ImportResult {
        guard spendingImportID == nil else { return .failed }
        guard let appUserID = client.appUserID,
              let operationID = incoming.spendOperationID(for: id) else {
            message = SpoonClientError.notConfigured.localizedDescription
            return .failed
        }
        spendingImportID = id
        defer { spendingImportID = nil }
        do {
            try await spendingClient.spendForImport(appUserID: appUserID, operationID: operationID)
            incoming.prepare(id)
            balance = try? await client.loadBalance(currencyCode: configuration.currencyCode, forceRefresh: true)
            message = nil
            return .imported
        } catch SpoonSpendingError.insufficientBalance {
            incoming.renewSpendOperation(for: id)
            balance = try? await client.loadBalance(currencyCode: configuration.currencyCode, forceRefresh: true)
            message = "You need \(configuration.importCost) Spoons to import this recipe."
            return .needsSpoons
        } catch {
            message = error.localizedDescription
            return .failed
        }
    }
}
