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
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Kitchen Table, " + title + ", back to Recipe Book")
                .accessibilityIdentifier("page.back")
                content()
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)
            .padding(.bottom, 24)
        }
        .background(Color(uiColor: appearance.theme.paper))
        .foregroundStyle(Color(uiColor: appearance.theme.ink))
        .toolbar(.hidden, for: .navigationBar)
        .navigationTitle(title)
    }
}
