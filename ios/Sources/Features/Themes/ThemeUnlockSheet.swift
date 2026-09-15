import SwiftUI

struct ThemeUnlockSheet: View {
    @EnvironmentObject private var appearance: AppearanceStore
    @Environment(\.dismiss) private var dismiss
    let theme: AppTheme
    @ObservedObject var plus: PlusAccessStore
    @ObservedObject var themeRewards: ThemeRewardStore

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            header
            ThemePreview(theme: theme, isSelected: false)

            if let message = themeRewards.message {
                Text(message)
                    .themeFont(appearance.theme, style: .subheadline)
                    .foregroundStyle(Color(uiColor: appearance.theme.muted))
                    .accessibilityIdentifier("themes.reward.message")
            }

            Button(action: watchAd) {
                HStack(spacing: 10) {
                    if themeRewards.state == .loading || themeRewards.state == .verifying {
                        ProgressView().tint(Color(uiColor: appearance.theme.onAccent))
                    }
                    Text(rewardButtonTitle)
                }
            }
            .buttonStyle(KitchenButtonStyle(primary: true))
            .disabled(themeRewards.state != .ready)
            .accessibilityIdentifier("themes.reward.watch")

            Button("Get Kitchen Table Plus") {
                plus.choosePlusForRequestedTheme()
            }
            .buttonStyle(KitchenButtonStyle())
            .accessibilityIdentifier("themes.reward.upgrade")

            Text("Plus unlocks every theme permanently and removes ads.")
                .themeFont(appearance.theme, style: .footnote)
                .foregroundStyle(Color(uiColor: appearance.theme.muted))
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color(uiColor: appearance.theme.paper))
        .foregroundStyle(Color(uiColor: appearance.theme.ink))
        .presentationDetents([.large])
        .presentationDragIndicator(.hidden)
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Try every theme")
                    .themeTitleFont(appearance.theme, size: 30)
                Text("Watch one ad to use Studio, Editorial, Archive and Classic for 30 minutes.")
                    .themeFont(appearance.theme, style: .body)
                    .foregroundStyle(Color(uiColor: appearance.theme.muted))
            }
            Spacer(minLength: 12)
            Button { dismiss() } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(Color(uiColor: appearance.theme.muted))
            }
            .accessibilityLabel("Close")
            .accessibilityIdentifier("themes.unlock.close")
        }
    }

    private func watchAd() {
        themeRewards.present {
            Task { await plus.completeVerifiedThemeReward() }
        }
    }

    private var rewardButtonTitle: String {
        switch themeRewards.state {
        case .ready: "Watch an ad"
        case .presenting: "Starting ad…"
        case .verifying: "Unlocking themes…"
        case .loading: "Loading ad…"
        case .unavailable: "Ad unavailable"
        }
    }
}
