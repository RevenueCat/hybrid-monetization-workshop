import SwiftUI

struct IncomingRecipeSection: View {
    @EnvironmentObject private var appearance: AppearanceStore
    @EnvironmentObject private var ads: AdSupportStore
    @ObservedObject var incoming: IncomingRecipeStore
    var discardImport: (IncomingRecipe) -> Void

    var body: some View {
        Group {
            if !incoming.visibleItems.isEmpty {
                ForEach(incoming.visibleItems.filter { $0.status != .complete }) { item in
                    VStack(spacing: 0) {
                        RecipeBookRow(title: item.title, subtitle: subtitle(item), secondaryColor: appearance.theme.pendingRecipeSecondary) {
                            HStack(spacing: 12) {
                                Button { discardImport(item) } label: {
                                    Image(systemName: "trash")
                                        .foregroundStyle(Color(uiColor: appearance.theme.muted))
                                        .frame(width: 44, height: 44, alignment: .trailing)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Discard import \(item.title)")
                                .accessibilityIdentifier("incoming.remove.\(item.title)")
                                switch item.status {
                                case .preparing:
                                    ProgressView().controlSize(.small).frame(width: 44, height: 44, alignment: .trailing)
                                        .accessibilityLabel("Importing recipe")
                                case .waiting:
                                    Image(systemName: "clock").frame(width: 44, height: 44, alignment: .trailing)
                                        .accessibilityLabel("Up next")
                                default:
                                    Button { ads.performAction { incoming.prepare(item.id) } } label: {
                                        Image(systemName: "tray.and.arrow.down").frame(width: 44, height: 44, alignment: .trailing).contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel(item.status == .failed ? "Retry import" : "Import recipe")
                                    .accessibilityIdentifier("incoming.action.\(item.title)")
                                }
                            }
                        }
                        .background {
                            Color(uiColor: appearance.theme.pendingRecipeTint)
                                .padding(.horizontal, -24)
                        }
                        .overlay(alignment: .top) {
                            // Cover the preceding inset separator, without adding a second line.
                            Rectangle().fill(Color(uiColor: appearance.theme.line))
                                .frame(height: 0.5).padding(.horizontal, -24).offset(y: -0.5)
                        }
                        .accessibilityAction(named: "Discard recipe") { discardImport(item) }
                    }
                    .padding(.bottom, 0.5)
                    .overlay(alignment: .bottom) {
                        Rectangle().fill(Color(uiColor: appearance.theme.line)).frame(height: 0.5)
                            .padding(.horizontal, -24)
                    }
                }
            }
            if let error = incoming.errorMessage {
                VStack(alignment: .leading, spacing: 8) {
                    Text(error).themeFont(appearance.theme, style: .caption1)
                    Button("Try again") { incoming.errorMessage = nil; incoming.setActive(false); incoming.setActive(true) }
                }.padding(.vertical, 12)
            }
        }
    }

    private func subtitle(_ item: IncomingRecipe) -> String {
        switch item.status {
        case .preparing: "Importing…"
        case .waiting: "Up next"
        case .failed: "Couldn’t import · Try again"
        default: "Ready to import"
        }
    }
}

struct AddRecipeFromLinkSheet: View {
    @EnvironmentObject private var appearance: AppearanceStore
    @EnvironmentObject private var ads: AdSupportStore
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var incoming: IncomingRecipeStore
    @State private var link = ""
    @State private var saveError: String?
    @State private var contentHeight: CGFloat = 300
    @FocusState private var focused: Bool

    private var url: URL? { RecipeSource.webURL(from: link) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Import from a link").themeTitleFont(appearance.theme, size: 26)
                    .accessibilityAddTraits(.isHeader)
                VStack(alignment: .leading, spacing: 10) {
                    Text("Recipe link").themeFont(appearance.theme, style: .subheadline, emphasized: true)
                    HStack(spacing: 10) {
                        TextField("", text: $link, prompt: Text(verbatim: "https://example.com/recipe")
                            .foregroundStyle(Color(uiColor: appearance.theme.muted).opacity(0.6)))
                            .themeFont(appearance.theme, style: .body)
                            .foregroundStyle(Color(uiColor: appearance.theme.ink))
                            .keyboardType(.URL)
                            .textContentType(.URL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .submitLabel(.done)
                            .focused($focused)
                            .onSubmit(importRecipe)
                            .padding(12)
                            .frame(minHeight: 48)
                            .background(Color(uiColor: appearance.theme.surface), in: RoundedRectangle(cornerRadius: appearance.theme.cornerRadius))
                            .overlay(RoundedRectangle(cornerRadius: appearance.theme.cornerRadius)
                                .stroke(Color(uiColor: appearance.theme.line), lineWidth: 1))
                            .accessibilityLabel("Recipe link")
                            .accessibilityIdentifier("addRecipe.url")
                        RecipePasteButton(theme: appearance.theme) { text in
                            link = text
                            saveError = nil
                        }
                        .id(appearance.theme)
                        .frame(width: 48, height: 48)
                    }
                    if !link.isEmpty && url == nil {
                        Text("Enter a valid website link.")
                            .themeFont(appearance.theme, style: .caption1)
                            .foregroundStyle(Color(uiColor: appearance.theme.muted))
                    }
                    if let saveError {
                        Text(saveError).themeFont(appearance.theme, style: .caption1)
                            .accessibilityIdentifier("addRecipe.error")
                    }
                }
                AdaptiveActionRow {
                    Button("Cancel") { dismiss() }.buttonStyle(KitchenButtonStyle())
                        .accessibilityIdentifier("addRecipe.cancel")
                    Button("Import recipe", action: importRecipe).buttonStyle(KitchenButtonStyle(primary: true))
                        .disabled(url == nil)
                        .accessibilityIdentifier("addRecipe.save")
                }
            }
            .padding(24)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = ceil($0) }
        }
        .scrollBounceBehavior(.basedOnSize)
        .foregroundStyle(Color(uiColor: appearance.theme.ink))
        .tint(Color(uiColor: appearance.theme.ink))
        .presentationBackground(Color(uiColor: appearance.theme.paper))
        .presentationDetents([.height(contentHeight)])
        .presentationDragIndicator(.hidden)
        .onChange(of: link) { _, _ in saveError = nil }
    }

    private func add() {
        guard let url else { return }
        do {
            let id = try incoming.capture(url)
            incoming.prepare(id)
            focused = false
            dismiss()
        } catch { saveError = error.localizedDescription }
    }

    private func importRecipe() {
        guard url != nil else { return }
        focused = false
        ads.performAction(add)
    }
}

/// Keeps the system paste authorization behavior while matching secondary app controls.
private struct RecipePasteButton: UIViewRepresentable {
    let theme: AppTheme
    let paste: (String) -> Void

    func makeCoordinator() -> PasteTarget { PasteTarget(paste: paste) }

    func makeUIView(context: Context) -> UIPasteControl {
        let configuration = UIPasteControl.Configuration()
        configuration.displayMode = .iconOnly
        configuration.cornerStyle = .fixed
        configuration.cornerRadius = theme.cornerRadius
        configuration.baseForegroundColor = theme.ink
        configuration.baseBackgroundColor = theme.surface
        let control = UIPasteControl(configuration: configuration)
        control.target = context.coordinator
        control.accessibilityLabel = "Paste recipe link"
        control.accessibilityIdentifier = "addRecipe.paste"
        control.layer.cornerRadius = theme.cornerRadius
        control.layer.borderWidth = 1
        control.layer.borderColor = theme.line.cgColor
        return control
    }

    func updateUIView(_ control: UIPasteControl, context: Context) {
        context.coordinator.pasteText = paste
        control.layer.borderColor = theme.line.resolvedColor(with: control.traitCollection).cgColor
    }

    final class PasteTarget: UIResponder {
        var pasteText: (String) -> Void
        init(paste: @escaping (String) -> Void) {
            pasteText = paste
            super.init()
            pasteConfiguration = UIPasteConfiguration(forAccepting: NSString.self)
        }
        override func paste(itemProviders: [NSItemProvider]) {
            guard let provider = itemProviders.first(where: { $0.canLoadObject(ofClass: NSString.self) }) else { return }
            _ = provider.loadObject(ofClass: NSString.self) { [weak self] value, _ in
                guard let text = value as? String else { return }
                DispatchQueue.main.async { self?.pasteText(text) }
            }
        }
    }
}
