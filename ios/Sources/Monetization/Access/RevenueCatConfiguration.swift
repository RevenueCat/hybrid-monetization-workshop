import Foundation
import RevenueCat

enum RevenueCatConfiguration {
    static func configureIfAvailable(
        bundle: Bundle = .main,
        arguments: [String] = ProcessInfo.processInfo.arguments
    ) {
        let apiKey = bundle.object(forInfoDictionaryKey: "RevenueCatAPIKey") as? String ?? ""
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
