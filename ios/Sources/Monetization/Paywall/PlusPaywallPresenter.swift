import RevenueCatUI
import SwiftUI

struct PlusPaywallPresenter: ViewModifier {
    @ObservedObject var plus: PlusAccessStore

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $plus.isPaywallPresented) {
                if let offering = plus.offering {
                    PaywallView(offering: offering, displayCloseButton: true)
                        .onPurchaseCompleted { plus.complete(with: $0) }
                        .onRestoreCompleted { plus.complete(with: $0) }
                        .onRequestedDismissal { plus.dismissPaywall() }
                }
            }
            .alert("Kitchen Table Plus", isPresented: Binding(
                get: { plus.alertMessage != nil },
                set: { if !$0 { plus.alertMessage = nil } }
            )) {
                Button("OK") { plus.alertMessage = nil }
            } message: {
                Text(plus.alertMessage ?? "")
            }
    }
}

extension View {
    func plusPaywallPresenter(_ plus: PlusAccessStore) -> some View {
        modifier(PlusPaywallPresenter(plus: plus))
    }
}
