import Foundation

struct SpoonConfiguration {
    let currencyCode: String
    let offeringIdentifier: String
    let importCost: Int
    let serviceURL: URL

    static func current(bundle: Bundle = .main) -> Self {
        func string(_ key: String, fallback: String) -> String {
            let value = (bundle.object(forInfoDictionaryKey: key) as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return value.isEmpty || value.contains("$(") ? fallback : value
        }
        let configuredCost = Int(string("SpoonImportCost", fallback: "25")) ?? 25
        return .init(
            currencyCode: string("RevenueCatSpoonCurrencyCode", fallback: "SPOON"),
            offeringIdentifier: string("RevenueCatSpoonsOfferingIdentifier", fallback: "spoons"),
            importCost: max(1, configuredCost),
            serviceURL: URL(string: string("SpoonServiceURL", fallback: "http://127.0.0.1:8787"))!
        )
    }
}
