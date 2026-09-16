import SwiftUI

struct SpoonsView: View {
    @EnvironmentObject private var appearance: AppearanceStore
    @EnvironmentObject private var spoons: SpoonStore
    @EnvironmentObject private var rewards: SpoonRewardStore

    var body: some View {
        LibraryPage(title: "Spoons") {
            VStack(alignment: .leading, spacing: 24) {
                balanceCard
                dailyRewardCard

                if let recurring = spoons.products.first(where: { $0.kind == .monthly }) {
                    productSection(title: "EVERY MONTH", products: [recurring])
                }
                let packs = spoons.products.filter { $0.kind == .oneTime }
                if !packs.isEmpty { productSection(title: "ONE-TIME PACKS", products: packs) }

                if spoons.isLoading && spoons.products.isEmpty {
                    ProgressView("Loading Spoons…")
                        .frame(maxWidth: .infinity, minHeight: 120)
                        .accessibilityIdentifier("spoons.loading")
                }

                if let message = spoons.message {
                    Text(message)
                        .themeFont(appearance.theme, style: .subheadline)
                        .foregroundStyle(Color(uiColor: appearance.theme.muted))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityIdentifier("spoons.message")
                }
                if let message = rewards.message {
                    Text(message)
                        .themeFont(appearance.theme, style: .subheadline)
                        .foregroundStyle(Color(uiColor: appearance.theme.muted))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityIdentifier("spoons.reward.message")
                }

                Button("Restore purchases") { Task { await spoons.restore() } }
                    .buttonStyle(.plain)
                    .themeFont(appearance.theme, style: .subheadline, emphasized: true)
                    .frame(minHeight: 44)
                    .disabled(spoons.isLoading || spoons.purchasingProductID != nil)
                    .accessibilityIdentifier("spoons.restore")

                Text("Spoons are spent on recipe imports. Purchases and balances are managed by RevenueCat.")
                    .themeFont(appearance.theme, style: .caption1)
                    .foregroundStyle(Color(uiColor: appearance.theme.muted))
            }
        }
        .task {
            await spoons.refresh()
            await rewards.refreshDailyEligibility()
        }
        .refreshable {
            await spoons.refresh(force: true)
            await rewards.refreshDailyEligibility()
        }
    }

    private var dailyRewardCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: "play.rectangle.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(Color(uiColor: appearance.theme.muted))
                    .frame(width: 32)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Daily Spoons").themeFont(appearance.theme, style: .headline)
                    Text(dailyRewardDetail)
                        .themeFont(appearance.theme, style: .subheadline)
                        .foregroundStyle(Color(uiColor: appearance.theme.muted))
                }
                Spacer(minLength: 8)
            }
            Button(action: rewards.claimDaily) {
                if rewards.dailyPhase == .presenting || rewards.dailyPhase == .verifying {
                    ProgressView().controlSize(.small).frame(maxWidth: .infinity)
                } else {
                    Text(dailyRewardButtonTitle).frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(KitchenButtonStyle(primary: rewards.canClaimDaily))
            .disabled(!rewards.canClaimDaily)
            .accessibilityIdentifier("spoons.daily.claim")
        }
        .padding(16)
        .background(Color(uiColor: appearance.theme.surface), in: RoundedRectangle(cornerRadius: appearance.theme.cornerRadius))
        .overlay(RoundedRectangle(cornerRadius: appearance.theme.cornerRadius)
            .stroke(Color(uiColor: appearance.theme.line), lineWidth: 1))
    }

    private var dailyRewardDetail: String {
        switch rewards.dailyEligibility {
        case .claimed: "Claimed today. Come back tomorrow."
        case .unavailable: "Start the workshop service to check today’s claim."
        default: "Watch one rewarded ad for \(rewards.dailyAmount) Spoons."
        }
    }

    private var dailyRewardButtonTitle: String {
        switch rewards.dailyEligibility {
        case .checking: "Checking…"
        case .claimed: "Claimed"
        case .unavailable: "Unavailable"
        case .available:
            switch rewards.dailyPhase {
            case .ready: "Watch ad · +\(rewards.dailyAmount)"
            case .loading, .presenting, .verifying: "Loading ad…"
            case .unavailable: "Unavailable"
            }
        }
    }

    private var balanceCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("YOUR BALANCE")
                .themeFont(appearance.theme, style: .caption1, emphasized: true)
                .tracking(1.2)
                .foregroundStyle(Color(uiColor: appearance.theme.muted))
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(spoons.balanceLabel)
                    .themeTitleFont(appearance.theme, size: 40)
                    .contentTransition(.numericText())
                Text("Spoons")
                    .themeFont(appearance.theme, style: .headline)
                    .foregroundStyle(Color(uiColor: appearance.theme.muted))
            }
            Text("Each recipe import costs \(spoons.configuration.importCost) Spoons.")
                .themeFont(appearance.theme, style: .subheadline)
                .foregroundStyle(Color(uiColor: appearance.theme.muted))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(Color(uiColor: appearance.theme.surface), in: RoundedRectangle(cornerRadius: appearance.theme.cornerRadius))
        .overlay(RoundedRectangle(cornerRadius: appearance.theme.cornerRadius)
            .stroke(Color(uiColor: appearance.theme.line), lineWidth: 1))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("spoons.balance")
    }

    private func productSection(title: String, products: [SpoonProduct]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .themeFont(appearance.theme, style: .caption1, emphasized: true)
                .tracking(1.2)
                .foregroundStyle(Color(uiColor: appearance.theme.muted))
                .accessibilityAddTraits(.isHeader)
            ForEach(products) { product in
                HStack(alignment: .center, spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(product.title).themeFont(appearance.theme, style: .headline)
                        Text(product.detail)
                            .themeFont(appearance.theme, style: .subheadline)
                            .foregroundStyle(Color(uiColor: appearance.theme.muted))
                    }
                    Spacer(minLength: 8)
                    Button {
                        Task { await spoons.purchase(product) }
                    } label: {
                        if spoons.purchasingProductID == product.id {
                            ProgressView().controlSize(.small).frame(minWidth: 58)
                        } else {
                            Text(product.localizedPrice).frame(minWidth: 58)
                        }
                    }
                    .buttonStyle(KitchenButtonStyle(primary: product.kind == .monthly))
                    .fixedSize(horizontal: true, vertical: false)
                    .disabled(spoons.purchasingProductID != nil || spoons.isLoading)
                    .accessibilityLabel("Buy \(product.title) for \(product.localizedPrice)")
                    .accessibilityIdentifier("spoons.buy.\(product.id)")
                }
                .padding(16)
                .background(Color(uiColor: appearance.theme.surface), in: RoundedRectangle(cornerRadius: appearance.theme.cornerRadius))
                .overlay(RoundedRectangle(cornerRadius: appearance.theme.cornerRadius)
                    .stroke(Color(uiColor: appearance.theme.line), lineWidth: 1))
            }
        }
    }
}
