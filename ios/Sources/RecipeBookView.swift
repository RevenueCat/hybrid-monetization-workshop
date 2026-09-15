import SwiftUI
import Combine

/// Each recipe owns progress, edits, Undo, and its cooking journal entries.
@MainActor
final class RecipeLibrary: ObservableObject {
    // Keep removed sessions for Journal history and lossless Undo. Only the book filters them.
    @Published private var allStores: [SessionStore]
    @Published private(set) var removedIDs: Set<String> = []
    @Published var errorMessage: String?
    private var removalStorageReadable = true
    @Published private var recipeOrder: [String] = []
    private var orderStorageReadable = true
    private var orderedStores: [SessionStore] {
        let unsorted = allStores.filter { !recipeOrder.contains($0.graph.recipe.id) }
        return unsorted + recipeOrder.compactMap { id in allStores.first { $0.graph.recipe.id == id } }
    }
    var stores: [SessionStore] { orderedStores.filter { !removedIDs.contains($0.graph.recipe.id) } }

    func moveRecipes(from source: IndexSet, to destination: Int) {
        guard orderStorageReadable else { return }
        var visible = stores.map { $0.graph.recipe.id }
        guard source.allSatisfy({ visible.indices.contains($0) }), (0...visible.count).contains(destination) else { return }
        visible.move(fromOffsets: source, toOffset: destination)
        var iterator = visible.makeIterator()
        let updated = orderedStores.map { store in
            let id = store.graph.recipe.id
            return removedIDs.contains(id) ? id : iterator.next()!
        }
        do {
            if let directory {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                try JSONEncoder().encode(updated).write(to: directory.appendingPathComponent("recipe-order.json"), options: .atomic)
            }
            recipeOrder = updated
            errorMessage = nil
        } catch { errorMessage = "Couldn’t save recipe order. \(error.localizedDescription)" }
    }
    let incoming: IncomingRecipeStore?
    private let directory: URL?
    private var observations: Set<AnyCancellable> = []

    init(stores: [SessionStore], incoming: IncomingRecipeStore? = nil, directory: URL? = nil) {
        self.allStores = stores
        self.incoming = incoming
        self.directory = directory
        if let url = directory?.appendingPathComponent("removed-recipes.json"), FileManager.default.fileExists(atPath: url.path) {
            do { removedIDs = try JSONDecoder().decode(Set<String>.self, from: Data(contentsOf: url)) }
            catch { removalStorageReadable = false; errorMessage = "Couldn’t read removed recipes. \(error.localizedDescription)" }
        }
        if let url = directory?.appendingPathComponent("recipe-order.json"), FileManager.default.fileExists(atPath: url.path) {
            do {
                let saved = try JSONDecoder().decode([String].self, from: Data(contentsOf: url))
                var seen = Set<String>()
                recipeOrder = saved.filter { seen.insert($0).inserted }
            } catch { orderStorageReadable = false; errorMessage = "Couldn’t read recipe order. \(error.localizedDescription)" }
        }
        for store in stores { store.setRecipeRemoved(removedIDs.contains(store.graph.recipe.id)) }
        incoming?.currentRecipeTitles = { [weak self] in
            self?.stores.map { $0.graph.recipe.title } ?? []
        }
        incoming?.onChange = { [weak self] in
            self?.restoreImports()
        }
        incoming?.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &observations)
        for store in stores {
            store.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }
                .store(in: &observations)
        }
        restoreImports()
    }
    private func restoreImports() {
        guard let incoming, let directory else { return }
        for item in incoming.items where item.status == .complete && !allStores.contains(where: { $0.graph.recipe.id == item.recipeID }) {
            do {
                guard let data = item.preparedRecipe else { throw RecipeError.invalid("The prepared recipe is missing.") }
                let storedRecipe = try JSONDecoder().decode(Recipe.self, from: data)
                // Imports created before template metadata existed were all
                // Banana Muffins; newer imports retain their originating recipe.
                let templateID = item.mockTemplateID ?? "banana-muffins"
                let template = try Recipe.bundled(id: templateID)
                let recipe = Recipe(schemaVersion: storedRecipe.schemaVersion, id: storedRecipe.id,
                                    title: storedRecipe.title, yield: storedRecipe.yield,
                                    photo: storedRecipe.photo, sourceUrl: storedRecipe.sourceUrl,
                                    ingredients: storedRecipe.ingredients, steps: storedRecipe.steps)
                let templateOrder = try RecipeGraph(recipe: template).order
                let graph = try RecipeGraph(recipe: recipe, displayOrder: templateOrder)
                let layout = try RecipeTableLayout.generated(for: graph)
                let store = SessionStore(graph: graph, fileURL: directory.appendingPathComponent("\(recipe.id)-session.json"), layout: layout)
                store.onPrepareTimerAlert = { CookingTimerNotifications.shared.prepareForegroundAlert() }
                store.onTimerAlert = { CookingTimerNotifications.shared.foregroundAlert() }
                store.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &observations)
                store.setRecipeRemoved(removedIDs.contains(recipe.id))
                allStores.insert(store, at: 0)
            } catch { incoming.errorMessage = "Couldn’t open a prepared recipe. \(error.localizedDescription)" }
        }
    }
    @discardableResult
    func setRemoved(_ id: String, removed: Bool) -> Bool {
        guard removalStorageReadable, let store = allStores.first(where: { $0.graph.recipe.id == id }) else { return false }
        var updated = removedIDs
        if removed { updated.insert(id) } else { updated.remove(id) }
        do {
            if let directory {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                try JSONEncoder().encode(updated).write(to: directory.appendingPathComponent("removed-recipes.json"), options: .atomic)
            }
            removedIDs = updated
            store.setRecipeRemoved(removed)
            errorMessage = nil
            return true
        } catch { errorMessage = "Couldn’t update your recipe book. \(error.localizedDescription)"; return false }
    }
    func store(for id: String) -> SessionStore? { stores.first { $0.graph.recipe.id == id } }
    var dishesCooked: Int {
        allStores.reduce(0) { total, store in
            let statistics = store.session.statistics
            return total + max(statistics?.dishesCompleted ?? 0, statistics?.journalEntries.count ?? 0)
        }
    }
    var uniqueDishesCooked: Int {
        let recordedRecipeIDs = allStores.compactMap { store -> String? in
            guard let statistics = store.session.statistics,
                  statistics.dishesCompleted > 0 || !statistics.journalEntries.isEmpty else { return nil }
            return store.graph.recipe.id
        }
        return Set(recordedRecipeIDs + journalEntries.map(\.recipeID)).count
    }
    var journalEntries: [CookingJournalEntry] {
        allStores.flatMap { $0.session.statistics?.journalEntries ?? [] }
            .sorted {
                if $0.completedAt != $1.completedAt { return $0.completedAt > $1.completedAt }
                return $0.id > $1.id
            }
    }
}

struct RecipeBookView: View {
    @EnvironmentObject private var appearance: AppearanceStore
    @ObservedObject var library: RecipeLibrary
    var openWalkthrough: () -> Void = {}
    @State private var path: [String] = []
    @State private var showingAddRecipe = false
    @State private var editingRecipes = false
    @State private var revealedRecipeID: String?
    @State private var revealedBinFrame: CGRect = .zero
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private enum RemovalUndo {
        case recipe(String)
        case incoming(IncomingRecipeStore.DiscardedImport)
        var message: String {
            switch self {
            case .recipe: "Recipe removed"
            case .incoming: "Import discarded"
            }
        }
    }
    @State private var removals: [RemovalUndo] = []
    @State private var feedbackRevision = 0
    @State private var dismissalInterval: DateInterval?
    @State private var headerBottom: CGFloat = 150
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled
    @State private var titleFirstLineCenter: CGFloat = 60

    private func incomingItem(for store: SessionStore) -> IncomingRecipe? {
        library.incoming?.visibleItems.first { $0.recipeID == store.graph.recipe.id && $0.status == .complete }
    }

    private func cookingStatus(_ store: SessionStore) -> String {
        let states = store.session.progress.states.values
        if states.allSatisfy({ $0 == .pending }) { return "Start cooking" }
        if store.isComplete {
            return "Ready to finish · View table"
        }
        let completed = states.filter { $0 == .complete }.count
        return completed > 0 ? "Continue cooking · \(completed) completed" : "Continue cooking"
    }

    var body: some View {
        NavigationStack(path: $path) {
            List {
                    VStack(alignment: .leading, spacing: 6) {
                        PageHeading(title: "Recipe Book", accessibilityPrefix: "book",
                                    titleCoordinateSpace: .named("book.header")) {
                            titleFirstLineCenter = $0
                        }
                        .frame(minHeight: 48)
                        Text(library.stores.count == 1 ? "1 recipe" : "\(library.stores.count) recipes")
                            .themeFont(appearance.theme, style: .subheadline)
                            .foregroundStyle(Color(uiColor: appearance.theme.muted))
                            .padding(.top, 6)
                    }.padding(.trailing, 64).padding(.top, 20).padding(.bottom, 28)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .overlay(alignment: .topTrailing) {
                            Group {
                                if editingRecipes {
                                    Button {
                                        revealedRecipeID = nil
                                        editingRecipes = false
                                    } label: {
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 20, weight: .semibold))
                                            .frame(width: 48, height: 48, alignment: .trailing)
                                            .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel("Done editing recipes")
                                    .accessibilityIdentifier("book.edit.done")
                                } else { bookMenu }
                            }.padding(.top, titleFirstLineCenter - 24)
                        }
                        .coordinateSpace(name: "book.header")
                        .onGeometryChange(for: CGFloat.self) { $0.frame(in: .named("book.viewport")).maxY } action: { headerBottom = $0 }
                        .overlay(alignment: .bottom) {
                            Rectangle().fill(Color(uiColor: appearance.theme.line)).frame(height: 0.5)
                        }
                        .listRowInsets(EdgeInsets(top: 0, leading: 24, bottom: 0, trailing: 24))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color(uiColor: appearance.theme.paper))

                    if let incoming = library.incoming {
                        IncomingRecipeSection(incoming: incoming, discardImport: discardImport)
                            .listRowInsets(EdgeInsets(top: 0, leading: 24, bottom: 0, trailing: 24))
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color(uiColor: appearance.theme.paper))
                    }
                    ForEach(library.stores, id: \.graph.recipe.id) { store in
                        VStack(spacing: 0) {
                            Button {
                                guard !editingRecipes, revealedRecipeID != store.graph.recipe.id else { return }
                                path.append(store.graph.recipe.id)
                            } label: {
                                RecipeBookRow(title: store.graph.recipe.title, subtitle: cookingStatus(store)) {
                                    Image(systemName: "chevron.right")
                                        .accessibilityHidden(true)
                                }
                            }
                            .buttonStyle(.plain)
                            .allowsHitTesting(!editingRecipes && revealedRecipeID != store.graph.recipe.id)
                            .accessibilityLabel(incomingItem(for: store).map { _ in "Start cooking" } ?? "\(store.graph.recipe.title), \(cookingStatus(store))")
                            .accessibilityIdentifier(incomingItem(for: store).map { "incoming.action.\($0.title)" } ?? "book.open.\(store.graph.recipe.id)")
                        }
                        .modifier(RecipeRemovalActions(revealed: Binding(
                            get: { revealedRecipeID == store.graph.recipe.id },
                            set: { if $0 { revealedRecipeID = store.graph.recipe.id } else if revealedRecipeID == store.graph.recipe.id { revealedRecipeID = nil } }
                        ), editing: editingRecipes, title: "Remove", recipeTitle: store.graph.recipe.title) { removeRecipe(store.graph.recipe.id) })
                        .padding(.bottom, 0.5)
                        .overlay(alignment: .bottom) {
                            Rectangle().fill(Color(uiColor: appearance.theme.line)).frame(height: 0.5)
                        }
                        .listRowInsets(EdgeInsets(top: 0, leading: 24, bottom: 0, trailing: 24))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color(uiColor: appearance.theme.paper))
                    }
                    .onMove(perform: library.moveRecipes)
                    .moveDisabled(!editingRecipes)
            }
            .accessibilityIdentifier("recipe.book")
            .coordinateSpace(name: "book.viewport")
            .onPreferenceChange(RevealedRecipeBinFrame.self) { revealedBinFrame = $0 }
            .simultaneousGesture(SpatialTapGesture(coordinateSpace: .named("book.viewport")).onEnded { value in
                guard revealedRecipeID != nil, !revealedBinFrame.contains(value.location) else { return }
                withAnimation(reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.9)) {
                    revealedRecipeID = nil
                }
            })
            .overlay(alignment: .top) {
                GeometryReader { geometry in
                    if let removal = removals.last {
                        Button(action: undoRemoval) {
                            CookingNotificationPill(icon: "arrow.uturn.backward", text: "\(removal.message) · Undo",
                                                    dismissalInterval: dismissalInterval)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(removal.message). Undo")
                        .accessibilityIdentifier("book.removal.undo")
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 24)
                        .padding(.top, max(12, headerBottom - geometry.frame(in: .named("book.viewport")).minY + 12))
                    }
                }
            }
            .task(id: feedbackRevision) {
                dismissalInterval = nil
                guard !removals.isEmpty, !voiceOverEnabled else { return }
                let interval = DateInterval(start: Date(), duration: 3)
                dismissalInterval = interval
                do { try await Task.sleep(for: .seconds(max(0, interval.end.timeIntervalSinceNow))) } catch { return }
                removals = []
                dismissalInterval = nil
            }
            .alert("Recipe Book", isPresented: Binding(get: { library.errorMessage != nil }, set: { if !$0 { library.errorMessage = nil } })) {
                Button("OK") { library.errorMessage = nil }
            } message: { Text(library.errorMessage ?? "") }
            .contentMargins(.bottom, 88, for: .scrollContent)
            .overlay(alignment: .bottomTrailing) {
                if !editingRecipes && library.incoming != nil {
                    Button {
                        revealedRecipeID = nil
                        showingAddRecipe = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 22, weight: .medium))
                            .frame(width: 56, height: 56)
                            .foregroundStyle(Color(uiColor: appearance.theme.muted))
                            .background(Color(uiColor: appearance.theme.surface), in: Circle())
                            .overlay(Circle().stroke(Color(uiColor: appearance.theme.line), lineWidth: 0.5))
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .shadow(color: .black.opacity(0.06), radius: 6, y: 2)
                    .accessibilityLabel("Import recipe")
                    .accessibilityIdentifier("book.addRecipe")
                    .padding(.trailing, 24)
                    .padding(.bottom, 16)
                }
            }
            .sheet(isPresented: $showingAddRecipe) {
                if let incoming = library.incoming {
                    AddRecipeFromLinkSheet(incoming: incoming)
                }
            }
            .listStyle(.plain)
            .environment(\.defaultMinListRowHeight, 0)
            .scrollContentBackground(.hidden)
            .navigationTitle("Recipe Book")
            .background(Color(uiColor: appearance.theme.paper))
            .foregroundStyle(Color(uiColor: appearance.theme.ink))
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: String.self) { destination in
                if destination == "settings" { SettingsView() }
                else if destination == "themes" { ThemesView() }
                else if destination == "journal" { JournalView(library: library) }
                else if let store = library.store(for: destination) {
                    CookingView(store: store).id(destination).toolbar(.hidden, for: .navigationBar)
                }
            }
        }
        .tint(Color(uiColor: appearance.theme.ink))
        .onAppear { library.incoming?.beginBookVisit() }
        .onChange(of: path) { previous, current in
            if !previous.isEmpty && current.isEmpty { library.incoming?.beginBookVisit() }
        }
    }

    private func discardImport(_ item: IncomingRecipe) {
        guard let discarded = library.incoming?.remove(item.id) else { return }
        removals.append(.incoming(discarded))
        feedbackRevision += 1
    }

    private func undoRemoval() {
        revealedRecipeID = nil
        guard let removal = removals.last else { return }
        let restored: Bool
        switch removal {
        case .recipe(let id): restored = library.setRemoved(id, removed: false)
        case .incoming(let discarded): restored = library.incoming?.restore(discarded) ?? false
        }
        guard restored else { return }
        removals.removeLast()
        feedbackRevision += 1
    }

    private func removeRecipe(_ id: String) {
        guard library.setRemoved(id, removed: true) else { return }
        removals.append(.recipe(id))
        feedbackRevision += 1
    }

    private var bookMenu: some View {
        Menu {
            Button("Edit recipes", systemImage: "trash") { editingRecipes = true }
            Button("Walkthrough", systemImage: "hand.tap", action: openWalkthrough)
            Button("Journal", systemImage: "book.closed") { path.append("journal") }
            Button("Themes", systemImage: "paintpalette") { path.append("themes") }
            Button("Settings", systemImage: "gearshape") { path.append("settings") }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 20, weight: .medium))
                .frame(width: 48, height: 48, alignment: .trailing)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Menu")
        .accessibilityIdentifier("book.menu")
    }

}

private extension EnvironmentValues {
    @Entry var recipeRemovalProgress: CGFloat = 0
}

struct RecipeBookRow<Accessory: View>: View {
    @Environment(\.recipeRemovalProgress) private var removalProgress
    @EnvironmentObject private var appearance: AppearanceStore
    let title: String
    let subtitle: String
    var secondaryColor: UIColor? = nil
    @ViewBuilder var accessory: () -> Accessory

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 7) {
                Text(appearance.theme.title(title)).themeTitleFont(appearance.theme, size: 20)
                    .foregroundStyle(Color(uiColor: appearance.theme.ink))
                    .fixedSize(horizontal: false, vertical: true)
                Text(subtitle).themeFont(appearance.theme, style: .caption1)
                    .foregroundStyle(Color(uiColor: secondaryColor ?? appearance.theme.muted))

            }.frame(maxWidth: .infinity, alignment: .leading)
            accessory().opacity(1 - removalProgress).themeFont(appearance.theme, style: .body, emphasized: true)
                .foregroundStyle(Color(uiColor: secondaryColor ?? appearance.theme.muted))
        }.padding(.vertical, 20).contentShape(Rectangle())
    }
}

/// The separators belong to the enclosing row, outside this moving content.
struct RecipeRemovalActions: ViewModifier {
    @EnvironmentObject private var appearance: AppearanceStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding var revealed: Bool
    let editing: Bool
    var enabled = true
    let title: String
    let recipeTitle: String
    let remove: () -> Void
    @State private var dragOffset: CGFloat?
    @State private var dragOrigin: CGFloat = 0
    @State private var wasOpen = false
    private let revealWidth: CGFloat = 56

    private var offset: CGFloat { dragOffset ?? (revealed ? revealWidth : 0) }
    private var spring: Animation? { reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.9) }

    func body(content: Content) -> some View {
        if enabled {
            RecipeRemovalReveal(offset: offset, editProgress: editing ? 1 : 0, swiping: revealed || dragOffset != nil) {
                content
            } bin: {
                Button {
                    revealed = false
                    remove()
                } label: {
                    Image(systemName: "trash")
                        .foregroundStyle(Color(uiColor: appearance.theme.muted))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .allowsHitTesting(editing || (revealed && dragOffset == nil))
                .accessibilityHidden(!editing && !revealed)
                .accessibilityLabel("\(title) \(recipeTitle)")
                .background {
                    GeometryReader { geometry in
                        Color.clear.preference(key: RevealedRecipeBinFrame.self,
                            value: revealed && !editing ? geometry.frame(in: .named("book.viewport")) : .zero)
                    }
                }
            }
            .clipped()
            .accessibilityElement(children: .contain)
            .contentShape(Rectangle())
            .animation(spring, value: offset)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.42), value: editing)
            .transaction { if dragOffset != nil { $0.animation = nil } }
            .gesture(RecipeRowSwipeCapture(enabled: !editing, changed: { translation, began in
                if began {
                    wasOpen = revealed
                    dragOrigin = revealed ? revealWidth : 0
                    dragOffset = dragOrigin
                    revealed = true
                }
                let proposed = max(0, dragOrigin - translation)
                // Track the finger directly until fully revealed, then add gentle resistance.
                dragOffset = proposed <= revealWidth ? proposed : revealWidth + min(28, (proposed - revealWidth) * 0.18)
            }, ended: { translation, velocity, cancelled in
                let projected = dragOrigin - translation - velocity * 0.12
                withAnimation(spring) {
                    revealed = cancelled ? wasOpen : projected > revealWidth / 2
                    dragOffset = nil
                }
            }))
            .onChange(of: editing) { _, _ in revealed = false; dragOffset = nil }
            .accessibilityAction(named: "\(title) \(recipeTitle)", remove)
        } else {
            content
        }
    }
}

/// Interpolate edit layout separately from swipe tracking so neither transition snaps.
private struct RecipeRemovalReveal<Content: View, Bin: View>: View, Animatable {
    var offset: CGFloat
    var editProgress: CGFloat
    var swiping: Bool
    @ViewBuilder var content: () -> Content
    @ViewBuilder var bin: () -> Bin

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(offset, editProgress) }
        set { offset = newValue.first; editProgress = newValue.second }
    }

    var body: some View {
        let progress = min(1, max(0, editProgress))
        let space = max(offset, 56 * progress)
        let swipeOpacity = min(1, max(0, (offset - 28) / 20))
        ZStack(alignment: .trailing) {
            if space > 0 {
                bin()
                    .transition(.identity)
                    .opacity(max(progress, swipeOpacity))
                    .mask(alignment: .trailing) {
                        Rectangle().frame(width: max(0, space))
                    }
            }
            content()
                .environment(\.recipeRemovalProgress, max(progress, swiping ? 1 : 0))
                .transaction { $0.animation = nil }
                .padding(.trailing, 56 * progress)
                .offset(x: -offset * (1 - progress))
        }
    }
}

struct RevealedRecipeBinFrame: PreferenceKey {
    static var defaultValue: CGRect { .zero }
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        let next = nextValue()
        if next != .zero { value = next }
    }
}

/// Reject vertical pans before recognition so the book keeps its native scrolling.
private struct RecipeRowSwipeCapture: UIGestureRecognizerRepresentable {
    let enabled: Bool
    let changed: (CGFloat, Bool) -> Void
    let ended: (CGFloat, CGFloat, Bool) -> Void

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator { Coordinator() }
    func makeUIGestureRecognizer(context: Context) -> UIPanGestureRecognizer {
        let recognizer = UIPanGestureRecognizer()
        recognizer.maximumNumberOfTouches = 1
        recognizer.delegate = context.coordinator
        recognizer.cancelsTouchesInView = true
        recognizer.isEnabled = enabled
        return recognizer
    }
    func updateUIGestureRecognizer(_ recognizer: UIPanGestureRecognizer, context: Context) {
        recognizer.isEnabled = enabled
    }
    func handleUIGestureRecognizerAction(_ recognizer: UIPanGestureRecognizer, context: Context) {
        let translation = recognizer.translation(in: recognizer.view).x
        switch recognizer.state {
        case .began, .changed:
            changed(translation, recognizer.state == .began)
        case .ended, .cancelled:
            ended(translation, recognizer.velocity(in: recognizer.view).x, recognizer.state == .cancelled)
        default: break
        }
    }
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard let pan = gestureRecognizer as? UIPanGestureRecognizer else { return false }
            let velocity = pan.velocity(in: pan.view)
            return abs(velocity.x) > abs(velocity.y) * 1.5
        }
    }
}
