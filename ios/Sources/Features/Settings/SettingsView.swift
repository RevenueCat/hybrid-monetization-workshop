import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var appearance: AppearanceStore
    var body: some View {
        LibraryPage(title: "Settings") {
            VStack(alignment: .leading, spacing: 0) {
                SettingsSection(title: "Cooking") {
                    VStack(alignment: .leading, spacing: 12) {
                        ThemedToggle(title: "Keep screen on", isOn: $appearance.keepScreenAwake,
                                     identifier: "settings.keepScreenAwake")
                        Text("Prevents auto-lock while cooking. Uses more battery. Auto-lock resumes when you leave the recipe or the app.")
                            .themeFont(appearance.theme, style: .subheadline)
                            .foregroundStyle(Color(uiColor: appearance.theme.muted))
                    }
                }

                settingsDivider

                SettingsSection(title: "Display") {
                    VStack(alignment: .leading, spacing: 20) {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Appearance").themeFont(appearance.theme, style: .headline)
                            ThemedSegments(title: "Appearance", selection: $appearance.mode, options: AppearanceMode.allCases, label: { $0.rawValue })
                                .accessibilityIdentifier("settings.appearance")
                        }
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Table spacing").themeFont(appearance.theme, style: .headline)
                            ThemedSegments(title: "Table spacing", selection: $appearance.density, options: GridDensity.allCases, label: { $0.rawValue })
                                .accessibilityIdentifier("settings.density")
                            Text("Compact shows more of the recipe. Comfort gives cells more room.")
                                .themeFont(appearance.theme, style: .subheadline)
                                .foregroundStyle(Color(uiColor: appearance.theme.muted))
                        }

                    }
                }
            }
        }
    }

    private var settingsDivider: some View {
        Rectangle()
            .fill(Color(uiColor: appearance.theme.line))
            .frame(height: 0.5)
            .padding(.vertical, 20)
            .accessibilityHidden(true)
    }
}

struct SettingsSection<Content: View>: View {
    @EnvironmentObject private var appearance: AppearanceStore
    let title: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title.uppercased())
                .themeFont(appearance.theme, style: .caption1, emphasized: true)
                .tracking(1.2)
                .foregroundStyle(Color(uiColor: appearance.theme.muted))
                .accessibilityAddTraits(.isHeader)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
