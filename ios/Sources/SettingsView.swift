import SwiftUI

struct LibraryPage<Content: View>: View {
    @EnvironmentObject private var appearance: AppearanceStore
    @Environment(\.dismiss) private var dismiss
    let title: String
    @ViewBuilder var content: () -> Content
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Button { dismiss() } label: {
                    PageHeading(title: title, underlined: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }.buttonStyle(.plain).accessibilityLabel("Kitchen Table, " + title + ", back to Recipe Book")
                    .accessibilityIdentifier("page.back")
                content()
            }.padding(.horizontal, 24).padding(.top, 20).padding(.bottom, 24)
        }
        .background(Color(uiColor: appearance.theme.paper))
        .foregroundStyle(Color(uiColor: appearance.theme.ink))
        .toolbar(.hidden, for: .navigationBar)
        .navigationTitle(title)
    }
}

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

private struct SettingsSection<Content: View>: View {
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
                    Button {
                        appearance.theme = theme
                    } label: {
                        ThemePreview(theme: theme, isSelected: appearance.theme == theme)
                    }.buttonStyle(.plain).accessibilityIdentifier("theme.\(theme.rawValue)")
                        .accessibilityAddTraits(appearance.theme == theme ? .isSelected : [])
                }
        }
    }
}

struct JournalView: View {
    @EnvironmentObject private var appearance: AppearanceStore
    @ObservedObject var library: RecipeLibrary
    @Environment(\.sizeCategory) private var sizeCategory
    var body: some View {
        LibraryPage(title: "Journal") {
            journalSummary
            if library.journalEntries.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Nothing cooked yet").themeFont(appearance.theme, style: .headline)
                        .accessibilityIdentifier("journal.empty")
                    Text("Finished dishes will appear here, with the newest at the top.")
                        .font(appearance.theme.readingFont)
                        .foregroundStyle(Color(uiColor: appearance.theme.muted))
                }
            } else {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(library.journalEntries.enumerated()), id: \.element.id) { index, entry in
                        VStack(alignment: .leading, spacing: 7) {
                            Text(entry.dishName).themeTitleFont(appearance.theme, size: 22)
                                .accessibilityIdentifier("journal.entry.\(index).name")
                            Text(entry.completedAt, format: .dateTime.day().month(.wide).year())
                                .themeFont(appearance.theme, style: .subheadline)
                                .foregroundStyle(Color(uiColor: appearance.theme.muted))
                                .accessibilityIdentifier("journal.entry.\(index).date")
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 20)
                        Rectangle().fill(Color(uiColor: appearance.theme.line)).frame(height: 0.5)
                            .accessibilityHidden(true)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var journalSummary: some View {
        let values = [("Recipes in the book", library.stores.count, "journal.recipes"),
                      ("Dishes cooked", library.dishesCooked, "journal.dishes"),
                      ("Unique dishes cooked", library.uniqueDishesCooked, "journal.unique")]
        if sizeCategory.isAccessibilityCategory {
            VStack(spacing: 0) {
                ForEach(values.indices, id: \.self) { index in
                    summaryRow(values[index].0, value: values[index].1, id: values[index].2)
                }
            }
        } else {
            HStack(alignment: .top, spacing: 12) {
                ForEach(values.indices, id: \.self) { index in
                    let value = values[index]
                    VStack(alignment: .leading, spacing: 6) {
                        Text(value.1.formatted()).themeTitleFont(appearance.theme, size: 30).monospacedDigit()
                            .accessibilityIdentifier(value.2)
                        Text(value.0).themeFont(appearance.theme, style: .caption1)
                            .foregroundStyle(Color(uiColor: appearance.theme.muted))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.vertical, 8)
        }
    }

    private func summaryRow(_ title: String, value: Int, id: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).themeFont(appearance.theme, style: .body)
            Spacer()
            Text(value.formatted()).themeTitleFont(appearance.theme, size: 30).monospacedDigit()
                .accessibilityIdentifier(id)
        }
        .padding(.vertical, 16)
    }
}
