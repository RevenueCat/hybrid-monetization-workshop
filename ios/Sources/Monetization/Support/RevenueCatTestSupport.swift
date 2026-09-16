import Foundation

enum RevenueCatTestSupport {
    static func appUserID(apiKey: String, arguments: [String]) -> String? {
        guard arguments.contains("--ui-testing"), apiKey.hasPrefix("test_") else { return nil }
        guard let flag = arguments.firstIndex(of: "--revenuecat-test-user"),
              arguments.indices.contains(flag + 1) else { return nil }
        let value = arguments[flag + 1].trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
