import Foundation

struct AdConfiguration {
    let interstitialAdUnitID: String
    let bannerAdUnitID: String
    let interstitialPlacement: String
    let bannerPlacement: String
    let testDeviceIdentifiers: [String]

    static func bundled(_ bundle: Bundle = .main) -> AdConfiguration? {
        func value(_ key: String) -> String? {
            guard let value = bundle.object(forInfoDictionaryKey: key) as? String else { return nil }
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty || trimmed.contains("$(") ? nil : trimmed
        }

        guard let interstitialAdUnitID = value("AdMobInterstitialAdUnitIdentifier"),
              let bannerAdUnitID = value("AdMobBannerAdUnitIdentifier"),
              let interstitialPlacement = value("AdMobInterstitialPlacement"),
              let bannerPlacement = value("AdMobBannerPlacement") else { return nil }
        let testDeviceIdentifiers = value("AdMobTestDeviceIdentifiers")?
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty } ?? []
        return AdConfiguration(
            interstitialAdUnitID: interstitialAdUnitID,
            bannerAdUnitID: bannerAdUnitID,
            interstitialPlacement: interstitialPlacement,
            bannerPlacement: bannerPlacement,
            testDeviceIdentifiers: testDeviceIdentifiers
        )
    }
}

enum AdAccessPolicy {
    static func adsEnabled(for phase: PlusAccessPhase, disabledForTesting: Bool) -> Bool {
        guard !disabledForTesting,
              case .available(let hasPlus, _) = phase else { return false }
        return !hasPlus
    }
}
