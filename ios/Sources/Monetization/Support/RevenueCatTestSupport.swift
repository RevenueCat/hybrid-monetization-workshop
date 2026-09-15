import Foundation

/// Optional identity injection for real Test Store integration tests. Does not grant access.
enum RevenueCatTestSupport {
    static func appUserID(apiKey: String, arguments: [String] = ProcessInfo.processInfo.arguments) -> String? {
        #if DEBUG
        guard apiKey.hasPrefix("test_"), arguments.contains("--ui-testing"),
              let index = arguments.firstIndex(of: "--revenuecat-test-user"),
              arguments.indices.contains(index + 1) else { return nil }
        let customer = arguments[index + 1].trimmingCharacters(in: .whitespacesAndNewlines)
        guard !customer.isEmpty, !customer.hasPrefix("--") else { return nil }
        return customer
        #else
        return nil
        #endif
    }
}
