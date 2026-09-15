import GoogleMobileAds
import OSLog
@_spi(Experimental) import RevenueCat
@_spi(Experimental) import RevenueCatAdMob
import SwiftUI

enum ThemeRewardAdState: Equatable {
    case unavailable
    case loading
    case ready
    case presenting
    case verifying
}

struct ThemeRewardAccessContext: Equatable {
    let phase: PlusAccessPhase
    let hasPremiumThemes: Bool
}

enum ThemeRewardAccessPolicy {
    static func isAvailable(
        for phase: PlusAccessPhase,
        hasPremiumThemes: Bool,
        disabledForTesting: Bool
    ) -> Bool {
        guard !disabledForTesting,
              !hasPremiumThemes,
              case .available(let hasPlus, _) = phase else { return false }
        return !hasPlus
    }
}

/// Owns the rewarded-ad lifecycle for temporary premium-theme access.
@MainActor
final class ThemeRewardStore: NSObject, ObservableObject {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "KitchenTable",
        category: "ThemeRewardStore"
    )

    @Published private(set) var state: ThemeRewardAdState = .unavailable
    @Published private(set) var message: String?

    private let configuration: AdConfiguration?
    private let isDisabledForTesting: Bool
    private var isAvailable = false
    private var didStart = false
    private var isLoading = false
    private var ad: RewardedAd?
    private var completion: (() -> Void)?
    private var verificationStarted = false
    private var retryTask: Task<Void, Never>?

    init(
        configuration: AdConfiguration? = .bundled(),
        arguments: [String] = ProcessInfo.processInfo.arguments
    ) {
        self.configuration = configuration
        isDisabledForTesting = arguments.contains("--disable-ads") ||
            (arguments.contains("--ui-testing") && !arguments.contains("--revenuecat-test-user"))
        super.init()
    }

    func updateAccess(phase: PlusAccessPhase, hasPremiumThemes: Bool) {
        let available = ThemeRewardAccessPolicy.isAvailable(
            for: phase,
            hasPremiumThemes: hasPremiumThemes,
            disabledForTesting: isDisabledForTesting
        )
        guard available != isAvailable else { return }
        isAvailable = available

        if available {
            startAndPreload()
        } else {
            retryTask?.cancel()
            ad = nil
            completion = nil
            verificationStarted = false
            state = .unavailable
            message = nil
        }
    }

    func present(completion: @escaping () -> Void) {
        guard isAvailable else { return }
        guard let ad, let presenter = ViewControllerLocator.topViewController else {
            message = "The ad isn’t ready yet. Please try again shortly."
            loadIfNeeded()
            return
        }

        self.ad = nil
        self.completion = completion
        verificationStarted = false
        message = nil
        state = .presenting
        ad.present(
            from: presenter,
            placement: configuration?.rewardedPlacement,
            rewardVerificationStarted: { [weak self] in
                self?.verificationStarted = true
                self?.state = .verifying
            },
            rewardVerificationCompleted: { [weak self] result in
                self?.finishVerification(result)
            }
        )
    }

    private func startAndPreload() {
        guard configuration != nil else { return }
        if !didStart {
            didStart = true
            MobileAds.shared.start(completionHandler: nil)
        }
        loadIfNeeded()
    }

    private func loadIfNeeded() {
        guard isAvailable,
              let configuration,
              ad == nil,
              !isLoading else { return }
        retryTask?.cancel()
        isLoading = true
        state = .loading
        RewardedAd.loadAndTrack(
            withAdUnitID: configuration.rewardedAdUnitID,
            request: Request(),
            placement: configuration.rewardedPlacement,
            fullScreenContentDelegate: self
        ) { [weak self] ad, error in
            guard let self else { return }
            self.isLoading = false
            guard self.isAvailable else { return }
            guard let ad else {
                let detail = error?.localizedDescription ?? "The SDK did not provide an error."
                Self.logger.error("Rewarded ad failed to load: \(detail, privacy: .public)")
                self.message = "The rewarded ad couldn’t load. \(detail)"
                self.retry()
                return
            }
            ad.enableRewardVerification()
            self.ad = ad
            self.state = .ready
            self.message = nil
        }
    }

    private func finishVerification(_ result: RewardVerificationResult) {
        let rewards = result.verifiedReward.map { [$0] + result.moreRewards } ?? []
        let grantedPremiumThemes = rewards.compactMap(\.entitlement).contains {
            $0.identifier == PlusAccessStore.premiumThemesEntitlementID
        }
        let completion = completion
        self.completion = nil
        if grantedPremiumThemes {
            state = .unavailable
        } else {
            message = "Checking your theme access…"
            state = .loading
            loadIfNeeded()
        }
        completion?()
    }

    private func retry() {
        state = .loading
        retryTask?.cancel()
        retryTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            self?.loadIfNeeded()
        }
    }
}

extension ThemeRewardStore: FullScreenContentDelegate {
    func adDidDismissFullScreenContent(_ ad: any FullScreenPresentingAd) {
        guard !verificationStarted else { return }
        completion = nil
        message = "Finish the ad to unlock every theme."
        retry()
    }

    func ad(
        _ ad: any FullScreenPresentingAd,
        didFailToPresentFullScreenContentWithError error: Error
    ) {
        completion = nil
        verificationStarted = false
        message = "The ad couldn’t be shown. Please try again."
        retry()
    }
}
