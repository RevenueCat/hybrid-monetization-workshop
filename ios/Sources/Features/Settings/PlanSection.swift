import RevenueCatUI
import SwiftUI

struct PlanSection: View {
    @EnvironmentObject private var appearance: AppearanceStore
    @EnvironmentObject private var plus: PlusAccessStore
    @State private var showingCustomerCenter = false

    var body: some View {
        SettingsSection(title: "Plan") {
            VStack(alignment: .leading, spacing: 12) {
                planSummary
                planActions
            }
        }
        .sheet(isPresented: $showingCustomerCenter) {
            CustomerCenterView()
                .onCustomerCenterRestoreCompleted { plus.refresh(with: $0) }
                .onCustomerCenterRestoreFailed { _ in plus.reportCustomerCenterError() }
        }
    }

    @ViewBuilder
    private var planSummary: some View {
        switch plus.phase {
        case .loading:
            HStack(spacing: 10) {
                ProgressView().controlSize(.small)
                Text("Checking your plan…").themeFont(appearance.theme, style: .body)
            }
            .accessibilityIdentifier("settings.plan.loading")

        case .available(_, let plan):
            if let plan {
                Text(plan.billingPeriod.rawValue)
                    .themeFont(appearance.theme, style: .headline)
                    .accessibilityIdentifier("settings.plan.name")
                if let expirationDate = plan.expirationDate {
                    Text(plan.willRenew
                         ? "Renews \(expirationDate.formatted(date: .abbreviated, time: .omitted))"
                         : "Access until \(expirationDate.formatted(date: .abbreviated, time: .omitted))")
                        .themeFont(appearance.theme, style: .subheadline)
                        .foregroundStyle(Color(uiColor: appearance.theme.muted))
                        .accessibilityIdentifier("settings.plan.detail")
                }
            } else {
                freePlanSummary
            }

        case .unavailable:
            Text("Free")
                .themeFont(appearance.theme, style: .headline)
                .accessibilityIdentifier("settings.plan.name")
            Text("Subscriptions aren’t available in this build.")
                .themeFont(appearance.theme, style: .subheadline)
                .foregroundStyle(Color(uiColor: appearance.theme.muted))
                .accessibilityIdentifier("settings.plan.detail")
        }
    }

    private var freePlanSummary: some View {
        Group {
            Text("Free")
                .themeFont(appearance.theme, style: .headline)
                .accessibilityIdentifier("settings.plan.name")
            Text("Browse recipes and use the Original theme.")
                .themeFont(appearance.theme, style: .subheadline)
                .foregroundStyle(Color(uiColor: appearance.theme.muted))
                .accessibilityIdentifier("settings.plan.detail")
        }
    }

    private var planActions: some View {
        AdaptiveActionRow {
            if plus.plan != nil {
                Button("Manage subscription") { showingCustomerCenter = true }
                    .buttonStyle(KitchenButtonStyle(primary: true))
                    .accessibilityIdentifier("settings.plan.manage")
            } else {
                Button("Upgrade to Plus") { plus.presentPaywall() }
                    .buttonStyle(KitchenButtonStyle(primary: true))
                    .accessibilityIdentifier("settings.plan.upgrade")
            }
            Button {
                Task { await plus.restorePurchases() }
            } label: {
                if plus.isRestoring {
                    ProgressView().accessibilityLabel("Restoring purchases")
                } else {
                    Text("Restore purchases")
                }
            }
            .buttonStyle(KitchenButtonStyle())
            .disabled(plus.isRestoring)
            .accessibilityIdentifier("settings.plan.restore")
        }
    }
}
