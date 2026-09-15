import SwiftUI

struct CellPreview: UIViewRepresentable {
    @EnvironmentObject private var appearance: AppearanceStore
    @Environment(\.gridDensityOverride) private var gridDensityOverride
    @Environment(\.sizeCategory) private var sizeCategory
    @Environment(\.displayScale) private var displayScale
    let cell: RecipeCell
    let cells: [RecipeCell]
    let layout: RecipeTableLayout

    private var cellSize: CGSize {
        let traits = UITraitCollection(traitsFrom: [UITraitCollection(preferredContentSizeCategory: UIContentSizeCategory(sizeCategory)), UITraitCollection(displayScale: displayScale)])
        let editedCells = cells.map { $0.id == cell.id ? cell : $0 }
        return RecipeGridGeometry(cells: editedCells, layout: layout, theme: appearance.theme, density: gridDensityOverride ?? appearance.density, traits: traits).frames[cell.id]!.size
    }
    func makeUIView(context: Context) -> CellPreviewScrollView { CellPreviewScrollView(cell: cell) }
    func updateUIView(_ view: CellPreviewScrollView, context: Context) {
        view.cellView.cell = cell
        view.cellView.theme = appearance.theme
        view.refreshAppearance(density: gridDensityOverride ?? appearance.density)
        view.previewSize = cellSize
        view.setNeedsLayout()
    }
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: CellPreviewScrollView, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? cellSize.width, height: min(cellSize.height, 320))
    }
}

/// A bounded view onto the full-size cell; scroll to inspect wide or tall merged cells.
final class CellPreviewScrollView: UIScrollView {
    private enum PreviewState: String {
        case unchecked = "Unchecked", current = "Current step", checked = "Checked"
    }
    private var previewState: PreviewState = .unchecked
    let cellView: GridCellButton
    var previewSize = CGSize.zero
    private var priorSize = CGSize.zero
    private var priorViewport = CGSize.zero
    init(cell: RecipeCell) {
        cellView = GridCellButton(cell: cell)
        super.init(frame: .zero)
        cellView.onTap = { [weak self] in self?.cycleState() }
        // Preview supports tapping and scrolling, without the cooking cell's hold action.
        cellView.gestureRecognizers?.forEach { $0.isEnabled = false }
        cellView.accessibilityIdentifier = "edit.preview"
        cellView.drawsRightBorder = true; cellView.drawsBottomBorder = true
        addSubview(cellView)
        accessibilityIdentifier = "edit.preview.viewport"
        contentInsetAdjustmentBehavior = .never
        isDirectionalLockEnabled = true
        delaysContentTouches = false
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    func refreshAppearance(density: GridDensity) {
        cellView.update(state: previewState == .checked ? .complete : .pending, current: previewState == .current, density: density)
        cellView.accessibilityTraits = .button
        cellView.accessibilityValue = previewState.rawValue
        cellView.accessibilityHint = "Show the next preview state: unchecked, current step, or checked. Cooking progress is unchanged."
        cellView.accessibilityCustomActions = nil
    }
    private func cycleState() {
        switch previewState {
        case .unchecked: previewState = .current
        case .current: previewState = .checked
        case .checked: previewState = .unchecked
        }
        refreshAppearance(density: cellView.density)
    }
    override func touchesShouldCancel(in view: UIView) -> Bool { true }
    override func layoutSubviews() {
        super.layoutSubviews()
        cellView.frame = CGRect(x: max(0, (bounds.width - previewSize.width) / 2), y: 0, width: previewSize.width, height: previewSize.height)
        contentSize = CGSize(width: max(bounds.width, previewSize.width), height: previewSize.height)
        if priorSize != previewSize || priorViewport != bounds.size {
            priorSize = previewSize; priorViewport = bounds.size
            // Start where the real cell draws its text, retaining the original scale.
            contentOffset = CGPoint(x: cellView.cell.isIngredient ? 0 : max(0, (previewSize.width - bounds.width) / 2),
                                    y: max(0, (previewSize.height - bounds.height) / 2))
        }
    }
}

struct CellDetails: View {
    @ObservedObject var store: SessionStore
    @EnvironmentObject private var appearance: AppearanceStore
    let cellID: String
    let close: () -> Void
    var walkthroughSuggestion: String? = nil
    var editorFinished: (() -> Void)? = nil
    var onTimerComplete: (() -> Void)? = nil
    var onTimerCancel: (() -> Void)? = nil
    var onTimerAddMinutes: ((Int) -> Void)? = nil
    @State private var editing = false
    @State private var contentHeight: CGFloat = 280

    private var cell: RecipeCell { store.cell(cellID) }
    var body: some View {
        Group {
            if editing {
                CellEditor(store: store, cellID: cellID, suggestion: walkthroughSuggestion, cancel: editorFinished == nil ? nil : close, done: { editing = false; editorFinished?() })
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        Text(cell.isIngredient ? "INGREDIENT" : "STEP").themeFont(appearance.theme, style: .caption1).tracking(1.2)
                            .foregroundStyle(Color(uiColor: appearance.theme.muted))
                        Text(appearance.theme.title(cell.label)).themeTitleFont(appearance.theme, size: 30).accessibilityIdentifier("details.title")
                        if let timer = store.timerPresentation(for: cellID) {
                            VStack(alignment: .leading, spacing: 12) {
                                Text(timer.text).themeTitleFont(appearance.theme, size: 38).monospacedDigit()
                                    .accessibilityLabel(timer.accessibilityText).accessibilityIdentifier("timer.countdown")
                                if let amount = cell.amount, !amount.isEmpty {
                                    Text(amount).themeFont(appearance.theme, style: .title3).monospacedDigit().foregroundStyle(Color(uiColor: appearance.theme.muted))
                                }
                                AdaptiveActionRow {
                                    Button("−1 min") { addMinutes(-1) }.buttonStyle(KitchenButtonStyle()).accessibilityIdentifier("timer.subtractOne")
                                        .disabled(timer.needsAttention)
                                    Button("+1 min") { addMinutes(1) }.buttonStyle(KitchenButtonStyle()).accessibilityIdentifier("timer.addOne")
                                }
                                AdaptiveActionRow {
                                    Button("−5 min") { addMinutes(-5) }.buttonStyle(KitchenButtonStyle()).accessibilityIdentifier("timer.subtractFive")
                                        .disabled(timer.needsAttention)
                                    Button("+5 min") { addMinutes(5) }.buttonStyle(KitchenButtonStyle()).accessibilityIdentifier("timer.addFive")
                                }
                                AdaptiveActionRow {
                                    Button(timer.needsAttention ? "Complete" : "Complete early") {
                                        if let onTimerComplete { onTimerComplete() } else { store.completeTimer(cellID) }
                                        close()
                                    }.buttonStyle(KitchenButtonStyle()).accessibilityIdentifier("timer.complete")
                                    Button("Cancel timer") {
                                        if let onTimerCancel { onTimerCancel() } else { store.cancelTimer(cellID) }
                                        close()
                                    }.buttonStyle(KitchenButtonStyle()).accessibilityIdentifier("timer.cancel")
                                }
                            }
                        } else if let amount = cell.amount, !amount.isEmpty {
                            Text(amount).themeFont(appearance.theme, style: .title3).monospacedDigit().foregroundStyle(Color(uiColor: appearance.theme.muted))
                        }
                        if let cue = cell.cue, !cue.isEmpty { Text(cue).themeFont(appearance.theme, style: .body, emphasized: true) }
                        if !cell.dependencies.isEmpty {
                            Text("Uses · " + cell.dependencies.map { store.cell($0).label }.joined(separator: ", "))
                                .themeFont(appearance.theme, style: .caption1).foregroundStyle(Color(uiColor: appearance.theme.muted))
                        }
                        if !cell.instruction.isEmpty { Text(cell.instruction).font(appearance.theme.readingFont).lineSpacing(5) }
                        ForEach(Array(cell.inputReferences.enumerated()), id: \.offset) { _, reference in
                            Text(reference).themeFont(appearance.theme, style: .body)
                                .foregroundStyle(Color(uiColor: appearance.theme.muted))
                        }
                        if let walkthroughSuggestion {
                            Text("Add a cooking note, if you like. Try “\(walkthroughSuggestion)” in Short clarification, or write your own.").themeFont(appearance.theme, style: .callout)
                        }
                        AdaptiveActionRow {
                            Button("Done", action: close).buttonStyle(KitchenButtonStyle(primary: true)).accessibilityIdentifier("details.back")
                            Button("Edit") { editing = true }.buttonStyle(KitchenButtonStyle()).accessibilityIdentifier("cell.edit")
                        }.padding(.top, 4)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading).padding(24)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = ceil($0) }
                }
                .scrollBounceBehavior(.basedOnSize)
            }
        }
        .foregroundStyle(Color(uiColor: appearance.theme.ink))
        .background(Color(uiColor: appearance.theme.paper))
        .presentationBackground(Color(uiColor: appearance.theme.paper))
        .presentationDetents(editing ? [.large] : [.height(contentHeight)])
        .presentationContentInteraction(.scrolls)
        .presentationDragIndicator(editing ? .visible : .hidden)
        .interactiveDismissDisabled(editing)
    }
    private func addMinutes(_ minutes: Int) {
        if let onTimerAddMinutes { onTimerAddMinutes(minutes) } else { store.addMinutes(minutes, to: cellID) }
    }
}

private struct CellEditor: View {
    @ObservedObject var store: SessionStore
    @EnvironmentObject private var appearance: AppearanceStore
    let cellID: String
    let done: () -> Void
    let suggestion: String?
    let cancel: (() -> Void)?
    @State private var draft: CellContent
    @State private var minimum: String
    @State private var maximum: String
    @State private var unit: String
    @State private var approximate: Bool
    @State private var hasDuration: Bool
    @State private var attemptedSave = false
    @State private var saveError: String?
    @FocusState private var focusedField: CellEditField?

    init(store: SessionStore, cellID: String, suggestion: String? = nil, cancel: (() -> Void)? = nil, done: @escaping () -> Void) {
        self.store = store; self.cellID = cellID; self.done = done; self.suggestion = suggestion; self.cancel = cancel
        let value = store.content(for: cellID)
        _draft = State(initialValue: value)
        _minimum = State(initialValue: value.duration.map { $0.min.formatted(.number.grouping(.never)) } ?? "")
        _maximum = State(initialValue: value.duration.flatMap { $0.max == $0.min ? nil : $0.max.formatted(.number.grouping(.never)) } ?? "")
        _unit = State(initialValue: value.duration?.unit ?? "min")
        _approximate = State(initialValue: value.duration?.approximate ?? false)
        _hasDuration = State(initialValue: value.duration != nil)
    }
    private var base: RecipeCell { store.cell(cellID) }
    private var durationInput: DurationInput { DurationInput(minimum: minimum, maximum: maximum, unit: unit, approximate: approximate) }
    private var editedContent: CellContent {
        var content = draft
        if !base.isIngredient { content.duration = hasDuration ? durationInput.value : nil }
        return content
    }
    private var issues: [CellEditIssue] {
        // DurationInput owns duration errors so raw invalid strings are validated too.
        var content = draft
        content.duration = nil
        guard !base.isIngredient && hasDuration else { return content.issues }
        var durationIssues = durationInput.issues
        if minimum.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            durationIssues.removeAll { $0.field == .minimum }
            durationIssues.insert(.init(field: .minimum, message: "Enter a time, or turn Duration off."), at: 0)
        }
        return content.issues + durationIssues
    }
    private func error(for field: CellEditField) -> String? {
        attemptedSave ? issues.first { $0.field == field }?.message : nil
    }
    private func copyHint(for field: CellEditField) -> String? {
        if field == .label && (draft.label.count > 24 || draft.label.split(whereSeparator: \.isWhitespace).count > 3) {
            return "Aim for 1–3 words. Check the preview for wrapping."
        }
        if field == .cue && (draft.cue.count > 40 || draft.cue.split(whereSeparator: \.isWhitespace).count > 6) {
            return "Keep this to one short phrase. Use the full explanation for more detail."
        }
        return nil
    }
    var body: some View {
        ScrollViewReader { scroll in
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text(base.isIngredient ? "Edit ingredient" : "Edit step").themeTitleFont(appearance.theme, size: 30)
                    field(base.isIngredient ? "Ingredient" : "Action", text: $draft.label, key: .label)
                    if base.isIngredient {
                        field("Quantity", text: $draft.quantity, key: .quantity)
                    } else {
                        VStack(alignment: .leading, spacing: 12) {
                            Toggle("Duration", isOn: $hasDuration)
                                .themeFont(appearance.theme, style: .headline, emphasized: true)
                                .accessibilityIdentifier("edit.duration")
                                .onChange(of: hasDuration) { _, enabled in
                                    if !enabled { focusedField = nil }
                                }
                            if hasDuration {
                                Toggle(isOn: $approximate) {
                                    fieldLabel("Approximate time")
                                }.accessibilityIdentifier("edit.approximate")
                                AdaptiveActionRow {
                                    field("Time", text: $minimum, key: .minimum, number: true)
                                    field("To", text: $maximum, key: .maximum, number: true, optional: true)
                                }
                                VStack(alignment: .leading, spacing: 8) {
                                    fieldLabel("Unit")
                                    ThemedSegments(title: "Unit", selection: $unit, options: ["sec", "min", "h"], label: { ["sec": "Seconds", "min": "Minutes", "h": "Hours"][$0]! })
                                    if let message = error(for: .unit) { fieldError(message, key: .unit) }
                                }
                            }
                        }
                        .padding(16)
                        .overlay(RoundedRectangle(cornerRadius: appearance.theme.cornerRadius)
                            .stroke(Color(uiColor: appearance.theme.line), lineWidth: 1))
                        .id(CellEditField.unit)
                    }
                    if let suggestion {
                        Button("Use “\(suggestion)”") { draft.cue = suggestion }
                            .themeFont(appearance.theme, style: .callout).accessibilityIdentifier("edit.suggestion")
                    }
                    field("Short clarification", text: $draft.cue, key: .cue)
                    VStack(alignment: .leading, spacing: 8) {
                        fieldLabel("Full explanation")
                        TextField("Full explanation", text: $draft.instruction, axis: .vertical).lineLimit(4...10)
                            .font(appearance.theme.readingFont).padding(12)
                            .background(Color(uiColor: appearance.theme.surface), in: RoundedRectangle(cornerRadius: appearance.theme.cornerRadius))
                            .overlay(RoundedRectangle(cornerRadius: appearance.theme.cornerRadius).stroke(Color(uiColor: appearance.theme.line), lineWidth: 1))
                            .accessibilityIdentifier("edit.instruction")
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        fieldLabel("Preview")
                        CellPreview(cell: editedContent.applying(to: base), cells: store.graph.order.map { store.cell($0) }, layout: store.layout)
                            .frame(maxWidth: .infinity)
                    }
                }.padding(24)
            }
            .scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                VStack(spacing: 10) {
                    // File-saving failures apply to the edit as a whole, not to an individual field.
                    if let saveError { Text(saveError).themeFont(appearance.theme, style: .callout).accessibilityIdentifier("edit.error") }
                    AdaptiveActionRow {
                        Button("Cancel", action: cancel ?? done).buttonStyle(KitchenButtonStyle()).accessibilityIdentifier("edit.cancel")
                        Button("Save") {
                            attemptedSave = true
                            saveError = nil
                            if let issue = issues.first {
                                focusedField = issue.field
                                scroll.scrollTo(issue.field, anchor: .center)
                                return
                            }
                            do { try store.saveEdit(editedContent, for: cellID); done() }
                            catch { saveError = error.localizedDescription }
                        }.buttonStyle(KitchenButtonStyle(primary: true)).accessibilityIdentifier("edit.save")
                    }
                }.padding(20).background(Color(uiColor: appearance.theme.paper))
            }
        }
        .themeFont(appearance.theme)
        .tint(Color(uiColor: appearance.theme.accent))
    }
    private func fieldLabel(_ label: String, optional: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(label).themeFont(appearance.theme, style: .subheadline, emphasized: true)
            if optional {
                Text("· optional").themeFont(appearance.theme, style: .subheadline)
                    .foregroundStyle(Color(uiColor: appearance.theme.muted))
            }
        }.accessibilityElement(children: .combine)
    }
    private func field(_ label: String, text: Binding<String>, key: CellEditField, number: Bool = false, optional: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            fieldLabel(label, optional: optional)
            TextField(optional ? "\(label) · optional" : label, text: text).keyboardType(number ? .decimalPad : .default)
                .focused($focusedField, equals: key)
                .padding(12).background(Color(uiColor: appearance.theme.surface), in: RoundedRectangle(cornerRadius: appearance.theme.cornerRadius))
                .overlay(RoundedRectangle(cornerRadius: appearance.theme.cornerRadius).stroke(Color(uiColor: error(for: key) == nil ? appearance.theme.line : .systemRed), lineWidth: 1))
                .accessibilityIdentifier("edit.\(key.rawValue)")
                .accessibilityHint(error(for: key) ?? "")
            if let message = error(for: key) { fieldError(message, key: key) }
            else if let hint = copyHint(for: key) {
                Text(hint).themeFont(appearance.theme, style: .caption1).foregroundStyle(Color(uiColor: appearance.theme.muted))
                    .accessibilityIdentifier("edit.\(key.rawValue).hint")
            }
        }.id(key)
    }
    private func fieldError(_ message: String, key: CellEditField) -> some View {
        Label { Text(message) } icon: { Image(systemName: "exclamationmark.circle").foregroundStyle(Color(uiColor: .systemRed)) }
            .themeFont(appearance.theme, style: .caption1)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("edit.\(key.rawValue).error")
    }
}

private struct SteamStroke: Shape {
    let index: Int
    func path(in rect: CGRect) -> Path {
        let points: [[CGPoint]] = [
            [.init(x: 27, y: 28), .init(x: 20, y: 21), .init(x: 32, y: 17), .init(x: 26, y: 9)],
            [.init(x: 39, y: 25), .init(x: 32, y: 18), .init(x: 45, y: 13), .init(x: 38, y: 4)],
            [.init(x: 51, y: 28), .init(x: 44, y: 21), .init(x: 57, y: 17), .init(x: 50, y: 9)]
        ]
        let curve = points[index]
        var path = Path()
        path.move(to: curve[0])
        path.addCurve(to: curve[3], control1: curve[1], control2: curve[2])
        return path.applying(CGAffineTransform(scaleX: rect.width / 76, y: rect.height / 60))
    }
}

private struct ServingPlate: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path(ellipseIn: CGRect(x: 9, y: 34, width: 58, height: 16))
        path.move(to: CGPoint(x: 16, y: 49))
        path.addQuadCurve(to: CGPoint(x: 60, y: 49), control: CGPoint(x: 38, y: 60))
        return path.applying(CGAffineTransform(scaleX: rect.width / 76, y: rect.height / 60))
    }
}

private struct ServingMark: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var revealed = false
    var body: some View {
        ZStack {
            ServingPlate().stroke(style: StrokeStyle(lineWidth: 2.4, lineCap: .round))
            ForEach(0..<3) { index in
                SteamStroke(index: index).trim(from: 0, to: reduceMotion || revealed ? 1 : 0)
                    .stroke(style: StrokeStyle(lineWidth: 2.4, lineCap: .round))
                    .offset(y: reduceMotion || revealed ? 0 : 8)
                    .opacity(reduceMotion || revealed ? 1 : 0)
                    .animation(reduceMotion ? nil : .easeOut(duration: 1.2).delay(Double(index) * 0.14), value: revealed)
            }
        }
        .frame(width: 136, height: 108)
        .accessibilityHidden(true)
        .onAppear { revealed = true }
    }
}

struct CompletionView: View {
    @EnvironmentObject private var appearance: AppearanceStore
    let recipeTitle: String
    let finish: () -> Void
    let cookAgain: () -> Void
    let stay: () -> Void
    var walkthrough = false
    @State private var contentHeight: CGFloat = 420
    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                VStack(spacing: 12) {
                    ServingMark().foregroundStyle(Color(uiColor: appearance.theme.glow))
                    VStack(spacing: 6) {
                        Text(recipeTitle).themeTitleFont(appearance.theme, size: 24)
                            .foregroundStyle(Color(uiColor: appearance.theme.muted))
                        Text(appearance.theme.title("Ready to serve")).themeTitleFont(appearance.theme, size: 30)
                            .accessibilityIdentifier("recipe.finished")
                    }.multilineTextAlignment(.center)
                }.frame(maxWidth: .infinity)
                if walkthrough {
                    VStack(spacing: 4) {
                        Text("Find this walkthrough anytime in:")
                        Text("Recipe Book → … → Walkthrough.")
                    }.themeFont(appearance.theme, style: .callout).multilineTextAlignment(.center)
                }
                VStack(spacing: 10) {
                    Button("Finish", action: finish).buttonStyle(KitchenButtonStyle(primary: true)).accessibilityIdentifier("recipe.finish")
                    if walkthrough {
                        Button("Start again", action: cookAgain).buttonStyle(KitchenButtonStyle()).accessibilityIdentifier("recipe.again")
                        Button("Back", action: stay).buttonStyle(KitchenButtonStyle()).accessibilityIdentifier("recipe.back")
                    } else {
                        Button("Cook again", action: cookAgain).buttonStyle(KitchenButtonStyle()).accessibilityIdentifier("recipe.again")
                        Button("Stay", action: stay).buttonStyle(KitchenButtonStyle()).accessibilityIdentifier("recipe.stay")
                    }
                }
            }
            .padding(.horizontal, 24).padding(.top, 24).padding(.bottom, 20)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = ceil($0) }
        }
        .scrollBounceBehavior(.basedOnSize)
        .foregroundStyle(Color(uiColor: appearance.theme.ink))
        .background(Color(uiColor: appearance.theme.paper))
        .presentationBackground(Color(uiColor: appearance.theme.paper))
        // One content-sized stop; scrolling remains available for accessibility sizes or landscape.
        .presentationDetents([.height(contentHeight)])
        .presentationContentInteraction(.scrolls)
        .presentationDragIndicator(.hidden)
        .interactiveDismissDisabled(walkthrough)
    }
}
