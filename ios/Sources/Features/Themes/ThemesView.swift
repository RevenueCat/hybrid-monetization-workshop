import SwiftUI

struct ThemesView: View {
    @EnvironmentObject private var appearance: AppearanceStore
    @EnvironmentObject private var plus: PlusAccessStore

    var body: some View {
        LibraryPage(title: "Themes") {
            if let expiration = plus.premiumThemesExpirationDate {
                ThemeAccessCountdown(
                    expiration: expiration,
                    prefix: "Theme preview active",
                    identifier: "themes.reward.active"
                )
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    Color(uiColor: appearance.theme.surface),
                    in: RoundedRectangle(cornerRadius: appearance.theme.cornerRadius)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: appearance.theme.cornerRadius)
                        .stroke(Color(uiColor: appearance.theme.line), lineWidth: 1)
                )
            }
            if let error = appearance.iconError {
                VStack(alignment: .leading, spacing: 12) {
                    Text(error).themeFont(appearance.theme, style: .subheadline)
                    Button("Try again") { appearance.syncAppIcon() }
                        .buttonStyle(KitchenButtonStyle())
                        .disabled(appearance.isChangingIcon)
                }
            }
            ForEach(AppTheme.allCases) { theme in
                Button {
                    if theme == .original {
                        appearance.theme = theme
                    } else {
                        plus.requestPremiumTheme(theme)
                    }
                } label: {
                    ThemePreview(theme: theme, isSelected: appearance.theme == theme)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("theme.\(theme.rawValue)")
                .accessibilityAddTraits(appearance.theme == theme ? .isSelected : [])
            }
        }
    }
}
