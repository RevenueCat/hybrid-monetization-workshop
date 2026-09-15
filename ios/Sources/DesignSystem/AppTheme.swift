import SwiftUI
import UIKit

/// Stable IDs are persisted in appearance preferences.
enum AppTheme: String, CaseIterable, Identifiable {
    case original, ferran, dinner, genius, manual
    var id: String { rawValue }
    var alternateIconName: String? {
        switch self {
        case .original: return nil
        case .ferran: return "AppIcon-studio"
        case .dinner: return "AppIcon-editorial"
        case .genius: return "AppIcon-archive"
        case .manual: return "AppIcon-classic"
        }
    }

    private var definition: ThemeDefinition {
        switch self {
        case .original: return .original
        case .ferran: return .studio
        case .dinner: return .editorial
        case .genius: return .archive
        case .manual: return .classic
        }
    }

    var name: String { definition.name }
    var summary: String { definition.summary }
    var paper: UIColor { definition.palette.paper.color }
    var surface: UIColor { definition.palette.surface.color }
    var ink: UIColor { definition.palette.ink.color }
    var muted: UIColor { definition.palette.muted.color }
    var line: UIColor { definition.palette.line.color }
    var done: UIColor { definition.palette.done.color }
    var active: UIColor { definition.palette.active.color }
    var glow: UIColor { definition.palette.glow.color }
    var accent: UIColor { definition.palette.accent.color }
    var onAccent: UIColor { definition.palette.onAccent.color }
    /// A quiet accent wash over paper; slightly stronger in dark mode to stay visible.
    var pendingRecipeTint: UIColor {
        UIColor { traits in
            self.accent.resolvedColor(with: traits)
                .withAlphaComponent(traits.userInterfaceStyle == .dark ? 0.10 : 0.07)
        }
    }
    /// Readable secondary text and icons on the pending-row wash in every palette.
    var pendingRecipeSecondary: UIColor {
        UIColor { traits in self.ink.resolvedColor(with: traits).withAlphaComponent(0.72) }
    }
    var cornerRadius: CGFloat { definition.cornerRadius }
    var cellSize: CGFloat { definition.cellSize }
    var brandTitleSpacing: CGFloat { definition.brandTitleSpacing }
    func title(_ text: String) -> String { definition.uppercaseTitles ? text.uppercased() : text }

    func titleFont(size: CGFloat = 34, traits: UITraitCollection? = nil) -> UIFont {
        definition.typography.title.scaled(size: size, style: .largeTitle, traits: traits)
    }
    var titleWeight: Font.Weight? { definition.typography.title.swiftUIWeight }

    func cellFont(size: CGFloat, completed: Bool = false, secondary: Bool = false, traits: UITraitCollection? = nil) -> UIFont {
        let typography = definition.typography
        let font = secondary ? typography.secondaryCell : completed ? typography.completedCell : typography.cell
        return font.scaled(size: size, style: secondary ? .footnote : .body, traits: traits)
    }
    private func textFace(_ style: UIFont.TextStyle, emphasized: Bool) -> ThemeFont {
        emphasized || style == .headline ? definition.typography.emphasized : definition.typography.body
    }
    func textFont(_ style: UIFont.TextStyle = .body, emphasized: Bool = false, traits: UITraitCollection? = nil) -> UIFont {
        let size = UIFont.preferredFont(forTextStyle: style, compatibleWith: UITraitCollection(preferredContentSizeCategory: .large)).pointSize
        return textFace(style, emphasized: emphasized).scaled(size: size, style: style, traits: traits)
    }
    func textWeight(_ style: UIFont.TextStyle, emphasized: Bool = false) -> Font.Weight? {
        textFace(style, emphasized: emphasized).swiftUIWeight
    }
    var readingFont: Font { definition.typography.reading }

    func textDrawingAttributes(font: UIFont, color: UIColor) -> [NSAttributedString.Key: Any] {
        var attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        if let stroke = definition.typography.inkStroke, font.familyName == stroke.family {
            // Add ink to a single-weight face without changing its outlines or spacing.
            attributes[.strokeWidth] = stroke.width
            attributes[.strokeColor] = color
        }
        return attributes
    }
}

private struct ThemeColor {
    let light: UInt32
    let dark: UInt32
    var color: UIColor {
        UIColor { traits in
            let rgb = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: CGFloat((rgb >> 16) & 255) / 255,
                           green: CGFloat((rgb >> 8) & 255) / 255,
                           blue: CGFloat(rgb & 255) / 255, alpha: 1)
        }
    }
}

/// Semantic pairs mirror the web palettes; field names make their roles explicit.
private struct ThemePalette {
    let paper, surface, ink, muted, line, done, active, glow, accent, onAccent: ThemeColor
}

private struct ThemeFont {
    var names: [String] = []
    var fallbackWeight: UIFont.Weight = .regular
    var monospacedFallback = false
    var swiftUIWeight: Font.Weight? = nil

    func scaled(size: CGFloat, style: UIFont.TextStyle, traits: UITraitCollection?) -> UIFont {
        let font = names.lazy.compactMap { UIFont(name: $0, size: size) }.first
            ?? (monospacedFallback ? .monospacedSystemFont(ofSize: size, weight: fallbackWeight)
                                   : .systemFont(ofSize: size, weight: fallbackWeight))
        return UIFontMetrics(forTextStyle: style).scaledFont(for: font, compatibleWith: traits)
    }

    static let system = ThemeFont()
    static let medium = ThemeFont(fallbackWeight: .medium)
    static let georgia = ThemeFont(names: ["Georgia"])
    static let georgiaBold = ThemeFont(names: ["Georgia-Bold"])
    static let helvetica = ThemeFont(names: ["HelveticaNeue"])
    static let helveticaMedium = ThemeFont(names: ["HelveticaNeue-Medium"])
    static let typewriter = ThemeFont(names: ["SpecialElite-Regular"], fallbackWeight: .medium,
                                      monospacedFallback: true, swiftUIWeight: .bold)
    static let courier = ThemeFont(names: ["CourierNewPSMT"], monospacedFallback: true)
}

private struct ThemeTypography {
    let title, body, emphasized, cell, completedCell, secondaryCell: ThemeFont
    var reading: Font = .body
    var inkStroke: (family: String, width: CGFloat)? = nil
}

private struct ThemeDefinition {
    let name: String
    let summary: String
    let palette: ThemePalette
    let typography: ThemeTypography
    let cornerRadius: CGFloat
    var cellSize: CGFloat = 14
    var brandTitleSpacing: CGFloat = 6
    var uppercaseTitles = false
}

private extension ThemeDefinition {
    static let original = ThemeDefinition(
        name: "Original",
        summary: "Quiet neutrals and familiar type.",
        palette: ThemePalette(
            paper: ThemeColor(light: 0xfaf9f5, dark: 0x1b1c19),
            surface: ThemeColor(light: 0xffffff, dark: 0x232421),
            ink: ThemeColor(light: 0x252923, dark: 0xedf0e8),
            muted: ThemeColor(light: 0x60665c, dark: 0xb7bfb0),
            line: ThemeColor(light: 0xcbd0c4, dark: 0x535b4b),
            done: ThemeColor(light: 0xf2f3ef, dark: 0x2c2e29),
            active: ThemeColor(light: 0xfffdf7, dark: 0x2b2b25),
            glow: ThemeColor(light: 0xa69b7d, dark: 0xa99f7e),
            accent: ThemeColor(light: 0x42453f, dark: 0xd0d3ca),
            onAccent: ThemeColor(light: 0xffffff, dark: 0x20221d)
        ),
        typography: ThemeTypography(
            title: .medium, body: .system, emphasized: .medium,
            cell: .medium, completedCell: .system, secondaryCell: .system
        ),
        cornerRadius: 12
    )

    static let studio = ThemeDefinition(
        name: "Studio",
        summary: "Cool greens, blush accents, precise sans serif.",
        palette: ThemePalette(
            paper: ThemeColor(light: 0xfafaf7, dark: 0x222827),
            surface: ThemeColor(light: 0xedf0eb, dark: 0x2b3430),
            ink: ThemeColor(light: 0x252b2a, dark: 0xeef0e9),
            muted: ThemeColor(light: 0x555e57, dark: 0xc0c8c1),
            line: ThemeColor(light: 0xa3aea4, dark: 0x728478),
            done: ThemeColor(light: 0xdde3dc, dark: 0x39453c),
            active: ThemeColor(light: 0xf6ebe6, dark: 0x443b38),
            glow: ThemeColor(light: 0x947668, dark: 0xd3aba0),
            accent: ThemeColor(light: 0x515e58, dark: 0xd1dbd1),
            onAccent: ThemeColor(light: 0xffffff, dark: 0x222827)
        ),
        typography: ThemeTypography(
            title: ThemeFont(names: ["HelveticaNeue-Light"], fallbackWeight: .light),
            body: .helvetica, emphasized: .helveticaMedium,
            cell: .helveticaMedium, completedCell: .helvetica, secondaryCell: .helvetica
        ),
        cornerRadius: 2, uppercaseTitles: true
    )

    static let editorial = ThemeDefinition(
        name: "Editorial",
        summary: "Warm paper and expressive menu typography.",
        palette: ThemePalette(
            paper: ThemeColor(light: 0xf5efe3, dark: 0x28231e),
            surface: ThemeColor(light: 0xfcf8f0, dark: 0x302a23),
            ink: ThemeColor(light: 0x28231d, dark: 0xf3e9d8),
            muted: ThemeColor(light: 0x645b4d, dark: 0xcabeaa),
            line: ThemeColor(light: 0xb0a48e, dark: 0x93846c),
            done: ThemeColor(light: 0xe8e0d1, dark: 0x3d352b),
            active: ThemeColor(light: 0xfffaf0, dark: 0x3f362b),
            glow: ThemeColor(light: 0x947448, dark: 0xd2b38e),
            accent: ThemeColor(light: 0x302a23, dark: 0xefe2cb),
            onAccent: ThemeColor(light: 0xffffff, dark: 0x28231e)
        ),
        typography: ThemeTypography(
            title: ThemeFont(names: ["BodoniSvtyTwoITCTT-Bold", "Georgia-Bold"], fallbackWeight: .bold),
            body: .georgia, emphasized: .georgiaBold,
            cell: .medium, completedCell: .system, secondaryCell: .system,
            reading: .custom("Georgia", size: 18, relativeTo: .body)
        ),
        cornerRadius: 4, uppercaseTitles: true
    )

    static let archive = ThemeDefinition(
        name: "Archive",
        summary: "Olive tones and a collected-book feel.",
        palette: ThemePalette(
            paper: ThemeColor(light: 0xf7f4eb, dark: 0x282a23),
            surface: ThemeColor(light: 0xfcfaf3, dark: 0x303329),
            ink: ThemeColor(light: 0x2d3027, dark: 0xefeddc),
            muted: ThemeColor(light: 0x60624e, dark: 0xc4c5ac),
            line: ThemeColor(light: 0xa0a08c, dark: 0x8b8e75),
            done: ThemeColor(light: 0xe8e7dc, dark: 0x3b3f31),
            active: ThemeColor(light: 0xf8f7e7, dark: 0x373c2b),
            glow: ThemeColor(light: 0x81835e, dark: 0xc8ca9d),
            accent: ThemeColor(light: 0x535641, dark: 0xe4e7cc),
            onAccent: ThemeColor(light: 0xffffff, dark: 0x282a23)
        ),
        typography: ThemeTypography(
            title: ThemeFont(names: ["Georgia"], fallbackWeight: .medium),
            body: .georgia, emphasized: .georgiaBold,
            cell: .georgiaBold, completedCell: .georgia, secondaryCell: .georgia,
            reading: .custom("Georgia", size: 18, relativeTo: .body)
        ),
        cornerRadius: 4, cellSize: 15
    )

    static let classic = ThemeDefinition(
        name: "Classic",
        summary: "Aged paper, imperfect typewriter ink, red-pencil accents.",
        palette: ThemePalette(
            paper: ThemeColor(light: 0xf2ead8, dark: 0x241f1a),
            surface: ThemeColor(light: 0xfffbef, dark: 0x2f2923),
            ink: ThemeColor(light: 0x2c2923, dark: 0xeee4cf),
            muted: ThemeColor(light: 0x6f675c, dark: 0xc5b8a2),
            line: ThemeColor(light: 0xaaa08f, dark: 0x776b5c),
            done: ThemeColor(light: 0xe0d7c5, dark: 0x3a332c),
            active: ThemeColor(light: 0xefe0d8, dark: 0x49322d),
            glow: ThemeColor(light: 0xa34735, dark: 0xd88977),
            accent: ThemeColor(light: 0x9b3d31, dark: 0xd28270),
            onAccent: ThemeColor(light: 0xffffff, dark: 0x231b18)
        ),
        typography: ThemeTypography(
            title: .typewriter, body: .courier, emphasized: .typewriter,
            cell: .typewriter, completedCell: .typewriter, secondaryCell: .courier,
            reading: .custom("SpecialElite-Regular", size: 17, relativeTo: .body).bold(),
            inkStroke: (family: "Special Elite", width: -2)
        ),
        cornerRadius: 2,
        // Special Elite sits high in its line box; leave more room below the brand.
        brandTitleSpacing: 12
    )
}
