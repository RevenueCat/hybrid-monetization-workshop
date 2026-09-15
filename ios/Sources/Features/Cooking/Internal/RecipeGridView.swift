import SwiftUI
import UIKit
import CoreText

struct RecipeGridView: UIViewControllerRepresentable {
    @EnvironmentObject private var appearance: AppearanceStore
    @Environment(\.gridDensityOverride) private var gridDensityOverride
    @Binding var titleFirstLineCenter: CGFloat
    @ObservedObject var store: SessionStore
    var showDetails: (RecipeCell) -> Void
    var backToRecipes: () -> Void
    var safeInsets: UIEdgeInsets
    var onCellTap: ((String) -> Void)? = nil
    var automaticallyCenters = true
    var showsNavigation = true
    var pinsHeader = false
    var onHeaderBottomChange: ((CGFloat) -> Void)? = nil
    var focusTopInset: CGFloat = 0
    var focusBottomInset: CGFloat = 0

    func makeUIViewController(context: Context) -> RecipeGridController {
        let view = RecipeScrollView(store: store, showDetails: showDetails, backToRecipes: backToRecipes, safeInsets: safeInsets, theme: appearance.theme, density: gridDensityOverride ?? appearance.density)
        view.onCellTap = onCellTap
        view.automaticallyCenters = automaticallyCenters
        view.showsNavigation = showsNavigation
        view.pinsHeader = pinsHeader
        view.onTitleFirstLineCenterChange = { titleFirstLineCenter = $0 }
        view.onHeaderBottomChange = onHeaderBottomChange
        view.focusTopInset = focusTopInset
        view.focusBottomInset = focusBottomInset
        return RecipeGridController(scrollView: view)
    }
    static func dismantleUIViewController(_ controller: RecipeGridController, coordinator: ()) {
        let view = controller.scrollView
        view.cancelEntryCentering()
        // Capture even an in-flight scroll when navigating back to the book.
        view.store.recordScroll(x: Double(max(0, view.contentOffset.x)), y: Double(max(0, view.contentOffset.y)))
    }
    func updateUIViewController(_ controller: RecipeGridController, context: Context) {
        let view = controller.scrollView
        view.onCellTap = onCellTap
        view.automaticallyCenters = automaticallyCenters
        view.showsNavigation = showsNavigation
        view.pinsHeader = pinsHeader
        view.onTitleFirstLineCenterChange = { titleFirstLineCenter = $0 }
        view.onHeaderBottomChange = onHeaderBottomChange
        view.focusTopInset = focusTopInset
        view.focusBottomInset = focusBottomInset
        view.showDetails = showDetails
        view.backToRecipes = backToRecipes
        view.readableInsets = safeInsets
        view.density = gridDensityOverride ?? appearance.density
        view.applyTheme(appearance.theme)
        view.refresh()
    }
}

final class RecipeGridController: UIViewController {
    let scrollView: RecipeScrollView

    init(scrollView: RecipeScrollView) {
        self.scrollView = scrollView
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    override func loadView() { view = scrollView }
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // Begin the pause after the navigation transition, not during layout.
        scrollView.scheduleEntryCentering()
    }
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        scrollView.cancelEntryCentering()
    }
}

// Observe the first touch without recognizing a gesture or delaying cell taps/holds.
private final class EntryTouchObserver: UIGestureRecognizer {
    var onTouch: (() -> Void)?
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        state = .failed
        onTouch?()
    }
}

enum GridCellTextLayout {
    struct Line {
        let text: String
        let font: UIFont
        let completedFont: UIFont
        let width: CGFloat
        let height: CGFloat
        let secondary: Bool
    }
    static func lines(cell: RecipeCell, theme: AppTheme, width: CGFloat, traits: UITraitCollection, amountOverride: String? = nil) -> [Line] {
        let baseSize: CGFloat = theme.cellSize
        let cue = cell.cue
        let parts: [(String?, CGFloat, Bool)] = [(cell.label, baseSize, false), (amountOverride ?? cell.amount, baseSize - 2, true), (cue, baseSize - 2, true)]
            + cell.inputReferences.map { (Optional($0), baseSize - 2, true) }
        var result: [Line] = []
        for (text, size, secondary) in parts {
            guard let text, !text.isEmpty else { continue }
            let font = theme.cellFont(size: size, secondary: secondary, traits: traits)
            let completedFont = theme.cellFont(size: size, completed: true, secondary: secondary, traits: traits)
            let attributed = NSAttributedString(string: text, attributes: [.font: font])
            let typesetter = CTTypesetterCreateWithAttributedString(attributed)
            let string = text as NSString
            var offset = 0
            if !result.isEmpty { result.append(Line(text: "", font: font, completedFont: completedFont, width: 0, height: 5, secondary: true)) }
            while offset < string.length {
                let length = max(1, CTTypesetterSuggestLineBreak(typesetter, offset, Double(max(1, width))))
                let line = string.substring(with: NSRange(location: offset, length: min(length, string.length - offset))).trimmingCharacters(in: .whitespacesAndNewlines)
                result.append(Line(text: line, font: font, completedFont: completedFont, width: (line as NSString).size(withAttributes: [.font: font]).width, height: ceil(font.lineHeight), secondary: secondary))
                offset += length
            }
        }
        return result
    }

    static func requiredHeight(cell: RecipeCell, theme: AppTheme, width: CGFloat, traits: UITraitCollection) -> CGFloat {
        lines(cell: cell, theme: theme, width: width - 24, traits: traits).reduce(28) { $0 + $1.height }
    }

}

final class GridCellButton: UIButton {
    var cell: RecipeCell
    var theme: AppTheme = .original
    var progressState: CellState = .pending
    var current = false
    var drawsRightBorder = false
    var drawsBottomBorder = false
    var density: GridDensity = .compact
    var timer: TimerPresentation?
    var onTap: (() -> Void)?
    var onDetails: (() -> Void)?
    private var didHold = false
    private let timerGlowLayer = CAShapeLayer()

    var timerGlowIsVisible: Bool { !timerGlowLayer.isHidden }
    var timerGlowIsBreathing: Bool { timerGlowLayer.animation(forKey: "timerBreathing") != nil }
    var timerGlowLineWidth: CGFloat { timerGlowLayer.lineWidth }
    var timerGlowOutlineBounds: CGRect { timerGlowLayer.path?.boundingBoxOfPath ?? .zero }

    init(cell: RecipeCell) {
        self.cell = cell
        super.init(frame: .zero)
        isOpaque = true
        contentMode = .redraw
        timerGlowLayer.fillColor = UIColor.clear.cgColor
        timerGlowLayer.lineJoin = .round
        timerGlowLayer.zPosition = 1
        timerGlowLayer.isHidden = true
        layer.addSublayer(timerGlowLayer)
        accessibilityIdentifier = "cell.\(cell.id)"
        isAccessibilityElement = true
        addTarget(self, action: #selector(touchDown), for: .touchDown)
        addTarget(self, action: #selector(tapped), for: .touchUpInside)
        let hold = UILongPressGestureRecognizer(target: self, action: #selector(longPressed(_:)))
        hold.minimumPressDuration = 0.55
        hold.allowableMovement = 12
        addGestureRecognizer(hold)
        accessibilityCustomActions = [UIAccessibilityCustomAction(name: "Show details and edit", target: self, selector: #selector(accessibleDetails))]
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    @objc private func touchDown() { didHold = false }
    @objc private func tapped() { if !didHold { onTap?() } }
    @objc private func longPressed(_ gesture: UILongPressGestureRecognizer) {
        if gesture.state == .began { didHold = true; onDetails?() }
    }
    @objc private func accessibleDetails() -> Bool { onDetails?(); return true }

    func update(state: CellState, current: Bool, density: GridDensity, timer: TimerPresentation? = nil) {
        self.progressState = state; self.current = current; self.density = density; self.timer = timer
        accessibilityLabel = ([cell.label, cell.amount, cell.cue].compactMap { $0 } + cell.inputReferences).joined(separator: ", ")
        accessibilityValue = [progressState.rawValue, timer?.accessibilityText, current ? "current" : nil].compactMap { $0 }.joined(separator: ", ")
        switch progressState {
        case .pending: accessibilityHint = cell.amount == nil ? "Tap to complete with prerequisites. Hold for details." : "Tap to start timer. Hold for details."
        case .running: accessibilityHint = "Tap to complete. Hold to adjust the timer."
        default: accessibilityHint = "Tap to unmark with dependent steps. Hold for details."
        }
        accessibilityTraits = progressState == .complete ? [.button, .selected] : [.button]
        updateTimerGlow()
        setNeedsDisplay()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        timerGlowLayer.frame = bounds
        // Place the outer edge of the stroke flush with all four cell edges.
        // A fixed inset leaves a gap and changes alignment as the stroke thickens.
        let inset = timerGlowLayer.lineWidth / 2
        let outline = UIBezierPath(rect: timerGlowLayer.bounds.insetBy(dx: inset, dy: inset)).cgPath
        timerGlowLayer.path = outline
        timerGlowLayer.shadowPath = outline
        CATransaction.commit()
    }

    private func updateTimerGlow() {
        let isRunning = progressState == .running && timer != nil
        guard isRunning else {
            timerGlowLayer.removeAnimation(forKey: "timerBreathing")
            timerGlowLayer.isHidden = true
            return
        }

        let needsAttention = timer?.needsAttention == true
        let accent = theme.accent.resolvedColor(with: traitCollection)
        let glow = theme.glow.resolvedColor(with: traitCollection)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        timerGlowLayer.isHidden = false
        timerGlowLayer.strokeColor = accent.cgColor
        timerGlowLayer.lineWidth = needsAttention ? 3 : 2
        timerGlowLayer.opacity = needsAttention ? 1 : 0.78
        timerGlowLayer.shadowColor = glow.cgColor
        timerGlowLayer.shadowOffset = .zero
        timerGlowLayer.shadowRadius = needsAttention ? 9 : 5
        timerGlowLayer.shadowOpacity = needsAttention ? 0.7 : 0.38
        CATransaction.commit()
        setNeedsLayout()

        guard !needsAttention, !UIAccessibility.isReduceMotionEnabled else {
            timerGlowLayer.removeAnimation(forKey: "timerBreathing")
            return
        }
        guard timerGlowLayer.animation(forKey: "timerBreathing") == nil else { return }

        let opacity = CABasicAnimation(keyPath: "opacity")
        opacity.fromValue = 0.45
        opacity.toValue = 0.9
        let shadow = CABasicAnimation(keyPath: "shadowOpacity")
        shadow.fromValue = 0.18
        shadow.toValue = 0.52
        let breathing = CAAnimationGroup()
        breathing.animations = [opacity, shadow]
        breathing.duration = 0.9
        breathing.autoreverses = true
        breathing.repeatCount = .infinity
        breathing.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        timerGlowLayer.add(breathing, forKey: "timerBreathing")
    }

    private func lines(width: CGFloat) -> [GridCellTextLayout.Line] {
        GridCellTextLayout.lines(cell: cell, theme: theme, width: width, traits: traitCollection, amountOverride: timer?.text)
    }
    func requiredHeight(width: CGFloat) -> CGFloat {
        GridCellTextLayout.requiredHeight(cell: cell, theme: theme, width: width, traits: traitCollection)
    }

    var focusPoint: CGPoint {
        CGPoint(x: cell.isIngredient ? min(bounds.width / 2, 66) : bounds.midX, y: bounds.midY)
    }

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        (progressState == .complete ? theme.done : current && timer == nil ? theme.active : theme.surface).setFill()
        context.fill(bounds)
        if let timer {
            context.saveGState()
            context.clip(to: bounds)
            theme.active.withAlphaComponent(0.72).setFill()
            context.fill(CGRect(x: 0, y: 0, width: bounds.width * timer.progress, height: bounds.height))
            context.restoreGState()
        }
        if current {
            context.saveGState()
            context.clip(to: bounds)
            // Cast a glow inward from outside the cell. The source outline is
            // clipped away, leaving the shared grid border as the only hard edge.
            context.setShadow(offset: .zero, blur: 12, color: theme.glow.withAlphaComponent(0.6).resolvedColor(with: traitCollection).cgColor)
            theme.glow.setStroke()
            context.setLineWidth(4)
            context.stroke(bounds.insetBy(dx: -3, dy: -3))
            context.restoreGState()
        }
        // Each cell owns its top and left edges; only perimeter cells own the
        // bottom and right edges. Shared borders stay one point wide.
        theme.line.setFill()
        context.fill(CGRect(x: 0, y: 0, width: bounds.width, height: 1))
        context.fill(CGRect(x: 0, y: 0, width: 1, height: bounds.height))
        if drawsRightBorder { context.fill(CGRect(x: bounds.width - 1, y: 0, width: 1, height: bounds.height)) }
        if drawsBottomBorder { context.fill(CGRect(x: 0, y: bounds.height - 1, width: bounds.width, height: 1)) }
        theme.line.setStroke()
        context.setLineWidth(1)

        let lines = lines(width: bounds.width - 24)
        var y = max(14, (bounds.height - lines.reduce(0) { $0 + $1.height }) / 2)
        for line in lines {
            // Break and anchor at medium weight; drawing regular never changes geometry.
            let font = progressState == .complete ? line.completedFont : line.font
            let x = cell.isIngredient ? 12 : (bounds.width - line.width) / 2
            let color = line.secondary || progressState == .complete ? theme.muted : theme.ink
            (line.text as NSString).draw(
                at: CGPoint(x: x, y: y),
                withAttributes: theme.textDrawingAttributes(font: font, color: color)
            )
            y += line.height
        }
    }
}

/// Empty space without cooking semantics.
private final class NeutralRecipeRegionView: UIView {
    var theme: AppTheme = .original
    var drawsRightBorder = false
    var drawsBottomBorder = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        isOpaque = true
        contentMode = .redraw
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        theme.paper.setFill(); context.fill(bounds)
        theme.line.setFill()
        context.fill(CGRect(x: 0, y: 0, width: bounds.width, height: 1))
        context.fill(CGRect(x: 0, y: 0, width: 1, height: bounds.height))
        if drawsRightBorder { context.fill(CGRect(x: bounds.width - 1, y: 0, width: 1, height: bounds.height)) }
        if drawsBottomBorder { context.fill(CGRect(x: 0, y: bounds.height - 1, width: bounds.width, height: 1)) }

    }
}

final class RecipeScrollView: UIScrollView, UIScrollViewDelegate {
    let store: SessionStore
    private(set) var theme: AppTheme
    var density: GridDensity
    private var priorContentRevision = -1
    var onTitleFirstLineCenterChange: ((CGFloat) -> Void)?
    var onHeaderBottomChange: ((CGFloat) -> Void)?
    var focusTopInset: CGFloat = 0
    var focusBottomInset: CGFloat = 0
    private var reportedHeaderBottom: CGFloat = 0
    private var restingTitleCenter: CGFloat = 60
    private var restingHeaderBottom: CGFloat = 84
    private var reportedTitleFirstLineCenter: CGFloat = 0
    var showDetails: (RecipeCell) -> Void
    var backToRecipes: () -> Void
    var readableInsets: UIEdgeInsets { didSet { if oldValue != readableInsets { priorSize = .zero; setNeedsLayout() } } }
    private let topFade = ScrollEdgeFade(top: true)
    private let bottomFade = ScrollEdgeFade(top: false)
    private let canvas = UIView()
    var onCellTap: ((String) -> Void)?
    var automaticallyCenters = true
    var showsNavigation = true { didSet { headingButton.isHidden = !showsNavigation } }
    var pinsHeader = false {
        didSet {
            guard pinsHeader != oldValue else { return }
            if pinsHeader {
                addSubview(headingButton)
                insertSubview(headerBackdrop, belowSubview: headingButton)
            } else {
                canvas.addSubview(headingButton)
            }
            headerBackdrop.isHidden = !pinsHeader
            reportHeaderPosition()
        }
    }
    private let headerBackdrop = UIView()
    private let pageLeadingInset: CGFloat = 24
    private let sweep = CAGradientLayer()
    private let sweepContainer = CALayer()
    private var lastCelebrationID: UUID?
    private var tableBounds = CGRect.zero
    private var buttons: [String: GridCellButton] = [:]
    private var continuationButtons: [String: GridCellButton] = [:]
    private var neutralViews: [String: NeutralRecipeRegionView] = [:]
    private let recipeHeading = UIStackView()
    private let headingButton = UIButton(type: .custom)
    private var visibilityReport = 0
    private let titleLabel = UILabel()
    private let brandLabel = UILabel()
    private var priorSize = CGSize.zero
    private var priorDensity: GridDensity?
    private var priorCategory: UIContentSizeCategory?
    private var restored = false
    private let entryScrollPosition: CGPoint
    private var entryCanCenter = true
    private var entryTask: Task<Void, Never>?
    private let entryTouchObserver = EntryTouchObserver()
    private var lastFocusRequest = 0
    private var lastExplicitFocusRequest = 0
    private var xStops: [CGFloat] = []
    private var yStops: [CGFloat] = []
    private var dragOrigin = CGPoint.zero

    init(store: SessionStore, showDetails: @escaping (RecipeCell) -> Void, backToRecipes: @escaping () -> Void, safeInsets: UIEdgeInsets, theme: AppTheme, density: GridDensity) {
        self.store = store; self.showDetails = showDetails; self.backToRecipes = backToRecipes
        self.readableInsets = safeInsets
        self.theme = theme
        self.density = density
        self.entryScrollPosition = CGPoint(x: store.session.scrollX, y: store.session.scrollY)
        super.init(frame: .zero)
        entryTouchObserver.cancelsTouchesInView = false
        entryTouchObserver.delaysTouchesBegan = false
        entryTouchObserver.delaysTouchesEnded = false
        entryTouchObserver.onTouch = { [weak self] in self?.cancelEntryCentering() }
        NotificationCenter.default.addObserver(self, selector: #selector(cancelEntryCentering), name: UIApplication.willResignActiveNotification, object: nil)
        delegate = self
        backgroundColor = theme.paper
        contentInsetAdjustmentBehavior = .never
        isDirectionalLockEnabled = true
        decelerationRate = .fast
        alwaysBounceVertical = true
        accessibilityIdentifier = "recipe.grid"
        addSubview(canvas)
        canvas.backgroundColor = theme.paper
        recipeHeading.axis = .vertical
        brandLabel.numberOfLines = 0
        applyHeadingTypography()
        titleLabel.numberOfLines = 0
        titleLabel.accessibilityIdentifier = "recipe.title"
        for label in [brandLabel, titleLabel] {
            label.adjustsFontForContentSizeCategory = true
            recipeHeading.addArrangedSubview(label)
        }
        recipeHeading.isUserInteractionEnabled = false
        headingButton.addSubview(recipeHeading)
        headingButton.isAccessibilityElement = true
        headingButton.accessibilityLabel = "Kitchen Table, \(store.graph.recipe.title)"
        headingButton.accessibilityHint = "Back to recipes"
        headingButton.accessibilityIdentifier = "navigation.recipes"
        headingButton.addTarget(self, action: #selector(openRecipeBook), for: .touchUpInside)
        canvas.addSubview(headingButton)
        for placement in store.layout.placements {
            let cell = store.cell(placement.id)
            let button = GridCellButton(cell: cell)
            button.theme = theme
            button.drawsRightBorder = placement.column + placement.columns == store.layout.columnWidths.count
            button.drawsBottomBorder = placement.row + placement.rows == store.layout.rowCount
            button.onTap = { [weak self] in
                guard let self else { return }
                if let onCellTap = self.onCellTap { onCellTap(cell.id) } else { self.store.toggle(cell.id) }
            }
            button.onDetails = { [weak self] in guard let self else { return }; self.showDetails(self.store.cell(cell.id)) }
            buttons[cell.id] = button
            canvas.addSubview(button)
        }
        for lane in store.layout.continuations {
            let button = GridCellButton(cell: lane.displayCell(targetLabel: store.cell(lane.targetID).label))
            button.accessibilityIdentifier = lane.id
            button.drawsRightBorder = lane.region.column + lane.region.columns == store.layout.columnWidths.count
            button.drawsBottomBorder = lane.region.row + lane.region.rows == store.layout.rowCount
            button.onTap = { [weak self] in
                guard let self else { return }
                if let onCellTap = self.onCellTap { onCellTap(lane.sourceID) } else { self.store.toggle(lane.sourceID) }
            }
            button.onDetails = { [weak self] in guard let self else { return }; self.showDetails(self.store.cell(lane.sourceID)) }
            continuationButtons[lane.id] = button
            canvas.addSubview(button)
        }
        for region in store.layout.fillers {
            let view = NeutralRecipeRegionView(frame: .zero)
            view.drawsRightBorder = region.column + region.columns == store.layout.columnWidths.count
            view.drawsBottomBorder = region.row + region.rows == store.layout.rowCount
            neutralViews[region.id] = view
            canvas.addSubview(view)
        }
        registerForTraitChanges([UITraitPreferredContentSizeCategory.self, UITraitUserInterfaceStyle.self]) { (view: RecipeScrollView, _: UITraitCollection) in
            view.applyHeadingTypography()
            view.priorCategory = nil
            view.setNeedsLayout()
            view.buttons.values.forEach { $0.setNeedsDisplay() }
        }
        sweepContainer.masksToBounds = true
        layer.addSublayer(sweepContainer)
        sweepContainer.addSublayer(sweep)
        sweep.startPoint = CGPoint(x: 0, y: 0.3)
        sweep.endPoint = CGPoint(x: 1, y: 0.7)
        sweep.locations = [0, 0.4, 0.5, 0.6, 1]
        sweep.isHidden = true
        addSubview(topFade)
        addSubview(bottomFade)
        topFade.theme = theme; bottomFade.theme = theme
        // The heading is shown first; the controller schedules centering after entry.
        lastFocusRequest = store.focusRequest
        refresh()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    @objc private func openRecipeBook() { backToRecipes() }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        store.setTimerDisplayActive(window != nil)
        if let window, entryCanCenter {
            // Also observe touches on the SwiftUI controls outside the scroll view.
            window.addGestureRecognizer(entryTouchObserver)
        } else if window == nil {
            cancelEntryCentering()
        }
    }

    func scheduleEntryCentering() {
        guard automaticallyCenters, entryCanCenter, entryTask == nil else { return }
        layoutIfNeeded()
        let pause = !UIAccessibility.isReduceMotionEnabled
        entryTask = Task { @MainActor [weak self] in
            if pause {
                do { try await Task.sleep(for: .milliseconds(200)) } catch { return }
            }
            guard !Task.isCancelled, let self, self.entryCanCenter,
                  self.window != nil, !self.isTracking, !self.isDragging else { return }
            self.entryTask = nil
            self.cancelEntryCentering()
            self.layoutIfNeeded()
            // A completed recipe has no current cell: restore its last resting position.
            self.moveTo(self.currentTargetOffset() ?? self.clamped(self.entryScrollPosition))
        }
    }

    @objc func cancelEntryCentering() {
        entryCanCenter = false
        entryTask?.cancel()
        entryTask = nil
        entryTouchObserver.view?.removeGestureRecognizer(entryTouchObserver)
    }

    func applyTheme(_ newTheme: AppTheme) {
        guard theme != newTheme else { return }
        theme = newTheme
        backgroundColor = theme.paper; canvas.backgroundColor = theme.paper
        applyHeadingTypography()
        topFade.theme = theme; bottomFade.theme = theme
        priorCategory = nil
        setNeedsLayout()
    }

    private func applyHeadingTypography() {
        let style = PageHeadingStyle(theme: theme, traits: traitCollection)
        recipeHeading.spacing = style.spacing
        brandLabel.font = style.brandFont
        brandLabel.attributedText = NSAttributedString(
            string: PageHeadingStyle.brand,
            attributes: style.brandAttributes(underlined: true)
        )
        titleLabel.font = style.titleFont
        titleLabel.attributedText = NSAttributedString(
            string: theme.title(store.graph.recipe.title),
            attributes: style.titleAttributes()
        )
    }

    func refresh() {
        if priorContentRevision != store.contentRevision {
            priorContentRevision = store.contentRevision
            priorCategory = nil
            setNeedsLayout()
        }
        for (id, button) in buttons {
            button.isAccessibilityElement = true
            button.cell = store.cell(id)
            button.theme = theme
            button.update(state: store.session.progress.states[id] ?? .pending, current: id == store.session.progress.current,
                          density: density, timer: store.timerPresentation(for: id))
        }
        for view in neutralViews.values { view.theme = theme; view.setNeedsDisplay() }
        for lane in store.layout.continuations {
            let button = continuationButtons[lane.id]!
            button.cell = lane.displayCell(targetLabel: store.cell(lane.targetID).label)
            button.theme = theme
            button.update(state: store.session.progress.states[lane.sourceID] ?? .pending,
                          current: lane.sourceID == store.session.progress.current,
                          density: density, timer: store.timerPresentation(for: lane.sourceID))
            button.accessibilityLabel = "\(lane.text), shared with \(store.cell(lane.sourceID).label)"
            button.accessibilityHint = "Tap to update both this cell and \(store.cell(lane.sourceID).label). Hold for step details."
        }
        if priorDensity != density { setNeedsLayout() }
        if lastFocusRequest != store.focusRequest {
            let explicitlyRequested = lastExplicitFocusRequest != store.explicitFocusRequest
            lastExplicitFocusRequest = store.explicitFocusRequest
            lastFocusRequest = store.focusRequest
            cancelEntryCentering()
            if automaticallyCenters || explicitlyRequested { DispatchQueue.main.async { [weak self] in self?.layoutIfNeeded(); self?.centerCurrent() } }
        }
        if lastCelebrationID != store.celebrationID {
            lastCelebrationID = store.celebrationID
            sweep.removeAllAnimations()
            sweep.isHidden = true
            if store.celebrationID != nil && !UIAccessibility.isReduceMotionEnabled {
                layoutIfNeeded()
                positionSweep()
                let color = theme.glow.resolvedColor(with: traitCollection)
                sweep.colors = [UIColor.clear.cgColor, color.withAlphaComponent(0.08).cgColor, color.withAlphaComponent(0.30).cgColor, color.withAlphaComponent(0.08).cgColor, UIColor.clear.cgColor]
                sweep.isHidden = false
                let animation = CABasicAnimation(keyPath: "transform.translation.x")
                animation.fromValue = -sweepContainer.bounds.width
                animation.toValue = sweepContainer.bounds.width
                animation.duration = 0.95
                animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                sweep.transform = CATransform3DMakeTranslation(sweepContainer.bounds.width, 0, 0)
                sweep.add(animation, forKey: "finish")
            }
        }
        reportVisibility()
    }

    private func positionSweep() {
        let visible = tableBounds.intersection(bounds)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        sweepContainer.frame = visible.isNull ? .zero : visible
        sweep.bounds = sweepContainer.bounds
        sweep.position = CGPoint(x: sweepContainer.bounds.midX, y: sweepContainer.bounds.midY)
        CATransaction.commit()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.width > 0, bounds.height > 0 else { return }
        if priorSize != bounds.size || priorDensity != density || priorCategory != traitCollection.preferredContentSizeCategory {
            priorSize = bounds.size; priorDensity = density; priorCategory = traitCollection.preferredContentSizeCategory
            arrangeGrid()
        }
        if !restored {
            restored = true
            setContentOffset(.zero, animated: false)
        }
        positionEdgeFades()
        reportVisibility()
    }

    private func arrangeGrid() {
        let minimumTableWidth = store.layout.fillsAvailableWidth ? max(0, bounds.width - pageLeadingInset - 12) : nil
        let geometry = RecipeGridGeometry(cells: store.graph.order.map { store.cell($0) }, layout: store.layout, theme: theme, density: density, traits: traitCollection, minimumWidth: minimumTableWidth)
        // 24-point outer margins, 16-point separation, and a reserved 48-point control.
        let titleWidth = max(1, bounds.width - pageLeadingInset - 88)
        let titleHeight = recipeHeading.systemLayoutSizeFitting(CGSize(width: titleWidth, height: 0), withHorizontalFittingPriority: .required, verticalFittingPriority: .fittingSizeLevel).height
        let headingButtonHeight = max(48, titleHeight)
        headingButton.frame = CGRect(x: contentOffset.x + pageLeadingInset, y: readableInsets.top + 20, width: titleWidth, height: headingButtonHeight)
        recipeHeading.frame = CGRect(x: 0, y: (headingButtonHeight - titleHeight) / 2, width: titleWidth, height: titleHeight)
        recipeHeading.layoutIfNeeded()
        // Relative to the safe area, independent of scroll offset and wrapped title height.
        let firstLineCenter = 20 + recipeHeading.frame.minY + titleLabel.frame.minY + titleLabel.font.lineHeight / 2
        restingTitleCenter = firstLineCenter
        let headerBottom = max(20 + headingButtonHeight, firstLineCenter + 24)
        restingHeaderBottom = headerBottom
        reportHeaderPosition()
        let tableTop = readableInsets.top + headerBottom + 20
        canvas.frame = CGRect(x: 0, y: 0, width: geometry.size.width + pageLeadingInset + 12, height: tableTop + geometry.size.height + readableInsets.bottom + 24)
        contentSize = canvas.bounds.size
        tableBounds = CGRect(origin: CGPoint(x: pageLeadingInset, y: tableTop), size: geometry.size)
        positionSweep()
        for placement in store.layout.placements {
            buttons[placement.id]!.frame = geometry.frames[placement.id]!.offsetBy(dx: pageLeadingInset, dy: tableTop)
        }
        for (id, view) in neutralViews {
            view.frame = geometry.frames[id]!.offsetBy(dx: pageLeadingInset, dy: tableTop)
        }
        for (id, button) in continuationButtons {
            button.frame = geometry.frames[id]!.offsetBy(dx: pageLeadingInset, dy: tableTop)
        }
        let accessibleRegions = (store.layout.placements + store.layout.continuations.map(\.region)).sorted {
            $0.row == $1.row ? $0.column < $1.column : $0.row < $1.row
        }
        canvas.accessibilityElements = (pinsHeader ? [] : [headingButton]) + accessibleRegions.compactMap {
            (buttons[$0.id] as UIView?) ?? continuationButtons[$0.id]
        }
        // Snapped columns share the title's leading edge; free scrolling still uses the full screen.
        xStops = geometry.columnEdges
        yStops = [0] + geometry.rowEdges.dropFirst().map { max(0, tableTop + $0 - 50) }
    }

    private func clamped(_ point: CGPoint) -> CGPoint {
        CGPoint(x: max(0, min(point.x, contentSize.width - bounds.width)), y: max(0, min(point.y, contentSize.height - bounds.height)))
    }

    private func currentPoint() -> CGPoint? {
        guard let id = store.focusTargetID, let button = buttons[id] else { return nil }
        return CGPoint(x: button.frame.minX + button.focusPoint.x, y: button.frame.minY + button.focusPoint.y)
    }

    private func currentTargetOffset() -> CGPoint? {
        guard let point = currentPoint() else { return nil }
        let top = readableInsets.top + focusTopInset
        let bottom = max(top, bounds.height - readableInsets.bottom - focusBottomInset)
        let readableCenterY = (top + bottom) / 2
        return clamped(CGPoint(x: point.x - bounds.width / 2, y: point.y - readableCenterY))
    }

    func centerCurrent() {
        cancelEntryCentering()
        guard let target = currentTargetOffset() else {
            store.isCenteringCurrent = false
            return
        }
        moveTo(target)
    }

    private func moveTo(_ target: CGPoint) {
        let animated = !UIAccessibility.isReduceMotionEnabled && target != contentOffset
        store.isCenteringCurrent = animated
        setContentOffset(target, animated: animated)
        // No animation callback is sent for an immediate or already-reached target.
        if !animated { persistPosition() }
        reportVisibility()
    }

    private func positionEdgeFades() {
        topFade.frame = CGRect(x: bounds.minX, y: bounds.minY, width: bounds.width, height: readableInsets.top + 20)
        bottomFade.frame = CGRect(x: bounds.minX, y: bounds.maxY - readableInsets.bottom - 12, width: bounds.width, height: readableInsets.bottom + 12)
    }

    private func reportHeaderPosition() {
        headingButton.frame.origin.x = contentOffset.x + pageLeadingInset
        headingButton.frame.origin.y = readableInsets.top + 20 + (pinsHeader ? contentOffset.y : 0)
        headerBackdrop.isUserInteractionEnabled = false
        headerBackdrop.backgroundColor = theme.paper
        headerBackdrop.frame = CGRect(x: bounds.minX, y: bounds.minY, width: bounds.width,
                                      height: readableInsets.top + restingHeaderBottom + 12)
        // Follow the title initially, then settle into a compact fixed utility position.
        let offset = pinsHeader ? 0 : contentOffset.y
        let center = max(24, restingTitleCenter - offset)
        let bottom = max(center + 24, restingHeaderBottom - offset)
        guard center != reportedTitleFirstLineCenter || bottom != reportedHeaderBottom else { return }
        reportedTitleFirstLineCenter = center
        reportedHeaderBottom = bottom
        DispatchQueue.main.async { [weak self] in
            guard let self, self.reportedTitleFirstLineCenter == center, self.reportedHeaderBottom == bottom else { return }
            self.onTitleFirstLineCenterChange?(center)
            self.onHeaderBottomChange?(bottom)
        }
    }

    private func reportVisibility() {
        guard bounds.width > 0, bounds.height > 0 else { return }
        // A little hysteresis prevents flickering near the tolerance boundary.
        // Compare reachable scroll positions so edge cells can also be centered.
        let tolerance: CGFloat = store.currentIsCentered ? 0.18 : 0.12
        let offset = clamped(contentOffset)
        let centered = currentTargetOffset().map {
            abs(offset.x - $0.x) <= bounds.width * tolerance &&
            abs(offset.y - $0.y) <= bounds.height * tolerance
        } ?? true
        visibilityReport += 1
        let report = visibilityReport
        if store.currentIsCentered != centered {
            DispatchQueue.main.async { [weak self] in
                guard let self, self.visibilityReport == report else { return }
                self.store.currentIsCentered = centered
            }
        }
    }
    private func persistPosition() { store.recordScroll(x: Double(max(0, contentOffset.x)), y: Double(max(0, contentOffset.y))) }
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        // The title follows vertical scrolling, while horizontal movement belongs to the table.
        headingButton.frame.origin.x = contentOffset.x + pageLeadingInset
        reportHeaderPosition()
        positionEdgeFades()
        positionSweep()
        reportVisibility()
    }
    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        cancelEntryCentering()
        dragOrigin = contentOffset
        store.isCenteringCurrent = false
    }
    func scrollViewWillEndDragging(_ scrollView: UIScrollView, withVelocity velocity: CGPoint, targetContentOffset target: UnsafeMutablePointer<CGPoint>) {
        let proposed = target.pointee
        func nearest(_ value: CGFloat, stops: [CGFloat], maximum: CGFloat) -> CGFloat {
            stops.map { min($0, max(0, maximum)) }.min { abs($0 - value) < abs($1 - value) } ?? value
        }
        if abs(proposed.x - dragOrigin.x) > 20 { target.pointee.x = nearest(proposed.x, stops: xStops, maximum: contentSize.width - bounds.width) }
        if abs(proposed.y - dragOrigin.y) > 20 { target.pointee.y = nearest(proposed.y, stops: yStops, maximum: contentSize.height - bounds.height) }
    }
    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) { persistPosition() }
    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) { if !decelerate { persistPosition() } }
    func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) {
        store.isCenteringCurrent = false
        persistPosition()
        reportVisibility()
    }
}

// A masked system material softens the safe-area boundary without obscuring controls.
private final class ScrollEdgeFade: UIView {
    var theme: AppTheme = .original { didSet { refreshMaterial() } }
    private let blur = UIVisualEffectView()
    private let tint = UIView()
    private let fadeMask = CAGradientLayer()
    private let top: Bool

    init(top: Bool) {
        self.top = top
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        accessibilityElementsHidden = true
        addSubview(blur)
        blur.contentView.addSubview(tint)
        layer.mask = fadeMask
        fadeMask.colors = top ? [UIColor.black.cgColor, UIColor.black.cgColor, UIColor.clear.cgColor] : [UIColor.clear.cgColor, UIColor.black.cgColor, UIColor.black.cgColor]
        fadeMask.locations = top ? [0, 0.55, 1] : [0, 0.6, 1]
        refreshMaterial()
        NotificationCenter.default.addObserver(self, selector: #selector(refreshMaterial), name: UIAccessibility.reduceTransparencyStatusDidChangeNotification, object: nil)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    @objc private func refreshMaterial() {
        let reduced = UIAccessibility.isReduceTransparencyEnabled
        blur.effect = reduced ? nil : UIBlurEffect(style: .systemThinMaterial)
        tint.backgroundColor = theme.paper.withAlphaComponent(reduced ? 1 : (top ? 0.45 : 0.25))
    }
    override func layoutSubviews() {
        super.layoutSubviews()
        blur.frame = bounds
        tint.frame = blur.bounds
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        fadeMask.frame = bounds
        CATransaction.commit()
    }
}
