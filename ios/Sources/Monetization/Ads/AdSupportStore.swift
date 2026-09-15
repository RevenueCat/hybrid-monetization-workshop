import GoogleMobileAds
@_spi(Experimental) import RevenueCatAdMob
import SwiftUI

@MainActor
final class AdSupportStore: NSObject, ObservableObject {
    @Published private(set) var isInterstitialReady = false
    @Published private(set) var adsEnabled = false

    private let configuration: AdConfiguration?
    private let isDisabledForTesting: Bool
    private var didStart = false
    private var isLoadingInterstitial = false
    private var interstitialAd: InterstitialAd?
    private var pendingAction: (() -> Void)?
    private var interstitialRetry: Task<Void, Never>?

    init(
        configuration: AdConfiguration? = .bundled(),
        arguments: [String] = ProcessInfo.processInfo.arguments
    ) {
        self.configuration = configuration
        isDisabledForTesting = arguments.contains("--disable-ads") ||
            (arguments.contains("--ui-testing") && !arguments.contains("--revenuecat-test-user"))
        super.init()
    }

    func updateAccess(_ phase: PlusAccessPhase) {
        let enabled = AdAccessPolicy.adsEnabled(for: phase, disabledForTesting: isDisabledForTesting)
        guard enabled != adsEnabled else { return }
        adsEnabled = enabled

        if enabled {
            startAndPreload()
        } else {
            interstitialRetry?.cancel()
            interstitialAd = nil
            isInterstitialReady = false
            finishPendingAction()
        }
    }

    func performAction(_ action: @escaping () -> Void) {
        guard adsEnabled else {
            action()
            return
        }
        guard let ad = interstitialAd,
              let presenter = ViewControllerLocator.topViewController else {
            action()
            loadInterstitialIfNeeded()
            return
        }

        interstitialAd = nil
        isInterstitialReady = false
        pendingAction = action
        ad.present(from: presenter)
    }

    private func startAndPreload() {
        guard let configuration else { return }
        if !didStart {
            didStart = true
            #if DEBUG
            if !configuration.testDeviceIdentifiers.isEmpty {
                MobileAds.shared.requestConfiguration.testDeviceIdentifiers = configuration.testDeviceIdentifiers
            }
            #endif
            MobileAds.shared.start(completionHandler: nil)
        }
        loadInterstitialIfNeeded()
    }

    private func loadInterstitialIfNeeded() {
        guard adsEnabled,
              let configuration,
              interstitialAd == nil,
              !isLoadingInterstitial else { return }
        interstitialRetry?.cancel()
        isLoadingInterstitial = true
        InterstitialAd.loadAndTrack(
            withAdUnitID: configuration.interstitialAdUnitID,
            request: Request(),
            placement: configuration.interstitialPlacement,
            fullScreenContentDelegate: self
        ) { [weak self] ad, _ in
            guard let self else { return }
            self.isLoadingInterstitial = false
            guard self.adsEnabled else { return }
            self.interstitialAd = ad
            self.isInterstitialReady = ad != nil
            if ad == nil { self.retryInterstitial() }
        }
    }

    private func finishPendingAction() {
        let action = pendingAction
        pendingAction = nil
        action?()
    }

    private func finishInterstitialAction() {
        finishPendingAction()
        loadInterstitialIfNeeded()
    }

    private func retryInterstitial() {
        interstitialRetry?.cancel()
        interstitialRetry = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            self?.loadInterstitialIfNeeded()
        }
    }
}

extension AdSupportStore: FullScreenContentDelegate {
    func adDidDismissFullScreenContent(_ ad: any FullScreenPresentingAd) {
        finishInterstitialAction()
    }

    func ad(
        _ ad: any FullScreenPresentingAd,
        didFailToPresentFullScreenContentWithError error: Error
    ) {
        finishInterstitialAction()
    }
}
