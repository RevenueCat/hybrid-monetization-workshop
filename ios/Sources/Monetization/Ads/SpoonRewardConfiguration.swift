import Foundation

struct SpoonRewardConfiguration {
    let dailyAdUnitID: String
    let importRescueAdUnitID: String
    let dailyPlacement: String
    let importRescuePlacement: String
    let dailyAmount: Int
    let importRescueAmount: Int
    let currencyCode: String
    let testDeviceIdentifiers: [String]

    static func bundled(_ bundle: Bundle = .main) -> SpoonRewardConfiguration? {
        func value(_ key: String) -> String? {
            guard let value = bundle.object(forInfoDictionaryKey: key) as? String else { return nil }
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty || trimmed.contains("$(") ? nil : trimmed
        }
        guard let dailyAdUnitID = value("AdMobDailyRewardedAdUnitIdentifier"),
              let importRescueAdUnitID = value("AdMobImportRescueRewardedAdUnitIdentifier"),
              let dailyPlacement = value("AdMobDailyRewardedPlacement"),
              let importRescuePlacement = value("AdMobImportRescueRewardedPlacement"),
              let dailyAmount = Int(value("SpoonDailyRewardAmount") ?? ""), dailyAmount > 0,
              let importRescueAmount = Int(value("SpoonImportRescueRewardAmount") ?? ""), importRescueAmount > 0,
              let currencyCode = value("RevenueCatSpoonCurrencyCode") else { return nil }
        let testDeviceIdentifiers = value("AdMobTestDeviceIdentifiers")?
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty } ?? []
        return .init(
            dailyAdUnitID: dailyAdUnitID,
            importRescueAdUnitID: importRescueAdUnitID,
            dailyPlacement: dailyPlacement,
            importRescuePlacement: importRescuePlacement,
            dailyAmount: dailyAmount,
            importRescueAmount: importRescueAmount,
            currencyCode: currencyCode,
            testDeviceIdentifiers: testDeviceIdentifiers
        )
    }
}
