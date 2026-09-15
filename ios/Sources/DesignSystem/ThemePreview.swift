import SwiftUI

struct ThemePreview: View {
    let theme: AppTheme
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(theme.name).themeFont(theme, style: .headline)
                    Text(theme.summary).themeFont(theme, style: .caption1)
                }
                Spacer(minLength: 8)
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .accessibilityHidden(true)
            }
            Text(theme.title("Kitchen Table")).themeTitleFont(theme, size: 25)
            HStack(spacing: 6) {
                ForEach(0..<4) { index in
                    let colors = [theme.paper, theme.surface, theme.done, theme.active]
                    Rectangle().fill(Color(uiColor: colors[index])).frame(height: 20)
                        .overlay(Rectangle().stroke(Color(uiColor: theme.line), lineWidth: 0.5))
                }
            }.accessibilityHidden(true)
        }
        .foregroundStyle(Color(uiColor: theme.ink)).padding(18)
        .background(Color(uiColor: theme.paper), in: RoundedRectangle(cornerRadius: theme.cornerRadius))
        .overlay(RoundedRectangle(cornerRadius: theme.cornerRadius)
            .stroke(Color(uiColor: isSelected ? theme.accent : theme.line), lineWidth: isSelected ? 2 : 1))
    }
}
