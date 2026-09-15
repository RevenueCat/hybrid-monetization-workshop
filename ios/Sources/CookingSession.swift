import Foundation
import Combine
import UIKit

enum CellState: String, Codable { case pending, running, complete }
enum GridDensity: String, Codable, CaseIterable { case compact = "Compact", comfortable = "Comfort" }

struct CookingTimer: Codable, Equatable {
    var startedAt: Date
    var checkAt: Date
    var endAt: Date
    /// Real seconds used for one recipe second. Literal timers use 1; scaled
    /// test clocks may use another value while preserving recipe-time display.
    var secondsPerRecipeSecond: Double

    init(startedAt: Date, checkAt: Date, endAt: Date, secondsPerRecipeSecond: Double = 1) {
        self.startedAt = startedAt
        self.checkAt = checkAt
        self.endAt = endAt
        self.secondsPerRecipeSecond = secondsPerRecipeSecond
    }
}

struct ProgressSnapshot: Codable, Equatable {
    var states: [String: CellState]
    var current: String?
    var timers: [String: CookingTimer] = [:]

    init(states: [String: CellState], current: String?, timers: [String: CookingTimer] = [:]) {
        self.states = states; self.current = current; self.timers = timers
    }

    private enum CodingKeys: String, CodingKey { case states, current, timers }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        states = try values.decode([String: CellState].self, forKey: .states)
        current = try values.decodeIfPresent(String.self, forKey: .current)
        timers = try values.decodeIfPresent([String: CookingTimer].self, forKey: .timers) ?? [:]
    }
}

struct TimerPresentation: Equatable {
    var text: String
    var accessibilityText: String
    var progress: Double
    var needsAttention: Bool
}

struct CookingJournalEntry: Codable, Equatable, Identifiable {
    var id: String
    var recipeID: String
    var dishName: String
    var completedAt: Date

    init(id: String = UUID().uuidString, recipeID: String, dishName: String, completedAt: Date) {
        self.id = id
        self.recipeID = recipeID
        self.dishName = dishName
        self.completedAt = completedAt
    }


}

struct CookingStatistics: Codable {
    var dishesCompleted = 0
    var lastCompleted: Date?
    var journalEntries: [CookingJournalEntry] = []

    init(dishesCompleted: Int = 0, lastCompleted: Date? = nil,
         journalEntries: [CookingJournalEntry] = []) {
        self.dishesCompleted = dishesCompleted
        self.lastCompleted = lastCompleted
        self.journalEntries = journalEntries
    }


}

struct CookingSession: Codable {
    var version = 1
    var recipeID: String
    var progress: ProgressSnapshot
    var history: [ProgressSnapshot] = []
    var density: GridDensity = .compact
    var scrollX: Double = 0
    var scrollY: Double = 0
    var statistics: CookingStatistics?

    var isUntouched: Bool {
        progress.timers.isEmpty && progress.states.values.allSatisfy { $0 == .pending }
    }

    private mutating func discardHistoryIfUntouched() {
        if isUntouched { history.removeAll() }
    }

    init(graph: RecipeGraph) {
        recipeID = graph.recipe.id
        progress = ProgressSnapshot(states: Dictionary(uniqueKeysWithValues: graph.order.map { ($0, .pending) }), current: graph.order.first)
    }

    func validated(for graph: RecipeGraph) throws -> CookingSession {
        let ids = Set(graph.order)
        func valid(_ snapshot: ProgressSnapshot) -> Bool {
            Set(snapshot.states.keys) == ids && Set(snapshot.timers.keys).isSubset(of: ids) &&
            snapshot.timers.allSatisfy { id, timer in
                snapshot.states[id] == .running && timer.startedAt <= timer.checkAt && timer.checkAt <= timer.endAt &&
                timer.secondsPerRecipeSecond.isFinite && timer.secondsPerRecipeSecond > 0
            } && (snapshot.current.map { ids.contains($0) } ?? true)
        }
        guard version == 1, recipeID == graph.recipe.id, valid(progress), history.allSatisfy(valid),
              scrollX.isFinite, scrollY.isFinite, scrollX >= 0, scrollY >= 0 else {
            throw RecipeError.invalid("Saved cooking progress is incompatible with this recipe.")
        }
        var restored = self
        restored.discardHistoryIfUntouched()
        return restored
    }

    mutating func toggle(_ id: String, graph: RecipeGraph, ingredientOrder: [String]? = nil) {
        guard graph.cells[id] != nil, progress.states[id] != .running else { return }
        history.append(progress)
        if progress.states[id] == .pending { mark(id, graph: graph) }
        else { unmark(id, graph: graph) }
        progress.current = suggestion(after: id, graph: graph,
                                      ingredientOrder: ingredientOrder ?? graph.ingredientOrder)
        discardHistoryIfUntouched()
    }

    private mutating func mark(_ id: String, graph: RecipeGraph) {
        if progress.states[id] == .complete { return }
        for input in graph.cells[id]!.dependencies { mark(input, graph: graph) }
        progress.timers.removeValue(forKey: id)
        progress.states[id] = .complete
    }

    private mutating func unmark(_ id: String, graph: RecipeGraph) {
        progress.timers.removeValue(forKey: id)
        progress.states[id] = .pending
        for dependent in graph.dependents(of: id) { unmark(dependent, graph: graph) }
    }

    mutating func startTimer(_ id: String, duration: EditedDuration, graph: RecipeGraph, now: Date, scale: Double = 1) {
        guard graph.cells[id] != nil, progress.states[id] == .pending, runningPrerequisite(of: id, graph: graph) == nil,
              duration.issues.isEmpty, scale.isFinite, scale > 0 else { return }
        history.append(progress)
        for dependency in graph.cells[id]!.dependencies { mark(dependency, graph: graph) }
        let minimum = duration.recipeSeconds(duration.min) * scale
        let maximum = duration.recipeSeconds(duration.max) * scale
        progress.states[id] = .running
        progress.timers[id] = CookingTimer(startedAt: now, checkAt: now.addingTimeInterval(minimum),
                                           endAt: now.addingTimeInterval(maximum), secondsPerRecipeSecond: scale)
        progress.current = suggestion(after: id, graph: graph, ingredientOrder: graph.ingredientOrder)
    }

    mutating func completeTimer(_ id: String, graph: RecipeGraph) {
        guard progress.states[id] == .running else { return }
        history.append(progress)
        progress.timers.removeValue(forKey: id)
        progress.states[id] = .complete
        progress.current = suggestion(after: id, graph: graph, ingredientOrder: graph.ingredientOrder)
    }

    mutating func cancelTimer(_ id: String, graph: RecipeGraph) {
        guard progress.states[id] == .running else { return }
        history.append(progress)
        unmark(id, graph: graph)
        progress.current = suggestion(after: id, graph: graph, ingredientOrder: graph.ingredientOrder)
        discardHistoryIfUntouched()
    }

    mutating func addTime(_ recipeSeconds: TimeInterval, to id: String, graph: RecipeGraph, now: Date = Date()) {
        guard recipeSeconds.isFinite, recipeSeconds != 0, var timer = progress.timers[id] else { return }
        let requestedSeconds = recipeSeconds * timer.secondsPerRecipeSecond
        // Stop at the check time without completing the cell or shifting an expired timer forward.
        let realSeconds = requestedSeconds < 0
            ? max(requestedSeconds, min(0, max(now, timer.startedAt).timeIntervalSince(timer.checkAt)))
            : requestedSeconds
        guard realSeconds != 0 else { return }
        history.append(progress)
        timer.checkAt = timer.checkAt.addingTimeInterval(realSeconds)
        timer.endAt = timer.endAt.addingTimeInterval(realSeconds)
        progress.timers[id] = timer
        // Adjusting a deadline is not a progress action: preserve the current cell.
    }

    @discardableResult
    mutating func reconsiderCurrent(now: Date, graph: RecipeGraph) -> Bool {
        let due = progress.timers.filter { now >= $0.value.checkAt }
            .sorted { lhs, rhs in lhs.value.checkAt == rhs.value.checkAt ?
                (graph.order.firstIndex(of: lhs.key) ?? 0) < (graph.order.firstIndex(of: rhs.key) ?? 0) : lhs.value.checkAt < rhs.value.checkAt }
            .first?.key
        guard let due, progress.current != due else { return false }
        progress.current = due
        return true
    }

    mutating func undo() {
        if let previous = history.popLast() { progress = previous }
        discardHistoryIfUntouched()
    }

    mutating func reset(graph: RecipeGraph) {
        statistics = statistics ?? CookingStatistics()
        history.removeAll()
        progress = CookingSession(graph: graph).progress
    }

    private func pendingPrerequisite(_ id: String, graph: RecipeGraph) -> String? {
        guard progress.states[id] == .pending else { return nil }
        for dependency in graph.cells[id]!.dependencies {
            if progress.states[dependency] == .running { return nil }
            if let next = pendingPrerequisite(dependency, graph: graph) { return next }
        }
        // A blocked subtree returning nil does not mean its parent is ready.
        return graph.cells[id]!.dependencies.allSatisfy { progress.states[$0] == .complete } ? id : nil
    }

    private func runningPrerequisite(of id: String, graph: RecipeGraph) -> String? {
        if progress.states[id] == .running { return id }
        for dependency in graph.cells[id]?.dependencies ?? [] {
            if let running = runningPrerequisite(of: dependency, graph: graph) { return running }
        }
        return nil
    }

    private func firstReady(graph: RecipeGraph) -> String? {
        graph.order.first { id in
            progress.states[id] == .pending && graph.cells[id]!.dependencies.allSatisfy { progress.states[$0] == .complete }
        }
    }

    private func suggestion(after id: String, graph: RecipeGraph, ingredientOrder: [String]) -> String? {
        if progress.states[id] == .pending { return pendingPrerequisite(id, graph: graph) }
        if graph.cells[id]!.isIngredient, let index = ingredientOrder.firstIndex(of: id) {
            let rest = Array(ingredientOrder.dropFirst(index + 1)) + Array(ingredientOrder.prefix(index))
            return rest.first { progress.states[$0] == .pending } ?? firstReady(graph: graph)
        }
        for next in graph.dependents(of: id) {
            if let pending = pendingPrerequisite(next, graph: graph) { return pending }
        }
        return firstReady(graph: graph)
    }
}

private extension EditedDuration {
    func recipeSeconds(_ value: Double) -> TimeInterval {
        switch unit {
        case "h": value * 3600
        case "min": value * 60
        default: value
        }
    }
}

@MainActor
final class SessionStore: ObservableObject {
    let graph: RecipeGraph
    let layout: RecipeTableLayout
    let fileURL: URL
    private let persists: Bool
    @Published private(set) var session: CookingSession
    @Published var errorMessage: String?
    @Published var focusRequest = 0
    private(set) var explicitFocusRequest = 0
    @Published var currentIsCentered = true
    @Published var isCenteringCurrent = false
    @Published private(set) var celebrationID: UUID?
    @Published private(set) var edits: [String: CellContent] = [:]
    @Published private(set) var contentRevision = 0
    @Published private(set) var timerNow = Date()
    @Published private(set) var timerAlertSequence = 0
    private let timerScale: Double
    private let timerDurationOverride: TimeInterval?
    private let fixedTimerDurationOverride: TimeInterval?
    private let timerTickInterval: TimeInterval
    private var timerClock: AnyCancellable?
    private var deadlineTimer: Timer?
    private var preparationTimer: Timer?
    private var lifecycleObservers: Set<AnyCancellable> = []
    private var displaysTimers = false
    private var isActive = true
    private(set) var recipeRemoved = false

    func setRecipeRemoved(_ removed: Bool) {
        guard recipeRemoved != removed else { return }
        recipeRemoved = removed
        syncClock()
        if removed { CookingTimerNotifications.shared.cancel(self) }
        else { Task { await CookingTimerNotifications.shared.sync(self) } }
    }
    var onPrepareTimerAlert: (() -> Void)?
    var onTimerAlert: (() -> Void)?
    private var attentionIDs: Set<String> = []
    private var editsURL: URL { fileURL.deletingPathExtension().appendingPathExtension("edits.json") }

    init(graph: RecipeGraph, fileURL: URL, persists: Bool = true, timerScale: Double = 1,
         timerDurationOverride: TimeInterval? = nil, fixedTimerDurationOverride: TimeInterval? = nil,
         timerTickInterval: TimeInterval = 1, layout: RecipeTableLayout? = nil) {
        self.graph = graph; self.fileURL = fileURL; self.persists = persists
        self.layout = layout ?? (try! RecipeTableLayout.generated(for: graph))
        self.timerScale = timerScale; self.timerDurationOverride = timerDurationOverride
        self.fixedTimerDurationOverride = fixedTimerDurationOverride; self.timerTickInterval = timerTickInterval
        session = CookingSession(graph: graph)
        if persists && FileManager.default.fileExists(atPath: fileURL.path) {
            do {
                session = try JSONDecoder().decode(CookingSession.self, from: Data(contentsOf: fileURL)).validated(for: graph)
            } catch {
                let backup = fileURL.deletingPathExtension().appendingPathExtension("unreadable-\(Int(Date().timeIntervalSince1970)).json")
                try? FileManager.default.copyItem(at: fileURL, to: backup)
                errorMessage = "Saved progress could not be restored. A new session is open. \(error.localizedDescription)"
            }
        }
        if persists && FileManager.default.fileExists(atPath: editsURL.path) {
            do {
                let saved = try JSONDecoder().decode(RecipeEdits.self, from: Data(contentsOf: editsURL))
                guard saved.version == 1, saved.recipeID == graph.recipe.id, Set(saved.cells.keys).isSubset(of: Set(graph.order)) else {
                    throw RecipeError.invalid("Saved recipe edits do not match this recipe.")
                }
                edits = try saved.cells.mapValues { try $0.validated() }
            } catch {
                let backup = editsURL.appendingPathExtension("unreadable-\(Int(Date().timeIntervalSince1970))")
                try? FileManager.default.copyItem(at: editsURL, to: backup)
                errorMessage = "Saved recipe edits could not be read. Their original file was preserved. \(error.localizedDescription)"
            }
        }
        timerNow = Date()
        _ = session.reconsiderCurrent(now: timerNow, graph: graph)
        attentionIDs = Set(attentionTimerIDs)
        NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in self?.setApplicationActive(true) }.store(in: &lifecycleObservers)
        NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)
            .sink { [weak self] _ in self?.setApplicationActive(false) }.store(in: &lifecycleObservers)
        syncClock()
    }

    deinit { deadlineTimer?.invalidate(); preparationTimer?.invalidate() }

    func setTimerDisplayActive(_ active: Bool) {
        displaysTimers = active
        syncDisplayClock()
    }

    private func setApplicationActive(_ active: Bool) {
        isActive = active
        if active {
            // Background delivery belongs to local notifications. Reconcile the
            // table on return without playing the same alert a second time.
            timerNow = Date()
            if session.reconsiderCurrent(now: timerNow, graph: graph) { save(); focusRequest += 1 }
            updateAttention(notify: false)
        }
        syncClock()
    }

    func content(for id: String) -> CellContent {
        if let edit = edits[id] { return edit }
        let cell = graph.cells[id]!
        let source = graph.recipe.steps.first { $0.id == id }?.duration
        return CellContent(label: cell.label, quantity: cell.isIngredient ? cell.amount ?? "" : "",
                           duration: source.map { EditedDuration(min: $0.min, max: $0.max, unit: $0.unit, approximate: $0.approximate ?? false) },
                           cue: cell.cue ?? "", instruction: cell.instruction)
    }
    func cell(_ id: String) -> RecipeCell {
        var cell = content(for: id).applying(to: graph.cells[id]!)
        cell.inputReferences = layout.references.filter { $0.targetID == id }.map {
            $0.text(sourceLabel: content(for: $0.sourceID).label)
        }
        return cell
    }

    func saveEdit(_ content: CellContent, for id: String) throws {
        guard graph.cells[id] != nil else { throw RecipeError.invalid("This cell is no longer available.") }
        let valid = try content.validated()
        var updated = edits
        updated[id] = valid
        if persists {
            try FileManager.default.createDirectory(at: editsURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(RecipeEdits(recipeID: graph.recipe.id, cells: updated)).write(to: editsURL, options: .atomic)
        }
        edits = updated
        contentRevision += 1
    }



    var isComplete: Bool {
        !session.progress.states.isEmpty && session.progress.states.values.allSatisfy { $0 == .complete }
    }
    var runningTimerIDs: [String] {
        graph.order.filter { session.progress.states[$0] == .running && session.progress.timers[$0] != nil }
    }
    var attentionTimerIDs: [String] {
        runningTimerIDs.filter { id in session.progress.timers[id].map { timerNow >= $0.checkAt } ?? false }
            .sorted { lhs, rhs in session.progress.timers[lhs]!.checkAt < session.progress.timers[rhs]!.checkAt }
    }
    var primaryAttentionID: String? { attentionTimerIDs.first }
    /// The cell used by viewport guidance. Ready work takes precedence; while
    /// there is nothing actionable, keep the next running timer reachable.
    var focusTargetID: String? {
        if let current = session.progress.current { return current }
        return runningTimerIDs.min { lhs, rhs in
            guard let left = session.progress.timers[lhs], let right = session.progress.timers[rhs] else {
                return false
            }
            if left.checkAt != right.checkAt { return left.checkAt < right.checkAt }
            return (graph.order.firstIndex(of: lhs) ?? .max) < (graph.order.firstIndex(of: rhs) ?? .max)
        }
    }
    func timerPresentation(for id: String) -> TimerPresentation? {
        guard let timer = session.progress.timers[id] else { return nil }
        let elapsed = timerNow.timeIntervalSince(timer.startedAt)
        let total = max(0.001, timer.endAt.timeIntervalSince(timer.startedAt))
        let progress = min(1, max(0, elapsed / total))
        if timerNow >= timer.endAt {
            return TimerPresentation(text: "Time reached", accessibilityText: "time reached", progress: progress, needsAttention: true)
        }
        if timerNow >= timer.checkAt {
            return TimerPresentation(text: "Check now", accessibilityText: "ready to check", progress: progress, needsAttention: true)
        }
        let recipeSeconds = max(0, timer.checkAt.timeIntervalSince(timerNow) / timer.secondsPerRecipeSecond)
        let text = Self.countdown(recipeSeconds)
        return TimerPresentation(text: text, accessibilityText: "\(text) remaining", progress: progress, needsAttention: false)
    }
    private static func countdown(_ seconds: TimeInterval) -> String {
        let value = Int(ceil(seconds))
        let hours = value / 3600, minutes = (value % 3600) / 60, remainder = value % 60
        return hours > 0 ? String(format: "%d:%02d:%02d", hours, minutes, remainder) : String(format: "%d:%02d", minutes, remainder)
    }
    /// In-memory walkthrough navigation may restore progress without undoing text edits.
    func restoreTransientProgress(_ snapshot: CookingSession) {
        guard !persists else { return }
        cancelCelebration()
        session = snapshot
        timerNow = Date()
        _ = session.reconsiderCurrent(now: timerNow, graph: graph)
        updateAttention()
        syncClock()
        focusRequest += 1
    }
    func cancelCelebration() { celebrationID = nil }
    func requestCurrentStep() {
        guard !isCenteringCurrent, !currentIsCentered, focusTargetID != nil else { return }
        // Lock immediately, before SwiftUI delivers the request to the scroll view.
        isCenteringCurrent = true
        explicitFocusRequest += 1
        focusRequest += 1
    }
    func toggle(_ id: String) {
        cancelCelebration()
        // The display clock is stopped while idle; start from the actual tap.
        timerNow = Date()
        if session.progress.states[id] == .running {
            completeTimer(id)
            return
        }
        let completing = session.progress.states[id] == .pending
        let wasFinished = isComplete
        if completing, let duration = content(for: id).duration {
            let effectiveDuration: EditedDuration
            if let override = fixedTimerDurationOverride, override > 0 {
                effectiveDuration = EditedDuration(min: override, max: override, unit: "sec", approximate: false)
            } else if let override = timerDurationOverride, override > 0, duration.max > 0 {
                effectiveDuration = EditedDuration(min: override * duration.min / duration.max,
                                                   max: override, unit: "sec", approximate: duration.approximate)
            } else {
                effectiveDuration = duration
            }
            session.startTimer(id, duration: effectiveDuration, graph: graph, now: timerNow, scale: timerScale)
        } else {
            let ingredientOrder = layout.readingOrder.filter { graph.cells[$0]?.isIngredient == true }
            session.toggle(id, graph: graph, ingredientOrder: ingredientOrder)
        }
        _ = session.reconsiderCurrent(now: timerNow, graph: graph)
        if completing && !wasFinished && isComplete {
            celebrationID = UUID()
        }
        syncClock()
        save(); focusRequest += 1
    }
    func completeTimer(_ id: String) {
        cancelCelebration()
        let wasFinished = isComplete
        session.completeTimer(id, graph: graph)
        _ = session.reconsiderCurrent(now: timerNow, graph: graph)
        if !wasFinished && isComplete { celebrationID = UUID() }
        updateAttention(); syncClock(); save(); focusRequest += 1
    }
    func cancelTimer(_ id: String) {
        cancelCelebration(); session.cancelTimer(id, graph: graph)
        _ = session.reconsiderCurrent(now: timerNow, graph: graph)
        updateAttention(); syncClock(); save(); focusRequest += 1
    }
    func addMinutes(_ minutes: Int, to id: String) {
        guard [-5, -1, 1, 5].contains(minutes), session.progress.states[id] == .running else { return }
        timerNow = Date()
        session.addTime(TimeInterval(minutes * 60), to: id, graph: graph)
        // Keep the table stationary behind the timer details sheet.
        updateAttention(); syncClock(); save()
    }
    func undo() {
        cancelCelebration(); session.undo()
        _ = session.reconsiderCurrent(now: timerNow, graph: graph)
        updateAttention(); syncClock(); save(); focusRequest += 1
    }
    func reset() { cancelCelebration(); session.reset(graph: graph); updateAttention(); syncClock(); save(); focusRequest += 1 }
    /// Commit the meal and fresh progress together; plain reset/Undo never count a dish.
    @discardableResult
    func finish() -> Bool {
        guard isComplete else { return false }
        var finished = session
        var stats = finished.statistics ?? CookingStatistics()
        let completedAt = Date()
        stats.dishesCompleted += 1
        stats.lastCompleted = completedAt
        stats.journalEntries.append(CookingJournalEntry(recipeID: graph.recipe.id,
                                                       dishName: graph.recipe.title,
                                                       completedAt: completedAt))
        finished.statistics = stats
        finished.reset(graph: graph)
        do {
            try persist(finished)
            cancelCelebration()
            session = finished
            syncClock()
            errorMessage = nil
            focusRequest += 1
            return true
        } catch {
            errorMessage = "The dish could not be finished. Your table is still available. \(error.localizedDescription)"
            return false
        }
    }

    func setDensity(_ density: GridDensity) { session.density = density; save(); focusRequest += 1 }
    func recordScroll(x: Double, y: Double) {
        session.scrollX = max(0, x); session.scrollY = max(0, y); save()
    }
    func save() {
        do {
            try persist(session)
        } catch { errorMessage = "Progress could not be saved. \(error.localizedDescription)" }
    }
    private func persist(_ value: CookingSession) throws {
        guard persists else { return }
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(value).write(to: fileURL, options: .atomic)
    }

    private func tick(_ date: Date) {
        timerNow = date
        let moved = session.reconsiderCurrent(now: date, graph: graph)
        updateAttention()
        if moved { save(); focusRequest += 1 }
    }
    private func updateAttention(notify: Bool = true) {
        let latest = Set(attentionTimerIDs)
        if !latest.subtracting(attentionIDs).isEmpty && notify {
            timerAlertSequence += 1
            onTimerAlert?()
        }
        attentionIDs = latest
    }
    private func syncClock() {
        deadlineTimer?.invalidate(); deadlineTimer = nil
        preparationTimer?.invalidate(); preparationTimer = nil
        // An edit or another tap may arrive as a deadline passes. Reconcile
        // before replacing callbacks so that an already-due check is not lost.
        if isActive && !recipeRemoved { tick(Date()) }
        syncDisplayClock()
        guard isActive, !recipeRemoved else { return }
        let now = Date()
        let timers = session.progress.timers.values
        // Only wake for a state transition: first check, then the range end.
        let deadlines = timers.flatMap { timer -> [Date] in
            var dates: [Date] = []
            if timer.checkAt > timerNow { dates.append(timer.checkAt) }
            if timer.endAt > timerNow { dates.append(timer.endAt) }
            return dates
        }
        if let deadline = deadlines.min() {
            let timer = Timer(fire: max(now, deadline), interval: 0, repeats: false) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.tick(Date())
                    self.syncClock()
                }
            }
            deadlineTimer = timer
            RunLoop.main.add(timer, forMode: .common)
        }
        if let check = timers.map(\.checkAt).filter({ $0 > now }).min() {
            let timer = Timer(fire: max(now, check.addingTimeInterval(-0.5)), interval: 0, repeats: false) { [weak self] _ in
                MainActor.assumeIsolated { self?.onPrepareTimerAlert?() }
            }
            preparationTimer = timer
            RunLoop.main.add(timer, forMode: .common)
        }
    }

    private func syncDisplayClock() {
        if recipeRemoved || !displaysTimers || !isActive || !session.progress.timers.values.contains(where: { $0.endAt > Date() }) {
            timerClock = nil
        } else if timerClock == nil {
            timerClock = Timer.publish(every: timerTickInterval, on: .main, in: .common).autoconnect().sink { [weak self] date in
                // Presentation only. Deadline callbacks own alerts and guidance.
                self?.timerNow = date
            }
        }
    }

}
