import Foundation

struct DailyRewardStatus: Equatable {
    let claimable: Bool
    let nextClaimAt: Date
}

enum DailyRewardClientError: LocalizedError {
    case unavailable

    var errorDescription: String? {
        "Daily Spoons are unavailable. Start the local workshop service and try again."
    }
}

@MainActor
protocol DailyRewardClient {
    func status(appUserID: String) async throws -> DailyRewardStatus
    func recordClaim(appUserID: String) async throws -> DailyRewardStatus
}

@MainActor
struct LocalDailyRewardClient: DailyRewardClient {
    let serviceURL: URL

    func status(appUserID: String) async throws -> DailyRewardStatus {
        try await request(path: "rewards/daily/status", appUserID: appUserID)
    }

    func recordClaim(appUserID: String) async throws -> DailyRewardStatus {
        try await request(path: "rewards/daily/claim", appUserID: appUserID)
    }

    private func request(path: String, appUserID: String) async throws -> DailyRewardStatus {
        var request = URLRequest(url: serviceURL.appending(path: path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(Body(appUserID: appUserID))
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw DailyRewardClientError.unavailable
        }
        let value = try JSONDecoder.rewardDecoder.decode(Response.self, from: data)
        return .init(claimable: value.claimable, nextClaimAt: value.nextClaimAt)
    }

    private struct Body: Encodable {
        let appUserID: String
        enum CodingKeys: String, CodingKey { case appUserID = "app_user_id" }
    }

    private struct Response: Decodable {
        let claimable: Bool
        let nextClaimAt: Date
        enum CodingKeys: String, CodingKey { case claimable; case nextClaimAt = "next_claim_at" }
    }
}

private extension JSONDecoder {
    static var rewardDecoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
