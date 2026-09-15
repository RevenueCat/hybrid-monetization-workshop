import SwiftUI

/// Checkpoints describe a lesson, never an open keyboard or a partially completed gesture.
@MainActor
final class WalkthroughStore: ObservableObject {
    enum Lesson: String, Codable { case welcome, ingredients, peel, details, controls, cook, parallel, waiting, timerReady, serve, toast, plating, complete }
    private struct HistoryEntry: Codable {
        var lesson: Lesson
        var session: CookingSession
    }
    private struct Checkpoint: Codable {
        var lesson: Lesson
        var edits: [String: CellContent]
        var history: [HistoryEntry]?
        var session: CookingSession?
    }
    private let defaults: UserDefaults
    private let checkpointKey = "walkthrough.v1.checkpoint"
    private let completedKey = "walkthrough.v1.completed"
    @Published private(set) var lesson: Lesson = .welcome
    @Published var presented: Bool
    @Published var resumePrompt = false
    @Published private(set) var practice: SessionStore
    @Published private var history: [HistoryEntry] = []
    var canUndo: Bool { !history.isEmpty && !practice.session.isUntouched }
    var hasCompleted: Bool { defaults.bool(forKey: completedKey) }

    static let graph: RecipeGraph = {
        let recipe = try! Recipe.decode(Data(#"""
        {"schema_version":1,"id":"walkthrough","title":"Garlic spread",
         "ingredients":[
          {"id":"garlic","name":"Garlic","quantity":"¼ cup","instruction":"Separate the cloves and set them on the table."},
          {"id":"olive-oil","name":"Olive oil","quantity":"¼ cup, plus more","clarification":"Enough to cover","instruction":"Add enough olive oil to fully cover the garlic in a small pan."},
          {"id":"bread","name":"Bread","quantity":"2 slices","instruction":"Set out two slices of crusty bread."}],
         "steps":[
          {"id":"peel","action":"Peel","inputs":[{"ingredient":"garlic"}],"outputs":[{"id":"peeled-garlic","name":"Peeled garlic"}],"instruction":"Remove the papery skins from the garlic cloves."},
          {"id":"cook","action":"Confit","inputs":[{"output":"peeled-garlic"},{"ingredient":"olive-oil"}],"outputs":[{"id":"confit-garlic","name":"Confit garlic"},{"id":"garlic-oil","name":"Garlic oil"}],"duration":{"min":35,"max":40,"unit":"min"},"clarification":"Very low heat · barely bubbling","instruction":"Keep the garlic covered with oil over very low heat until very soft and pale golden."},
          {"id":"serve","action":"Mash","inputs":[{"output":"confit-garlic"}],"outputs":[{"id":"garlic-spread","name":"Garlic spread"}],"after":["cook"],"clarification":"Reserve the oil","instruction":"Lift the cloves out of the oil and mash with a fork until smooth and spreadable. Reserve the garlic oil for another use."},
          {"id":"toast","action":"Toast","inputs":[{"ingredient":"bread"}],"outputs":[{"id":"toasted-bread","name":"Toasted bread"}],"clarification":"Crisp and golden","instruction":"Toast the bread until crisp and golden while the garlic cooks."},
          {"id":"serve-spread","action":"Serve","inputs":[{"output":"garlic-spread"},{"output":"toasted-bread"}],"outputs":[],"clarification":"Spread over toast","instruction":"Spread the mashed garlic over the toast and serve."}]}
        """#.utf8))
        return try! RecipeGraph(recipe: recipe, displayOrder: ["garlic", "olive-oil", "bread", "peel", "cook", "serve", "toast", "serve-spread"])
    }()
    private static func makePractice() -> SessionStore {
        // No session or edits are written by this sample store.
        let store = SessionStore(graph: graph, fileURL: URL(fileURLWithPath: "/walkthrough-memory-only"), persists: false)
        store.onPrepareTimerAlert = { CookingTimerNotifications.shared.prepareForegroundAlert() }
        store.onTimerAlert = { CookingTimerNotifications.shared.foregroundAlert() }
        return store
    }
    init(defaults: UserDefaults = .standard, skip: Bool = false) {
        self.defaults = defaults
        practice = Self.makePractice()
        presented = !skip && !defaults.bool(forKey: completedKey)
        restore()
        resumePrompt = presented && lesson != .welcome
    }
    func open() {
        if lesson == .complete { restart() }
        resumePrompt = lesson != .welcome
        presented = true
    }
    func restart() {
        practice = Self.makePractice()
        history = []
        lesson = .welcome
        resumePrompt = false
        save()
    }
    func start() {
        guard lesson == .welcome else { return }
        remember(); advance(to: .ingredients)
    }
    func initialMenu() { save(); resumePrompt = lesson != .welcome }
    private func remember() { history.append(HistoryEntry(lesson: lesson, session: practice.session)) }
    func undo() {
        guard let previous = history.popLast() else { return }
        practice.restoreTransientProgress(previous.session)
        lesson = previous.lesson
        if practice.session.isUntouched { history.removeAll() }
        if [.parallel, .waiting].contains(lesson) {
            lesson = practice.session.progress.states["toast"] == .complete ? .timerReady : .toast
        }
        resumePrompt = false
        save()
    }
    func later() { save(); presented = false }
    func acknowledgeControls() {
        guard lesson == .controls else { return }
        remember()
        advance(to: practice.session.progress.states["toast"] == .complete ? .plating : .toast)
        practice.requestCurrentStep()
    }
    func detailsClosed() { if lesson == .details { remember(); advance(to: .peel) } else { save() } }
    func save() {
        defaults.set(try? JSONEncoder().encode(Checkpoint(lesson: lesson, edits: practice.edits, history: history, session: practice.session)), forKey: checkpointKey)
    }
    private func advance(to lesson: Lesson) {
        self.lesson = lesson
        if lesson == .timerReady {
            var session = practice.session
            session.progress.current = "cook"
            practice.restoreTransientProgress(session)
        }
        save()
    }
    func tap(_ id: String) {
        defer {
            if practice.session.isUntouched {
                history.removeAll()
                save()
            }
        }
        if practice.session.progress.states[id] == .running {
            completeTimer(id)
            return
        }
        switch lesson {
        case .ingredients:
            let setup = ["garlic", "olive-oil", "bread"]
            guard setup.contains(id), practice.session.progress.states[id] == .pending else { return }
            remember()
            practice.toggle(id)
            if setup.allSatisfy({ practice.session.progress.states[$0] != .pending }) { advance(to: .details) }
        case .peel:
            guard id == "peel" else { return }
            remember(); practice.toggle(id); advance(to: .cook)
        case .cook:
            guard id == "cook" else { return }
            remember(); practice.toggle(id)
            advance(to: practice.session.progress.states["toast"] == .complete ? .timerReady : .toast)
        case .timerReady:
            guard id == "cook" else { return }
            completeTimer(id)
        case .serve:
            guard id == "serve" else { return }
            remember(); practice.toggle(id)
            advance(to: .controls)
        case .toast:
            guard id == "toast" else { return }
            remember(); practice.toggle(id)
            advance(to: practice.session.progress.states["serve"] == .complete ? .controls :
                    practice.session.progress.states["cook"] == .complete ? .serve : .timerReady)
            practice.requestCurrentStep()
        case .controls, .plating:
            guard Self.graph.cells[id] != nil else { return }
            remember(); practice.toggle(id)
            if practice.isComplete {
                defaults.set(true, forKey: completedKey); advance(to: .complete)
            } else {
                switch id {
                case "garlic", "olive-oil", "bread": advance(to: .ingredients)
                case "peel": advance(to: .peel)
                case "cook": advance(to: practice.session.progress.states[id] == .running ? .timerReady : .cook)
                case "serve": advance(to: .serve)
                case "toast": advance(to: .toast)
                default: advance(to: .plating)
                }
            }
        default: break
        }
    }
    func timerReached() {
        if lesson == .waiting { advance(to: .timerReady) }
    }
    func completeTimer(_ id: String) {
        guard id == "cook", practice.session.progress.states[id] == .running else { return }
        remember(); practice.completeTimer(id)
        advance(to: practice.session.progress.states["toast"] == .complete ? .serve : .toast)
        practice.requestCurrentStep()
    }
    func addMinutes(_ minutes: Int, to id: String) {
        guard id == "cook", practice.session.progress.states[id] == .running else { return }
        remember(); practice.addMinutes(minutes, to: id); save()
    }
    func cancelTimer(_ id: String) {
        guard [Lesson.parallel, .waiting, .timerReady, .toast].contains(lesson), id == "cook" else { return }
        remember(); practice.cancelTimer(id); advance(to: .cook)
    }
    func completionBack() {
        guard lesson == .complete else { return }
        undo()
    }
    func finish() { practice.cancelCelebration(); save(); presented = false }
    private static func upgradingWalkthrough(to value: CookingSession, completed: Bool = false) -> CookingSession {
        var session = value
        func upgradingWalkthrough(to value: ProgressSnapshot, completed: Bool) -> ProgressSnapshot {
            var snapshot = value
            if snapshot.states["bread"] == nil {
                let setupWasComplete = snapshot.states["garlic"] != .pending && snapshot.states["olive-oil"] != .pending
                snapshot.states["bread"] = setupWasComplete ? .complete : .pending
            }
            if snapshot.states["serve-spread"] == nil {
                snapshot.states["serve-spread"] = completed ? .complete : .pending
            }
            if snapshot.states["toast"] == nil {
                snapshot.states["toast"] = completed || snapshot.states["serve-spread"] == .complete ? .complete : .pending
            }
            if !completed, snapshot.current == nil, snapshot.states["serve"] == .complete {
                snapshot.current = snapshot.states["toast"] == .complete ? "serve-spread" : "toast"
            }
            return snapshot
        }
        session.progress = upgradingWalkthrough(to: session.progress, completed: completed)
        session.history = session.history.map { upgradingWalkthrough(to: $0, completed: false) }
        return session
    }
    private func restore() {
        guard let data = defaults.data(forKey: checkpointKey),
              let checkpoint = try? JSONDecoder().decode(Checkpoint.self, from: data),
              Set(checkpoint.edits.keys).isSubset(of: Set(Self.graph.order)),
              checkpoint.edits.values.allSatisfy({ $0.issues.isEmpty }) else { return }
        for (id, content) in checkpoint.edits { try? practice.saveEdit(content, for: id) }
        if let rawHistory = checkpoint.history, let rawSession = checkpoint.session {
            let savedSession = Self.upgradingWalkthrough(to: rawSession, completed: checkpoint.lesson == .complete)
            let savedHistory = rawHistory.map { HistoryEntry(lesson: $0.lesson, session: Self.upgradingWalkthrough(to: $0.session)) }
            guard let session = try? savedSession.validated(for: Self.graph),
                  savedHistory.allSatisfy({ (try? $0.session.validated(for: Self.graph)) != nil }) else { return }
            lesson = checkpoint.lesson
            history = savedHistory
            // Resume the beginning of the unfinished lesson, retaining the actual
            // preceding action order for Undo (including either ingredient order).
            if let boundary = history.firstIndex(where: { $0.lesson == lesson }) {
                practice.restoreTransientProgress(history[boundary].session)
                history = Array(history.prefix(boundary))
            } else {
                practice.restoreTransientProgress(session)
            }
            // Before controls moved behind Mash, saved histories could contain
            // that lesson while Mash was still pending. Do not restore the old order.
            history.removeAll { $0.lesson == .controls && $0.session.progress.states["serve"] != .complete }
            if lesson == .controls && practice.session.progress.states["serve"] != .complete { lesson = .serve }
            if [.parallel, .waiting, .timerReady].contains(lesson) {
                lesson = practice.session.progress.states["toast"] == .complete ? .timerReady : .toast
            }
            if lesson == .plating { lesson = .controls }
            if lesson == .details && practice.session.progress.states["peel"] == .complete { lesson = .cook }
            advance(to: lesson)
        } else {
            // Upgrade checkpoints saved before walkthrough navigation had history.
            if checkpoint.lesson != .welcome { start() }
            if [.peel, .details, .cook, .parallel, .waiting, .timerReady, .controls, .serve, .toast, .plating, .complete].contains(checkpoint.lesson) {
                tap("garlic"); tap("olive-oil"); tap("bread")
            }
            if [.peel, .cook, .parallel, .waiting, .timerReady, .controls, .serve, .toast, .plating, .complete].contains(checkpoint.lesson) { detailsClosed() }
            if [.cook, .parallel, .waiting, .timerReady, .controls, .serve, .toast, .plating, .complete].contains(checkpoint.lesson) { tap("peel") }
            if [.parallel, .waiting, .timerReady, .controls, .serve, .toast, .plating, .complete].contains(checkpoint.lesson) { tap("cook") }
            if [.timerReady, .serve, .controls, .plating, .complete].contains(checkpoint.lesson) { tap("toast") }
            if [.serve, .controls, .toast, .plating, .complete].contains(checkpoint.lesson) { completeTimer("cook") }
            if [.controls, .toast, .plating, .complete].contains(checkpoint.lesson) { tap("serve") }
            if [.plating, .complete].contains(checkpoint.lesson) { acknowledgeControls() }
            if checkpoint.lesson == .complete { tap("serve-spread") }
        }
        practice.cancelCelebration()
    }
}

struct WalkthroughRoot: View {
    let library: RecipeLibrary
    @ObservedObject var walkthrough: WalkthroughStore
    var body: some View {
        Group {
            if walkthrough.presented {
                WalkthroughView(tour: walkthrough, store: walkthrough.practice)
                    .environment(\.gridDensityOverride, .comfortable)
            }
            else { RecipeBookView(library: library, openWalkthrough: walkthrough.open) }
        }
    }
}

private struct WalkthroughView: View {
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    private var compactCoaching: Bool { verticalSizeClass == .compact || dynamicTypeSize.isAccessibilitySize }
    @EnvironmentObject private var appearance: AppearanceStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject var tour: WalkthroughStore
    @ObservedObject var store: SessionStore
    @State private var selected: RecipeCell?
    @State private var titleCenter: CGFloat = 60
    @State private var headerBottom: CGFloat = 84
    @State private var hint = ""
    @State private var showingCompletion = false
    @State private var editorFinished = false

    private var suggestion: String? {
        guard let selected, !editorFinished, tour.lesson == .details else { return nil }
        return ["garlic": "Cloves separated", "olive-oil": "Cover the cloves", "peel": "Trim the root ends", "cook": "Low heat · stir occasionally"][selected.id]
    }
    var body: some View {
        Group {
            if tour.resumePrompt || tour.lesson == .welcome { welcome }
            else { table }
        }
        .foregroundStyle(Color(uiColor: appearance.theme.ink))
        .background(Color(uiColor: appearance.theme.paper))
        .tint(Color(uiColor: appearance.theme.ink))
        .sheet(item: $selected, onDismiss: tour.detailsClosed) { cell in
            CellDetails(store: store, cellID: cell.id, close: { selected = nil },
                        walkthroughSuggestion: suggestion, editorFinished: { editorFinished = true; tour.save() },
                        onTimerComplete: { tour.completeTimer(cell.id) },
                        onTimerCancel: { tour.cancelTimer(cell.id) },
                        onTimerAddMinutes: { tour.addMinutes($0, to: cell.id) })
        }
        .sheet(isPresented: $showingCompletion) {
            CompletionView(recipeTitle: store.graph.recipe.title, finish: { showingCompletion = false; tour.finish() },
                           cookAgain: { showingCompletion = false; tour.restart(); tour.start() },
                           stay: { showingCompletion = false; tour.completionBack() }, walkthrough: true)
        }
        .task(id: tour.lesson) {
            showingCompletion = false
            guard tour.lesson == .complete, !tour.resumePrompt else { return }
            if !reduceMotion {
                do { try await Task.sleep(for: .milliseconds(950)) } catch { return }
            }
            guard !Task.isCancelled, !tour.resumePrompt, tour.lesson == .complete else { return }
            showingCompletion = true
        }
        .onChange(of: store.primaryAttentionID) { _, id in if id == "cook" { tour.timerReached() } }
        .onChange(of: scenePhase) { _, phase in if phase != .active { tour.save() } }
    }
    private var welcome: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                PageBrand().accessibilityIdentifier("walkthrough.brand")
                Image(systemName: "fork.knife").font(.system(size: 44, weight: .light)).padding(.top, 36).accessibilityHidden(true)
                Text(tour.resumePrompt ? "Welcome back to the table." : "Let’s get cooking.")
                    .themeTitleFont(appearance.theme, size: 38).accessibilityIdentifier("walkthrough.welcome")
                Text(tour.resumePrompt ? "Pick up where you left off, or set the table again." : "From getting your ingredients ready to following each step, find your way around Kitchen Table.")
                    .themeFont(appearance.theme, style: .body)
                if tour.resumePrompt {
                    Button("Resume walkthrough") { tour.resumePrompt = false; if tour.lesson == .complete { showingCompletion = true } }
                        .buttonStyle(KitchenButtonStyle(primary: true)).accessibilityIdentifier("walkthrough.resume")
                    Button("Start again") { tour.restart(); tour.start() }.buttonStyle(KitchenButtonStyle())
                } else {
                    Button("Set the table", action: tour.start).buttonStyle(KitchenButtonStyle(primary: true)).accessibilityIdentifier("walkthrough.start")
                }
                Button("Later", action: tour.later).buttonStyle(KitchenButtonStyle()).accessibilityIdentifier("walkthrough.later")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24).padding(.top, 20).padding(.bottom, 24)
        }.scrollBounceBehavior(.basedOnSize)
    }
    private var table: some View {
        GeometryReader { geometry in
            let lessonCardHeight = min(250, geometry.size.height * 0.35)
            RecipeGridView(titleFirstLineCenter: $titleCenter, store: store, showDetails: { cell in
                guard ![WalkthroughStore.Lesson.welcome, .complete].contains(tour.lesson) else { return }
                editorFinished = false; selected = cell
            }, backToRecipes: tour.initialMenu,
                           safeInsets: UIEdgeInsets(top: geometry.safeAreaInsets.top, left: 0, bottom: geometry.safeAreaInsets.bottom + lessonCardHeight, right: 0),
                           onCellTap: tour.tap, automaticallyCenters: tour.lesson != .controls, showsNavigation: selected == nil, pinsHeader: true,
                           onHeaderBottomChange: { headerBottom = $0 },
                           focusTopInset: headerBottom + (store.primaryAttentionID == nil ? 12 : 68), focusBottomInset: 80)
                .id(ObjectIdentifier(store))
                .ignoresSafeArea(.container, edges: .vertical)
                .overlay(alignment: .topTrailing) {
                    if selected == nil && tour.canUndo {
                        HoldUndoButton(undo: tour.undo, reset: tour.restart, hint: $hint)
                            .frame(width: 48, height: 48).background(Color(uiColor: appearance.theme.surface), in: Circle())
                            .shadow(color: .black.opacity(0.10), radius: 8, y: 2)
                            .padding(.trailing, 24).padding(.top, max(24, titleCenter - 24))
                    }
                }
                .overlay(alignment: .top) {
                    if tour.lesson == .controls && !compactCoaching {
                        ScrollView {
                            HStack(alignment: .top, spacing: 12) {
                                tip(title: "Recipe Book", text: "Go back to your recipe list.", trailing: false, pointsUp: headerBottom > 48)
                                tip(title: "Undo · tap", text: "Reverses the last action.", trailing: true,
                                    additionalAction: ("Start over · hold 2s", "Release to start over."))
                            }.padding(.horizontal, 24).padding(.bottom, 8)
                        }.scrollBounceBehavior(.basedOnSize)
                            .allowsHitTesting(false)
                            .scrollClipDisabled()
                            .frame(maxHeight: max(60, geometry.size.height - min(250, geometry.size.height * 0.35) - headerBottom - 8))
                            .padding(.top, headerBottom + 8)
                    }
                }
                .overlay(alignment: .top) {
                    VStack(spacing: 12) {
                    if let id = store.primaryAttentionID {
                        Button { store.requestCurrentStep() } label: {
                            CookingNotificationPill(icon: "timer",
                                                    text: "\(store.cell(id).label) · \(store.timerPresentation(for: id)?.text ?? "Check now")")
                        }
                        .accessibilityIdentifier("timer.alert")
                    }
                        ScreenOnFeedback()
                    }.padding(.top, headerBottom + 12).padding(.horizontal, 24)
                }
                .overlay(alignment: .bottomLeading) {
                    KeepScreenOnButton().padding(.leading, 24).padding(.bottom, 16)
                }
                .overlay(alignment: .bottomTrailing) {
                    if tour.lesson == .controls || (!store.currentIsCentered && store.focusTargetID != nil) {
                        Button(action: store.requestCurrentStep) {
                            Image(systemName: "scope").font(.system(size: 20, weight: .medium))
                                .frame(width: 48, height: 48)
                                .background(Color(uiColor: appearance.theme.surface), in: Circle())
                                .shadow(color: .black.opacity(0.10), radius: 8, y: 2)
                        }.accessibilityLabel("Current step").accessibilityIdentifier("grid.current")
                            .disabled(store.isCenteringCurrent)
                            .padding(.trailing, 24).padding(.bottom, 16)
                    }
                }
                .overlay(alignment: .bottom) {
                    if tour.lesson == .controls && !compactCoaching {
                        HStack(alignment: .bottom, spacing: 12) {
                            tip(title: "Keep screen on", text: "Tap the sun to toggle. Filled means on; outlined allows auto-lock.", trailing: false, pointsDown: true)
                            tip(title: "Current step", text: "Bring the highlighted step back into view.", trailing: true, pointsDown: true)
                        }.padding(.horizontal, 24).padding(.bottom, 72).allowsHitTesting(false)
                    }
                }
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    lessonCard.frame(maxHeight: lessonCardHeight)
                }
                .modifier(CookingScreenAwake())
        }
    }
    private func tip(title: String, text: String, trailing: Bool, pointsUp: Bool = true, pointsDown: Bool = false,
                     additionalAction: (title: String, text: String)? = nil) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).themeFont(appearance.theme, style: .subheadline, emphasized: true)
            Text(text).themeFont(appearance.theme, style: .caption1)
            if let additionalAction {
                Text(additionalAction.title).themeFont(appearance.theme, style: .subheadline, emphasized: true)
                    .padding(.top, 4)
                Text(additionalAction.text).themeFont(appearance.theme, style: .caption1)
            }
        }.padding(14).frame(maxWidth: .infinity, alignment: .leading)
            .padding(pointsDown ? .bottom : .top, 9)
            .foregroundStyle(Color(uiColor: appearance.theme.onAccent))
            .background {
                WalkthroughTipShape(trailing: trailing, pointsUp: pointsUp, pointsDown: pointsDown)
                    .fill(Color(uiColor: appearance.theme.accent))
                    .shadow(color: .black.opacity(0.2), radius: 10, y: 4)
            }
            .fixedSize(horizontal: false, vertical: true).accessibilityElement(children: .combine)
            .modifier(WalkthroughTipEntrance())
    }
    private var lessonCard: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(lessonTitle).themeFont(appearance.theme, style: .headline, emphasized: true).accessibilityIdentifier("walkthrough.lesson")
                    Spacer()
                    Button("Later", action: tour.later).themeFont(appearance.theme, style: .callout).frame(minHeight: 44).accessibilityIdentifier("walkthrough.later")
                }
                Text(lessonCopy).themeFont(appearance.theme, style: .body).fixedSize(horizontal: false, vertical: true)
                if tour.lesson == .controls {
                    if compactCoaching {
                        tip(title: "Recipe Book", text: "Go back to your recipe list.", trailing: false, pointsUp: false)
                        tip(title: "Undo · tap", text: "Reverses the last action.", trailing: false, pointsUp: false,
                            additionalAction: ("Start over · hold 2s", "Release to start over."))
                        tip(title: "Keep screen on", text: "Tap the sun to toggle. Filled means on; outlined allows auto-lock.", trailing: false, pointsUp: false)
                        tip(title: "Current step", text: "Bring the highlighted step back into view.", trailing: false, pointsUp: false)
                    }
                    Button("Got it", action: tour.acknowledgeControls).buttonStyle(KitchenButtonStyle(primary: true)).accessibilityIdentifier("walkthrough.gotIt")
                }
                if !hint.isEmpty { Text(hint).themeFont(appearance.theme, style: .caption1).accessibilityIdentifier("walkthrough.hint") }
            }.padding(24)
        }.scrollBounceBehavior(.basedOnSize).frame(maxHeight: 250)
            .background(Color(uiColor: appearance.theme.paper))
            .overlay(alignment: .top) { Rectangle().fill(Color(uiColor: appearance.theme.line)).frame(height: 0.5) }
            .onChange(of: tour.lesson) { _, _ in hint = "" }
    }
    private var lessonTitle: String {
        switch tour.lesson {
        case .ingredients: "Mise en place"
        case .peel: "Ready to prep"
        case .details: "A closer look"
        case .controls: "Around the table"
        case .cook: "Start a timer"
        case .parallel, .waiting: "Use the waiting time"
        case .timerReady: "Time to check"
        case .serve: "Bring it all together"
        case .toast: "Toast the bread"
        case .plating, .complete: "Ready to serve"
        default: "Let’s get cooking"
        }
    }
    private var lessonCopy: String {
        switch tour.lesson {
        case .ingredients: "Set out the garlic, olive oil, and sliced bread. Tap each one as it reaches the table."
        case .peel: "Ingredients ready. The highlighted cell suggests what to do next. Tap Peel when the cloves are peeled."
        case .details: "Ingredients ready. Touch and hold Peel to see its details. You can do this with any ingredient or step."
        case .controls: "These controls are here whenever you need them."
        case .cook: "Tap Confit to start the 35–40 minute timer. You won’t need to wait that long in this walkthrough."
        case .parallel, .waiting: "Confit is running. Use the waiting time to toast the bread."
        case .timerReady: "Tap Confit to complete it early for this walkthrough. Hold it to adjust the timer. In your kitchen, wait until the garlic is soft."
        case .serve: "Confit is complete. Tap Mash to make the spread."
        case .toast: store.session.progress.states["cook"] == .running
            ? "While Confit runs, toast the bread until crisp and golden. Tap Toast when it is ready."
            : "Toast the bread until crisp and golden. Tap Toast when it is ready."
        case .plating: "Mash and Toast are complete. Tap Serve to finish."
        case .complete: "The garlic toast is ready to serve."
        default: ""
        }
    }
}

private struct WalkthroughTipShape: Shape {
    var trailing: Bool
    var pointsUp = true
    var pointsDown = false

    func path(in rect: CGRect) -> Path {
        let pointerHeight: CGFloat = 9
        let center = trailing ? rect.maxX - 22 : rect.minX + 22
        let top = rect.minY + pointerHeight
        let radius: CGFloat = 12
        // One continuous outline avoids seams between the pointer and rounded card.
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + radius, y: top))
        if pointsUp {
            path.addLine(to: CGPoint(x: center - 7, y: top))
            path.addLine(to: CGPoint(x: center, y: rect.minY))
            path.addLine(to: CGPoint(x: center + 7, y: top))
        }
        path.addLine(to: CGPoint(x: rect.maxX - radius, y: top))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: top + radius), control: CGPoint(x: rect.maxX, y: top))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - radius))
        path.addQuadCurve(to: CGPoint(x: rect.maxX - radius, y: rect.maxY), control: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX + radius, y: rect.maxY))
        path.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.maxY - radius), control: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: top + radius))
        path.addQuadCurve(to: CGPoint(x: rect.minX + radius, y: top), control: CGPoint(x: rect.minX, y: top))
        path.closeSubpath()
        return pointsDown ? path.applying(CGAffineTransform(translationX: 0, y: rect.height).scaledBy(x: 1, y: -1)) : path
    }
}

private struct WalkthroughTipEntrance: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var visible = false
    func body(content: Content) -> some View {
        content.opacity(visible ? 1 : 0)
            .offset(y: visible || reduceMotion ? 0 : 4)
            .onAppear { withAnimation(.easeOut(duration: reduceMotion ? 0.15 : 0.25)) { visible = true } }
    }
}
