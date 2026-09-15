import SwiftUI

struct ThemeAccessCountdown: View {
    @EnvironmentObject private var appearance: AppearanceStore
    let expiration: Date
    let prefix: String
    let identifier: String

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            Text("\(prefix) · \(remaining(from: context.date))")
                .themeFont(appearance.theme, style: .subheadline, emphasized: true)
                .foregroundStyle(Color(uiColor: appearance.theme.muted))
                .accessibilityIdentifier(identifier)
        }
    }

    private func remaining(from now: Date) -> String {
        let seconds = max(0, Int(expiration.timeIntervalSince(now).rounded(.up)))
        return String(format: "%d:%02d remaining", seconds / 60, seconds % 60)
    }
}
