import SwiftUI

struct ImportShortfallView: View {
    @EnvironmentObject private var appearance: AppearanceStore
    @EnvironmentObject private var spoons: SpoonStore
    @EnvironmentObject private var rewards: SpoonRewardStore
    @Environment(\.dismiss) private var dismiss
    let recipeTitle: String
    let retryImport: () async -> SpoonStore.ImportResult
    let openShop: () -> Void
    @State private var isRetrying = false

    var body: some View {
        LibraryPage(title: "Get Spoons") {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("KEEP IMPORTING")
                        .themeFont(appearance.theme, style: .caption1, emphasized: true)
                        .tracking(1.2)
                        .foregroundStyle(Color(uiColor: appearance.theme.muted))
                    Text(recipeTitle).themeTitleFont(appearance.theme, size: 28)
                    Text("This import costs \(spoons.configuration.importCost) Spoons. Your balance is \(spoons.balanceLabel).")
                        .themeFont(appearance.theme, style: .subheadline)
                        .foregroundStyle(Color(uiColor: appearance.theme.muted))
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("Watch one rewarded ad to receive \(rewards.importRescueAmount) Spoons. RevenueCat verifies the reward before the import continues.")
                        .themeFont(appearance.theme, style: .body)
                    Button(action: watchAndRetry) {
                        if rewards.importRescuePhase == .presenting || rewards.importRescuePhase == .verifying || isRetrying {
                            ProgressView().controlSize(.small).frame(maxWidth: .infinity)
                        } else {
                            Text(rewardButtonTitle)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(KitchenButtonStyle(primary: true))
                    .disabled(!rewards.canRescueImport || isRetrying)
                    .accessibilityIdentifier("import.reward.watch")
                }
                .padding(18)
                .background(Color(uiColor: appearance.theme.surface), in: RoundedRectangle(cornerRadius: appearance.theme.cornerRadius))
                .overlay(RoundedRectangle(cornerRadius: appearance.theme.cornerRadius)
                    .stroke(Color(uiColor: appearance.theme.line), lineWidth: 1))

                Button("Get Spoons another way", action: openShop)
                    .buttonStyle(KitchenButtonStyle())
                    .frame(maxWidth: .infinity)
                    .accessibilityIdentifier("import.reward.shop")

                if let message = rewards.message {
                    Text(message)
                        .themeFont(appearance.theme, style: .caption1)
                        .foregroundStyle(Color(uiColor: appearance.theme.muted))
                        .accessibilityIdentifier("import.reward.message")
                }
            }
        }
    }

    private func watchAndRetry() {
        rewards.rescueImport {
            isRetrying = true
            Task {
                let result = await retryImport()
                isRetrying = false
                if case .imported = result { dismiss() }
            }
        }
    }

    private var rewardButtonTitle: String {
        switch rewards.importRescuePhase {
        case .ready: "Watch ad · +\(rewards.importRescueAmount)"
        case .loading, .presenting, .verifying: "Loading ad…"
        case .unavailable: "Reward unavailable"
        }
    }
}
