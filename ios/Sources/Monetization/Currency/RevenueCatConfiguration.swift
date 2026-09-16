import Foundation
import RevenueCat

enum RevenueCatConfiguration {
    static func configureIfAvailable(
        bundle: Bundle = .main,
        arguments: [String] = ProcessInfo.processInfo.arguments
    ) {
        guard !Purchases.isConfigured else { return }
        let apiKey = (bundle.object(forInfoDictionaryKey: "RevenueCatAPIKey") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !apiKey.isEmpty, !apiKey.contains("$(") else { return }

        #if DEBUG
        Purchases.logLevel = .debug
        #endif
        Purchases.configure(
            withAPIKey: apiKey,
            appUserID: RevenueCatTestSupport.appUserID(apiKey: apiKey, arguments: arguments)
        )
    }
}
