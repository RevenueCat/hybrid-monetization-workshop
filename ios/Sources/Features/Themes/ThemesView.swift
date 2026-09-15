import SwiftUI

struct ThemesView: View {
    @EnvironmentObject private var appearance: AppearanceStore

    var body: some View {
        LibraryPage(title: "Themes") {
            if let error = appearance.iconError {
                VStack(alignment: .leading, spacing: 12) {
                    Text(error).themeFont(appearance.theme, style: .subheadline)
                    Button("Try again") { appearance.syncAppIcon() }
                        .buttonStyle(KitchenButtonStyle())
                        .disabled(appearance.isChangingIcon)
                }
            }
            ForEach(AppTheme.allCases) { theme in
                Button { appearance.theme = theme } label: {
                    ThemePreview(theme: theme, isSelected: appearance.theme == theme)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("theme.\(theme.rawValue)")
                .accessibilityAddTraits(appearance.theme == theme ? .isSelected : [])
            }
        }
    }
}
