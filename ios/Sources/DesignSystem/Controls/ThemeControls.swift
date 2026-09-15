import SwiftUI

private struct ThemedFontModifier: ViewModifier {
    @Environment(\.sizeCategory) private var sizeCategory
    let font: (UITraitCollection) -> UIFont
    var weight: Font.Weight?
    func body(content: Content) -> some View {
        content
            .font(Font(font(UITraitCollection(preferredContentSizeCategory: UIContentSizeCategory(sizeCategory)))))
            .fontWeight(weight)
    }
}

extension View {
    func themeFont(_ theme: AppTheme, style: UIFont.TextStyle = .body, emphasized: Bool = false) -> some View {
        modifier(ThemedFontModifier(
            font: { theme.textFont(style, emphasized: emphasized, traits: $0) },
            weight: theme.textWeight(style, emphasized: emphasized)
        ))
    }
    func themeTitleFont(_ theme: AppTheme, size: CGFloat = 34) -> some View {
        modifier(ThemedFontModifier(
            font: { theme.titleFont(size: size, traits: $0) },
            weight: theme.titleWeight
        ))
    }
}

struct AdaptiveActionRow<Content: View>: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ViewBuilder let content: () -> Content
    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10)) : AnyLayout(HStackLayout(alignment: .top, spacing: 10))
        layout { content() }
    }
}

struct KitchenButtonStyle: ButtonStyle {
    @EnvironmentObject private var appearance: AppearanceStore
    @Environment(\.isEnabled) private var enabled
    // Reserve primary emphasis for at most one action in the active screen or sheet.
    var primary = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.themeFont(appearance.theme, style: .body, emphasized: true).multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, minHeight: 24).padding(.horizontal, 16).padding(.vertical, 12)
            .foregroundStyle(Color(uiColor: primary ? appearance.theme.onAccent : appearance.theme.ink))
            .background(Color(uiColor: primary ? appearance.theme.accent : appearance.theme.surface), in: RoundedRectangle(cornerRadius: appearance.theme.cornerRadius))
            .overlay(RoundedRectangle(cornerRadius: appearance.theme.cornerRadius).stroke(Color(uiColor: primary ? appearance.theme.accent : appearance.theme.line), lineWidth: 1))
            .opacity(!enabled ? 0.45 : configuration.isPressed ? 0.75 : 1)
    }
}


/// Keep native switch interaction and accessibility while theming both track states.
struct ThemedToggle: View {
    @EnvironmentObject private var appearance: AppearanceStore
    @Environment(\.isEnabled) private var enabled
    let title: String
    @Binding var isOn: Bool
    let identifier: String

    var body: some View {
        HStack(spacing: 12) {
            Text(title)
                .themeFont(appearance.theme, style: .headline)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture { if enabled { isOn.toggle() } }
                .accessibilityHidden(true)
            ThemedSwitchControl(title: title, isOn: $isOn, identifier: identifier)
                .fixedSize()
                .frame(minHeight: 44)
        }
    }
}

private struct ThemedSwitchControl: UIViewRepresentable {
    @EnvironmentObject private var appearance: AppearanceStore
    @Environment(\.isEnabled) private var enabled
    let title: String
    @Binding var isOn: Bool
    let identifier: String

    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeUIView(context: Context) -> UISwitch {
        let control = UISwitch()
        control.addTarget(context.coordinator, action: #selector(Coordinator.changed(_:)), for: .valueChanged)
        return control
    }
    func updateUIView(_ control: UISwitch, context: Context) {
        context.coordinator.change = { isOn = $0 }
        control.setOn(isOn, animated: !UIAccessibility.isReduceMotionEnabled && control.window != nil)
        control.isEnabled = enabled
        control.accessibilityLabel = title
        control.accessibilityIdentifier = identifier
        control.onTintColor = appearance.theme.accent
        control.tintColor = appearance.theme.line
        control.backgroundColor = isOn ? appearance.theme.accent : appearance.theme.line
        control.thumbTintColor = isOn ? appearance.theme.onAccent : appearance.theme.surface
        control.layer.cornerRadius = control.intrinsicContentSize.height / 2
    }

    final class Coordinator: NSObject {
        var change: ((Bool) -> Void)?
        @objc func changed(_ control: UISwitch) { change?(control.isOn) }
    }
}

/// Preserve readable, full labels when segmented choices no longer fit.
struct ThemedSegments<Selection: Hashable>: View {
    @EnvironmentObject private var appearance: AppearanceStore
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let title: String
    @Binding var selection: Selection
    let options: [Selection]
    let label: (Selection) -> String

    var body: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(spacing: 8) {
                ForEach(options, id: \.self) { option in
                    Button { selection = option } label: {
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            Text(label(option)).fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 0)
                            Image(systemName: selection == option ? "checkmark.circle.fill" : "circle")
                                .accessibilityHidden(true)
                        }
                        .themeFont(appearance.theme, style: .subheadline, emphasized: selection == option)
                        .frame(maxWidth: .infinity, minHeight: 24, alignment: .leading).padding(12)
                        .foregroundStyle(Color(uiColor: appearance.theme.ink))
                        .background(Color(uiColor: selection == option ? appearance.theme.active : appearance.theme.surface), in: RoundedRectangle(cornerRadius: appearance.theme.cornerRadius))
                        .overlay(RoundedRectangle(cornerRadius: appearance.theme.cornerRadius)
                            .stroke(Color(uiColor: selection == option ? appearance.theme.ink : appearance.theme.line), lineWidth: selection == option ? 2 : 1))
                    }.buttonStyle(.plain)
                        .accessibilityLabel(label(option))
                        .accessibilityAddTraits(selection == option ? .isSelected : [])
                }
            }.accessibilityElement(children: .contain).accessibilityLabel(title)
        } else {
            SegmentedChoices(title: title, selection: $selection, options: options, label: label)
        }
    }
}

/// Local styling avoids global UISegmentedControl appearance caches and updates in place.
private struct SegmentedChoices<Selection: Hashable>: UIViewRepresentable {
    @EnvironmentObject private var appearance: AppearanceStore
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let title: String
    @Binding var selection: Selection
    let options: [Selection]
    let label: (Selection) -> String

    func makeCoordinator() -> SegmentSelectionCoordinator { SegmentSelectionCoordinator() }
    func makeUIView(context: Context) -> ThemeSegmentControl {
        let control = ThemeSegmentControl(items: options.map(label))
        control.addTarget(context.coordinator, action: #selector(SegmentSelectionCoordinator.changed(_:)), for: .valueChanged)
        return control
    }
    func updateUIView(_ control: ThemeSegmentControl, context: Context) {
        context.coordinator.select = { index in
            if options.indices.contains(index) { selection = options[index] }
        }
        control.accessibilityLabel = title
        control.selectedSegmentIndex = options.firstIndex(of: selection) ?? UISegmentedControl.noSegment
        control.theme = appearance.theme
        control.applyTheme()
    }
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: ThemeSegmentControl, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? uiView.intrinsicContentSize.width, height: max(44, uiView.theme.textFont(.subheadline, traits: uiView.traitCollection).lineHeight + 20))
    }
}

final class SegmentSelectionCoordinator: NSObject {
    var select: ((Int) -> Void)?
    @objc func changed(_ control: UISegmentedControl) { select?(control.selectedSegmentIndex) }
}

final class ThemeSegmentControl: UISegmentedControl {
    var theme: AppTheme = .original
    override init(items: [Any]?) {
        super.init(items: items)
        registerForTraitChanges([UITraitUserInterfaceStyle.self, UITraitPreferredContentSizeCategory.self]) { (control: ThemeSegmentControl, _: UITraitCollection) in
            control.applyTheme()
        }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    func applyTheme() {
        let font = theme.textFont(.subheadline, traits: traitCollection)
        setTitleTextAttributes(theme.textDrawingAttributes(font: font, color: theme.ink), for: .normal)
        let selectedFont = theme.textFont(.subheadline, emphasized: true, traits: traitCollection)
        // A contained segment communicates selection, not a competing primary action.
        setTitleTextAttributes(theme.textDrawingAttributes(font: selectedFont, color: theme.onAccent), for: .selected)
        selectedSegmentTintColor = theme.accent
        backgroundColor = theme.surface
        invalidateIntrinsicContentSize()
        setNeedsLayout()
    }
}
