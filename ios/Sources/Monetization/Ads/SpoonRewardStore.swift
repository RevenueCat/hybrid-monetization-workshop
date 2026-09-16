import GoogleMobileAds
import OSLog
@_spi(Experimental) import RevenueCat
@_spi(Experimental) import RevenueCatAdMob
import SwiftUI

enum SpoonRewardAdPhase: Equatable {
    case unavailable
    case loading
    case ready
    case presenting
    case verifying
}

enum DailyRewardEligibility: Equatable {
    case checking
    case available
    case claimed(nextClaimAt: Date)
    case unavailable
}

private enum SpoonRewardKind: Equatable {
    case daily
    case importRescue
}

/// Owns only rewarded ads. There are deliberately no banner or interstitial paths in Scenario D.
@MainActor
final class SpoonRewardStore: NSObject, ObservableObject {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "KitchenTable",
        category: "SpoonRewardStore"
    )

    @Published private(set) var dailyPhase: SpoonRewardAdPhase = .unavailable
    @Published private(set) var importRescuePhase: SpoonRewardAdPhase = .unavailable
    @Published private(set) var dailyEligibility: DailyRewardEligibility = .checking
    @Published private(set) var message: String?

    private let configuration: SpoonRewardConfiguration?
    private let dailyClient: any DailyRewardClient
    private let spoons: SpoonStore
    private let isPreview: Bool
    private var didStart = false
    private var dailyAd: RewardedAd?
    private var importRescueAd: RewardedAd?
    private var activeKind: SpoonRewardKind?
    private var verificationStarted = false
    private var rescueCompletion: (() -> Void)?
    private var dailyRetry: Task<Void, Never>?
    private var rescueRetry: Task<Void, Never>?

    init(
        spoons: SpoonStore,
        configuration: SpoonRewardConfiguration? = .bundled(),
        dailyClient: any DailyRewardClient,
        arguments: [String] = ProcessInfo.processInfo.arguments
    ) {
        self.spoons = spoons
        self.configuration = configuration
        self.dailyClient = dailyClient
        isPreview = arguments.contains("--ui-testing") && !arguments.contains("--revenuecat-test-user")
        super.init()
    }

    static func live(
        spoons: SpoonStore,
        arguments: [String] = ProcessInfo.processInfo.arguments
    ) -> SpoonRewardStore {
        .init(
            spoons: spoons,
            dailyClient: LocalDailyRewardClient(serviceURL: spoons.configuration.serviceURL),
            arguments: arguments
        )
    }

    var dailyAmount: Int { configuration?.dailyAmount ?? 10 }
    var importRescueAmount: Int { configuration?.importRescueAmount ?? spoons.configuration.importCost }
    var canClaimDaily: Bool { dailyEligibility == .available && dailyPhase == .ready }
    var canRescueImport: Bool { importRescuePhase == .ready }

    func start() async {
        guard !didStart else {
            await refreshDailyEligibility()
            return
        }
        didStart = true
        if isPreview {
            dailyEligibility = .available
            dailyPhase = .ready
            importRescuePhase = .ready
            return
        }
        await refreshDailyEligibility()
        guard let configuration else {
            dailyPhase = .unavailable
            importRescuePhase = .unavailable
            message = "Add both SSV-enabled rewarded ad units to the local workshop configuration."
            return
        }
        #if DEBUG
        if !configuration.testDeviceIdentifiers.isEmpty {
            MobileAds.shared.requestConfiguration.testDeviceIdentifiers = configuration.testDeviceIdentifiers
        }
        #endif
        _ = await MobileAds.shared.start()
        load(.daily)
        load(.importRescue)
    }

    func refreshDailyEligibility() async {
        guard let appUserID = spoons.appUserID else {
            dailyEligibility = .unavailable
            return
        }
        if isPreview {
            if case .claimed = dailyEligibility { return }
            dailyEligibility = .available
            return
        }
        dailyEligibility = .checking
        do {
            let status = try await dailyClient.status(appUserID: appUserID)
            dailyEligibility = status.claimable ? .available : .claimed(nextClaimAt: status.nextClaimAt)
        } catch {
            dailyEligibility = .unavailable
            message = error.localizedDescription
        }
    }

    func claimDaily() {
        guard canClaimDaily else { return }
        present(.daily)
    }

    func rescueImport(completion: @escaping () -> Void) {
        guard canRescueImport else { return }
        rescueCompletion = completion
        present(.importRescue)
    }

    private func present(_ kind: SpoonRewardKind) {
        if isPreview {
            finishPreview(kind)
            return
        }
        let ad = kind == .daily ? dailyAd : importRescueAd
        guard let ad, let presenter = ViewControllerLocator.topViewController else {
            message = "The ad isn’t ready yet. Please try again shortly."
            load(kind)
            return
        }
        if kind == .daily { dailyAd = nil; dailyPhase = .presenting }
        else { importRescueAd = nil; importRescuePhase = .presenting }
        activeKind = kind
        verificationStarted = false
        message = nil
        ad.present(
            from: presenter,
            placement: placement(for: kind),
            rewardVerificationStarted: { [weak self] in
                guard let self else { return }
                self.verificationStarted = true
                self.setPhase(.verifying, for: kind)
            },
            rewardVerificationCompleted: { [weak self] result in
                self?.finishVerification(result, kind: kind)
            }
        )
    }

    private func load(_ kind: SpoonRewardKind) {
        guard let configuration, activeKind != kind else { return }
        if kind == .daily {
            guard dailyAd == nil, dailyPhase != .loading else { return }
            dailyRetry?.cancel()
        } else {
            guard importRescueAd == nil, importRescuePhase != .loading else { return }
            rescueRetry?.cancel()
        }
        setPhase(.loading, for: kind)
        RewardedAd.loadAndTrack(
            withAdUnitID: adUnitID(for: kind, configuration: configuration),
            request: Request(),
            placement: placement(for: kind),
            fullScreenContentDelegate: self
        ) { [weak self] ad, error in
            guard let self else { return }
            guard let ad else {
                let detail = error?.localizedDescription ?? "The SDK did not provide an error."
                Self.logger.error("Rewarded ad failed to load: \(detail, privacy: .public)")
                self.message = "The rewarded ad couldn’t load. Please try again shortly."
                self.retry(kind)
                return
            }
            ad.enableRewardVerification()
            if kind == .daily { self.dailyAd = ad }
            else { self.importRescueAd = ad }
            self.setPhase(.ready, for: kind)
        }
    }

    private func finishVerification(_ result: RewardVerificationResult, kind: SpoonRewardKind) {
        let rewards = result.verifiedReward.map { [$0] + result.moreRewards } ?? []
        guard let reward = rewards.compactMap(\.virtualCurrency).first(where: {
            $0.code == configuration?.currencyCode && $0.amount > 0
        }) else {
            message = "RevenueCat couldn’t verify a Spoons reward. No local credit was added."
            finish(kind, succeeded: false)
            return
        }
        Task {
            await spoons.refreshBalance(force: true)
            if kind == .daily, let appUserID = spoons.appUserID {
                do {
                    let status = try await dailyClient.recordClaim(appUserID: appUserID)
                    dailyEligibility = .claimed(nextClaimAt: status.nextClaimAt)
                } catch {
                    dailyEligibility = .unavailable
                    message = "The Spoons were granted, but daily eligibility couldn’t be recorded."
                }
            }
            if message == nil { message = "+\(reward.amount) Spoons added." }
            finish(kind, succeeded: true)
        }
    }

    private func finishPreview(_ kind: SpoonRewardKind) {
        let amount = kind == .daily ? dailyAmount : importRescueAmount
        spoons.applyPreviewReward(amount)
        if kind == .daily {
            dailyEligibility = .claimed(nextClaimAt: Calendar.current.date(byAdding: .day, value: 1, to: Date())!)
            message = "+\(amount) Spoons added."
        }
        let completion = rescueCompletion
        rescueCompletion = nil
        if kind == .importRescue { completion?() }
    }

    private func finish(_ kind: SpoonRewardKind, succeeded: Bool) {
        let completion = rescueCompletion
        rescueCompletion = nil
        activeKind = nil
        verificationStarted = false
        setPhase(.unavailable, for: kind)
        load(kind)
        if succeeded, kind == .importRescue { completion?() }
    }

    private func retry(_ kind: SpoonRewardKind) {
        setPhase(.loading, for: kind)
        let task = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            self?.setPhase(.unavailable, for: kind)
            self?.load(kind)
        }
        if kind == .daily { dailyRetry = task } else { rescueRetry = task }
    }

    private func setPhase(_ phase: SpoonRewardAdPhase, for kind: SpoonRewardKind) {
        if kind == .daily { dailyPhase = phase } else { importRescuePhase = phase }
    }

    private func placement(for kind: SpoonRewardKind) -> String? {
        kind == .daily ? configuration?.dailyPlacement : configuration?.importRescuePlacement
    }

    private func adUnitID(for kind: SpoonRewardKind, configuration: SpoonRewardConfiguration) -> String {
        kind == .daily ? configuration.dailyAdUnitID : configuration.importRescueAdUnitID
    }
}

extension SpoonRewardStore: FullScreenContentDelegate {
    func adDidDismissFullScreenContent(_ ad: any FullScreenPresentingAd) {
        guard let kind = activeKind, !verificationStarted else { return }
        message = "Finish the ad to receive Spoons."
        finish(kind, succeeded: false)
    }

    func ad(
        _ ad: any FullScreenPresentingAd,
        didFailToPresentFullScreenContentWithError error: Error
    ) {
        guard let kind = activeKind else { return }
        message = "The ad couldn’t be shown. Please try again."
        finish(kind, succeeded: false)
    }
}
