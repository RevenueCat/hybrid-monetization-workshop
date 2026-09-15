import SwiftUI
import UIKit

/// Typography shared by SwiftUI page headings and the UIKit cooking-table heading.
struct PageHeadingStyle {
    static let brand = "KITCHEN TABLE"
    static let tracking: CGFloat = 1.2
    let theme: AppTheme
    let traits: UITraitCollection

    var spacing: CGFloat { theme.brandTitleSpacing }
    var brandFont: UIFont { theme.textFont(.caption2, traits: traits) }
    var titleFont: UIFont { theme.titleFont(traits: traits) }

    func brandAttributes(underlined: Bool) -> [NSAttributedString.Key: Any] {
        var attributes = theme.textDrawingAttributes(font: brandFont, color: theme.muted)
        attributes[.kern] = Self.tracking
        if underlined { attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue }
        return attributes
    }
    func titleAttributes() -> [NSAttributedString.Key: Any] {
        theme.textDrawingAttributes(font: titleFont, color: theme.ink)
    }
}

/// The brand label also appears without a page title in welcome views.
struct PageBrand: View {
    @EnvironmentObject private var appearance: AppearanceStore
    var underlined = false

    var body: some View {
        Text(PageHeadingStyle.brand)
            .themeFont(appearance.theme, style: .caption2)
            .tracking(PageHeadingStyle.tracking)
            .underline(underlined)
            .foregroundStyle(Color(uiColor: appearance.theme.muted))
    }
}

struct PageHeading: View {
    @EnvironmentObject private var appearance: AppearanceStore
    @Environment(\.sizeCategory) private var sizeCategory
    let title: String
    var underlined = false
    var accessibilityPrefix: String = "page"
    var titleCoordinateSpace: CoordinateSpace = .local
    var onTitleFirstLineCenterChange: (CGFloat) -> Void = { _ in }

    private var style: PageHeadingStyle {
        PageHeadingStyle(theme: appearance.theme,
                         traits: UITraitCollection(preferredContentSizeCategory: UIContentSizeCategory(sizeCategory)))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: style.spacing) {
            PageBrand(underlined: underlined)
                .accessibilityIdentifier(accessibilityPrefix + ".brand")
            Text(appearance.theme.title(title))
                .themeTitleFont(appearance.theme)
                .foregroundStyle(Color(uiColor: appearance.theme.ink))
                .fixedSize(horizontal: false, vertical: true)
                .onGeometryChange(for: CGFloat.self) {
                    $0.frame(in: titleCoordinateSpace).minY + style.titleFont.lineHeight / 2
                } action: { onTitleFirstLineCenterChange($0) }
                .accessibilityIdentifier(accessibilityPrefix + ".title")
        }
    }
}
