import SwiftUI
import UserNotifications
import AudioToolbox

final class CookingTimerNotifications: NSObject, UNUserNotificationCenterDelegate {
    static let shared = CookingTimerNotifications()
    private let center = UNUserNotificationCenter.current()
    @MainActor private var feedback: UINotificationFeedbackGenerator?

    func configure() { center.delegate = self }

    @MainActor
    func cancel(_ store: SessionStore) {
        let identifiers = store.graph.order.map { "cooking-timer.\(store.graph.recipe.id)." + $0 }
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
        center.removeDeliveredNotifications(withIdentifiers: identifiers)
    }

    @MainActor
    func sync(_ store: SessionStore) async {
        let prefix = "cooking-timer.\(store.graph.recipe.id)."
        let identifiers = store.graph.order.map { prefix + $0 }
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
        guard !store.recipeRemoved, !store.runningTimerIDs.isEmpty else { return }
        let settings = await center.notificationSettings()
        var allowed = [.authorized, .provisional, .ephemeral].contains(settings.authorizationStatus)
        if settings.authorizationStatus == .notDetermined {
            allowed = (try? await center.requestAuthorization(options: [.alert, .sound])) == true
        }
        guard allowed, !store.recipeRemoved else { return }
        for id in store.runningTimerIDs {
            guard !store.recipeRemoved else { cancel(store); return }
            guard let timer = store.session.progress.timers[id], timer.checkAt > Date() else { continue }
            let content = UNMutableNotificationContent()
            content.title = "\(store.cell(id).label) · Check now"
            content.body = store.graph.recipe.title
            content.sound = .default
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, timer.checkAt.timeIntervalSinceNow), repeats: false)
            try? await center.add(UNNotificationRequest(identifier: prefix + id, content: content, trigger: trigger))
            if store.recipeRemoved { cancel(store); return }
        }
    }

    @MainActor
    func prepareForegroundAlert() {
        guard UIApplication.shared.applicationState == .active,
              !ProcessInfo.processInfo.arguments.contains("--ui-testing") else { return }
        if feedback == nil { feedback = UINotificationFeedbackGenerator() }
        feedback?.prepare()
    }

    @MainActor
    func foregroundAlert() {
        guard UIApplication.shared.applicationState == .active,
              !ProcessInfo.processInfo.arguments.contains("--ui-testing") else { return }
        if feedback == nil { feedback = UINotificationFeedbackGenerator() }
        feedback?.notificationOccurred(.warning)
        AudioServicesPlaySystemSound(1005)
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        // The table owns the foreground alert; the system notification is for
        // background and locked-screen delivery.
        completionHandler([])
    }
}

@main
struct KitchenTableApp: App {
    @StateObject private var appearance: AppearanceStore
    @StateObject private var walkthrough: WalkthroughStore
    @Environment(\.scenePhase) private var phase
    private let result: Result<RecipeLibrary, Error>

    init() {
        CookingTimerNotifications.shared.configure()
        let testing = ProcessInfo.processInfo.arguments.contains("--ui-testing")
        let defaults = testing ? UserDefaults(suiteName: "local.kitchentable.ui-tests")! : .standard
        if testing && ProcessInfo.processInfo.arguments.contains("--reset-session") { defaults.removePersistentDomain(forName: "local.kitchentable.ui-tests") }
        _walkthrough = StateObject(wrappedValue: WalkthroughStore(defaults: defaults, skip: testing && ProcessInfo.processInfo.arguments.contains("--skip-walkthrough")))
        _appearance = StateObject(wrappedValue: AppearanceStore(defaults: defaults))
        result = Result {
            let directory = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
                .appendingPathComponent("KitchenTable", isDirectory: true)
            let stores = try ["baba-ganoush", "banana-muffins"].map { id in
                let recipe = try Recipe.bundled(id: id)
                let graph = try RecipeGraph(recipe: recipe)
                let layout = try RecipeTableLayout.generated(for: graph)
                // Preserve the original filename and all existing user progress and edits.
                let filename = testing ? "ui-test-session.json" : "\(id)-session.json"
                let url = directory.appendingPathComponent(filename)
                if testing && ProcessInfo.processInfo.arguments.contains("--reset-session") {
                    for source in [url] {
                        try? FileManager.default.removeItem(at: source)
                        try? FileManager.default.removeItem(at: source.deletingPathExtension().appendingPathExtension("edits.json"))
                    }
                }

                let store = SessionStore(graph: graph, fileURL: url, layout: layout)
                store.onPrepareTimerAlert = { CookingTimerNotifications.shared.prepareForegroundAlert() }
                store.onTimerAlert = { CookingTimerNotifications.shared.foregroundAlert() }
                return store
            }
            let incomingRepository: IncomingRecipeRepository
            if testing {
                let testDirectory = directory.appendingPathComponent("ui-test-imports")
                if ProcessInfo.processInfo.arguments.contains("--reset-session") { try? FileManager.default.removeItem(at: testDirectory) }
                incomingRepository = try IncomingRecipeRepository(directory: testDirectory)
                if ProcessInfo.processInfo.arguments.contains("--seed-imports") {
                    try incomingRepository.capture(url: URL(string: "https://example.com/first")!, title: "Sunday baking")
                    try incomingRepository.capture(url: URL(string: "https://example.com/second")!, title: "Dinner inspiration")
                }
            } else {
                incomingRepository = try IncomingRecipeRepository(directory: directory)
            }
            let incoming = try IncomingRecipeStore(repository: incomingRepository)
            return RecipeLibrary(stores: stores, incoming: incoming,
                                 directory: testing ? directory.appendingPathComponent("ui-test-imports") : directory)
        }
    }

    var body: some Scene {
        WindowGroup {
            switch result {
            case .success(let library):
                WalkthroughRoot(library: library, walkthrough: walkthrough)
                    .environmentObject(appearance)
                    .preferredColorScheme(appearance.mode.scheme)
                    .task {
                        library.incoming?.setActive(phase == .active)
                        appearance.setIconsActive(phase == .active && !ProcessInfo.processInfo.arguments.contains("--ui-testing"))
                    }
                    .onChange(of: phase) { _, value in
                        library.incoming?.setActive(value == .active)
                        appearance.setIconsActive(value == .active && !ProcessInfo.processInfo.arguments.contains("--ui-testing"))
                    }

            case .failure(let error): ContentUnavailableView("Recipe unavailable", systemImage: "tablecells", description: Text(error.localizedDescription))
            }
        }
    }
}

struct CookingView: View {
    @EnvironmentObject private var appearance: AppearanceStore
    @ObservedObject var store: SessionStore
    @Environment(\.scenePhase) private var phase
    @Environment(\.dismiss) private var dismiss
    @State private var selected: RecipeCell?
    @State private var resetHint = ""
    @State private var titleFirstLineCenter: CGFloat = 60
    @State private var headerBottom: CGFloat = 84
    @State private var showingCompletion = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var timerScheduleKey: String {
        store.runningTimerIDs.compactMap { id in store.session.progress.timers[id].map { "\(id):\($0.checkAt.timeIntervalSince1970)" } }.joined(separator: "|")
    }

    var body: some View {
        GeometryReader { geometry in
            RecipeGridView(titleFirstLineCenter: $titleFirstLineCenter, store: store, showDetails: { selected = $0 }, backToRecipes: backToRecipes,
                           safeInsets: UIEdgeInsets(top: geometry.safeAreaInsets.top, left: 0, bottom: geometry.safeAreaInsets.bottom, right: 0),
                           onHeaderBottomChange: { headerBottom = $0 },
                           focusTopInset: headerBottom + (store.primaryAttentionID == nil ? 12 : 68), focusBottomInset: 80)
                .ignoresSafeArea(.container, edges: .vertical)
        }
        .overlay(alignment: .bottomLeading) {
            KeepScreenOnButton().padding(.leading, 24).padding(.bottom, 16)
        }
        .overlay(alignment: .bottomTrailing) {
            if store.isComplete && store.celebrationID == nil && !showingCompletion {
                Button(action: finishAndReturn) {
                    Label("Finish", systemImage: "checkmark")
                        .themeFont(appearance.theme, style: .body, emphasized: true)
                        .padding(.horizontal, 18).frame(minHeight: 48)
                        .background(Color(uiColor: appearance.theme.surface), in: Capsule())
                        .shadow(color: .black.opacity(0.10), radius: 8, y: 2)
                }.accessibilityHint("Record this dish and return to Recipe Book")
                    .accessibilityIdentifier("grid.finish")
                    .padding(.trailing, 24).padding(.bottom, 16)
            } else if !store.isComplete && !store.currentIsCentered && store.focusTargetID != nil {
                Button(action: store.requestCurrentStep) {
                    Image(systemName: "scope").font(.system(size: 20, weight: .medium))
                        .frame(width: 48, height: 48)
                        .background(Color(uiColor: appearance.theme.surface), in: Circle())
                        .shadow(color: .black.opacity(0.10), radius: 8, y: 2)
                }
                .accessibilityLabel(store.session.progress.current == nil ? "Active timer" : "Current step")
                .accessibilityHint(store.session.progress.current == nil ? "Center the active timer in the table" : "Center the current step in the table")
                .accessibilityIdentifier("grid.current")
                .disabled(store.isCenteringCurrent)
                .padding(.trailing, 24).padding(.bottom, 16)
            }
        }
        .overlay(alignment: .topTrailing) {
            if !store.session.history.isEmpty {
                VStack(alignment: .trailing, spacing: 8) {
                    HoldUndoButton(undo: store.undo, reset: store.reset, hint: $resetHint)
                        .frame(width: 48, height: 48)
                        .background(Color(uiColor: appearance.theme.surface), in: Circle())
                        .shadow(color: .black.opacity(0.10), radius: 8, y: 2)
                    if !resetHint.isEmpty {
                        Text(resetHint).themeFont(appearance.theme, style: .caption1).padding(.horizontal, 12).padding(.vertical, 8)
                            .background(Color(uiColor: appearance.theme.surface), in: Capsule())
                            .accessibilityIdentifier("progress.resetHint")
                    }
                }.padding(.trailing, 24).padding(.top, max(24, titleFirstLineCenter - 24))
            }
        }
        .overlay(alignment: .top) {
            VStack(spacing: 12) {
            if let id = store.primaryAttentionID {
                Button {
                    store.requestCurrentStep()
                } label: {
                    CookingNotificationPill(icon: "timer",
                                            text: "\(store.cell(id).label) · \(store.timerPresentation(for: id)?.text ?? "Check now")",
                                            additionalCount: store.attentionTimerIDs.count - 1)
                }
                .accessibilityHint("Center the timer that needs attention")
                .accessibilityIdentifier("timer.alert")
            }
                ScreenOnFeedback()
            }.padding(.top, headerBottom + 12).padding(.horizontal, 24)
        }
        .foregroundStyle(Color(uiColor: appearance.theme.ink))
        .background(Color(uiColor: appearance.theme.paper))
        .tint(Color(uiColor: appearance.theme.ink))
        .sheet(item: $selected) { cell in
            CellDetails(store: store, cellID: cell.id, close: { selected = nil })
        }
        .sheet(isPresented: $showingCompletion, onDismiss: { store.cancelCelebration() }) {
            CompletionView(recipeTitle: store.graph.recipe.title, finish: finishAndReturn, cookAgain: { if store.finish() { showingCompletion = false } }, stay: { showingCompletion = false })
        }
        .task(id: store.celebrationID) {
            showingCompletion = false
            guard store.celebrationID != nil else { return }
            if !reduceMotion {
                do { try await Task.sleep(for: .milliseconds(950)) } catch { return }
            }
            guard !Task.isCancelled, store.celebrationID != nil else { return }
            showingCompletion = true
        }
        .task(id: timerScheduleKey) { await CookingTimerNotifications.shared.sync(store) }
        .modifier(CookingScreenAwake())
        .alert("Cooking progress", isPresented: Binding(get: { store.errorMessage != nil }, set: { if !$0 { store.errorMessage = nil } })) {
            Button("OK") { store.errorMessage = nil }
        } message: { Text(store.errorMessage ?? "") }
        .onDisappear { store.isCenteringCurrent = false; store.cancelCelebration(); store.save() }
        .onChange(of: phase) { _, phase in if phase != .active { store.cancelCelebration(); showingCompletion = false; store.save() } }
    }
    private func finishAndReturn() {
        if store.finish() { backToRecipes() }
    }

    private func backToRecipes() {
        showingCompletion = false
        store.cancelCelebration()
        store.save()
        dismiss()
    }
}
