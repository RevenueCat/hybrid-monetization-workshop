import Foundation

enum SpoonSpendingError: LocalizedError, Equatable {
    case insufficientBalance(required: Int)
    case serviceUnavailable
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .insufficientBalance(let required): "You need \(required) Spoons to import this recipe."
        case .serviceUnavailable: "The Spoons service is unavailable. Keep this import and try again."
        case .invalidResponse: "The Spoons service returned an unexpected response."
        }
    }
}

protocol SpoonSpendingClient: AnyObject {
    func spendForImport(appUserID: String, operationID: String) async throws
}

final class LocalSpoonSpendingClient: SpoonSpendingClient {
    private let endpoint: URL
    private let session: URLSession

    init(serviceURL: URL, session: URLSession = .shared) {
        endpoint = serviceURL.appendingPathComponent("imports/spend")
        self.session = session
    }

    func spendForImport(appUserID: String, operationID: String) async throws {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(RequestBody(appUserID: appUserID, operationID: operationID))

        let data: Data
        let response: URLResponse
        do { (data, response) = try await session.data(for: request) }
        catch { throw SpoonSpendingError.serviceUnavailable }
        guard let http = response as? HTTPURLResponse else { throw SpoonSpendingError.invalidResponse }
        switch http.statusCode {
        case 200:
            return
        case 422:
            let body = try? JSONDecoder().decode(ErrorBody.self, from: data)
            throw SpoonSpendingError.insufficientBalance(required: body?.required ?? 25)
        case 500...599:
            throw SpoonSpendingError.serviceUnavailable
        default:
            throw SpoonSpendingError.invalidResponse
        }
    }

    private struct RequestBody: Encodable {
        let appUserID: String
        let operationID: String
        enum CodingKeys: String, CodingKey { case appUserID = "app_user_id", operationID = "operation_id" }
    }
    private struct ErrorBody: Decodable { let required: Int? }
}

@MainActor
final class PreviewSpoonSpendingClient: SpoonSpendingClient {
    private let client: PreviewSpoonClient
    private let importCost: Int
    init(client: PreviewSpoonClient, importCost: Int) {
        self.client = client
        self.importCost = importCost
    }
    func spendForImport(appUserID: String, operationID: String) async throws {
        guard client.balance >= importCost else {
            throw SpoonSpendingError.insufficientBalance(required: importCost)
        }
        client.spend(importCost)
    }
}
