import SwiftUI

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
        store.runningTimerIDs.compactMap { id in
            store.session.progress.timers[id].map { "\(id):\($0.checkAt.timeIntervalSince1970)" }
        }.joined(separator: "|")
    }

    var body: some View {
        GeometryReader { geometry in
            RecipeGridView(
                titleFirstLineCenter: $titleFirstLineCenter,
                store: store,
                showDetails: { selected = $0 },
                backToRecipes: backToRecipes,
                safeInsets: UIEdgeInsets(
                    top: geometry.safeAreaInsets.top,
                    left: 0,
                    bottom: geometry.safeAreaInsets.bottom,
                    right: 0
                ),
                onHeaderBottomChange: { headerBottom = $0 },
                focusTopInset: headerBottom + (store.primaryAttentionID == nil ? 12 : 68),
                focusBottomInset: 80
            )
            .ignoresSafeArea(.container, edges: .vertical)
        }
        .overlay(alignment: .bottomLeading) {
            KeepScreenOnButton().padding(.leading, 24).padding(.bottom, 16)
        }
        .overlay(alignment: .bottomTrailing) { trailingControl }
        .overlay(alignment: .topTrailing) { undoControl }
        .overlay(alignment: .top) { notificationOverlay }
        .foregroundStyle(Color(uiColor: appearance.theme.ink))
        .background(Color(uiColor: appearance.theme.paper))
        .tint(Color(uiColor: appearance.theme.ink))
        .sheet(item: $selected) { cell in
            CellDetails(store: store, cellID: cell.id, close: { selected = nil })
        }
        .sheet(isPresented: $showingCompletion, onDismiss: { store.cancelCelebration() }) {
            CompletionView(
                recipeTitle: store.graph.recipe.title,
                finish: finishAndReturn,
                cookAgain: { if store.finish() { showingCompletion = false } },
                stay: { showingCompletion = false }
            )
        }
        .task(id: store.celebrationID) { await presentCompletion() }
        .task(id: timerScheduleKey) { await CookingTimerNotifications.shared.sync(store) }
        .modifier(CookingScreenAwake())
        .alert("Cooking progress", isPresented: Binding(
            get: { store.errorMessage != nil },
            set: { if !$0 { store.errorMessage = nil } }
        )) {
            Button("OK") { store.errorMessage = nil }
        } message: {
            Text(store.errorMessage ?? "")
        }
        .onDisappear {
            store.isCenteringCurrent = false
            store.cancelCelebration()
            store.save()
        }
        .onChange(of: phase) { _, phase in
            guard phase != .active else { return }
            store.cancelCelebration()
            showingCompletion = false
            store.save()
        }
    }

    @ViewBuilder
    private var trailingControl: some View {
        if store.isComplete && store.celebrationID == nil && !showingCompletion {
            Button(action: finishAndReturn) {
                Label("Finish", systemImage: "checkmark")
                    .themeFont(appearance.theme, style: .body, emphasized: true)
                    .padding(.horizontal, 18)
                    .frame(minHeight: 48)
                    .background(Color(uiColor: appearance.theme.surface), in: Capsule())
                    .shadow(color: .black.opacity(0.10), radius: 8, y: 2)
            }
            .accessibilityHint("Record this dish and return to Recipe Book")
            .accessibilityIdentifier("grid.finish")
            .padding(.trailing, 24)
            .padding(.bottom, 16)
        } else if !store.isComplete && !store.currentIsCentered && store.focusTargetID != nil {
            Button(action: store.requestCurrentStep) {
                Image(systemName: "scope")
                    .font(.system(size: 20, weight: .medium))
                    .frame(width: 48, height: 48)
                    .background(Color(uiColor: appearance.theme.surface), in: Circle())
                    .shadow(color: .black.opacity(0.10), radius: 8, y: 2)
            }
            .accessibilityLabel(store.session.progress.current == nil ? "Active timer" : "Current step")
            .accessibilityHint(store.session.progress.current == nil
                ? "Center the active timer in the table"
                : "Center the current step in the table")
            .accessibilityIdentifier("grid.current")
            .disabled(store.isCenteringCurrent)
            .padding(.trailing, 24)
            .padding(.bottom, 16)
        }
    }

    @ViewBuilder
    private var undoControl: some View {
        if !store.session.history.isEmpty {
            VStack(alignment: .trailing, spacing: 8) {
                HoldUndoButton(undo: store.undo, reset: store.reset, hint: $resetHint)
                    .frame(width: 48, height: 48)
                    .background(Color(uiColor: appearance.theme.surface), in: Circle())
                    .shadow(color: .black.opacity(0.10), radius: 8, y: 2)
                if !resetHint.isEmpty {
                    Text(resetHint)
                        .themeFont(appearance.theme, style: .caption1)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color(uiColor: appearance.theme.surface), in: Capsule())
                        .accessibilityIdentifier("progress.resetHint")
                }
            }
            .padding(.trailing, 24)
            .padding(.top, max(24, titleFirstLineCenter - 24))
        }
    }

    private var notificationOverlay: some View {
        VStack(spacing: 12) {
            if let id = store.primaryAttentionID {
                Button(action: store.requestCurrentStep) {
                    CookingNotificationPill(
                        icon: "timer",
                        text: "\(store.cell(id).label) · \(store.timerPresentation(for: id)?.text ?? "Check now")",
                        additionalCount: store.attentionTimerIDs.count - 1
                    )
                }
                .accessibilityHint("Center the timer that needs attention")
                .accessibilityIdentifier("timer.alert")
            }
            ScreenOnFeedback()
        }
        .padding(.top, headerBottom + 12)
        .padding(.horizontal, 24)
    }

    private func presentCompletion() async {
        showingCompletion = false
        guard store.celebrationID != nil else { return }
        if !reduceMotion {
            do { try await Task.sleep(for: .milliseconds(950)) } catch { return }
        }
        guard !Task.isCancelled, store.celebrationID != nil else { return }
        showingCompletion = true
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
