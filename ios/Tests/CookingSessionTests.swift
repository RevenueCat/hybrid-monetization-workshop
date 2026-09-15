import XCTest
import UIKit
import SwiftUI
@testable import KitchenTable

final class CookingSessionTests: XCTestCase {
    @MainActor
    func testThemeIconAutomaticallyFollowsSavedThemeAndForegroundChanges() async throws {
        let suite = "icon-tests-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let client = TestAppIconClient()
        let store = AppearanceStore(defaults: defaults, iconClient: client)
        defaults.set("ferran", forKey: "theme")
        defaults.set(false, forKey: "matchAppIconToTheme")
        let restored = AppearanceStore(defaults: defaults, iconClient: client)
        XCTAssertEqual(restored.theme, .ferran)
        store.theme = restored.theme
        XCTAssertTrue(client.requests.isEmpty)
        store.setIconsActive(true)
        await settleIcon(store)
        XCTAssertEqual(client.alternateIconName, "AppIcon-studio")
        store.setIconsActive(false)
        store.theme = .manual
        XCTAssertEqual(client.requests.count, 1)
        store.setIconsActive(true)
        await settleIcon(store)
        XCTAssertEqual(client.alternateIconName, "AppIcon-classic")
        store.syncAppIcon()
        XCTAssertEqual(client.requests.count, 2)
        store.theme = .original
        await settleIcon(store)
        XCTAssertNil(client.alternateIconName)
        XCTAssertEqual(client.requests.count, 3)
    }

    @MainActor
    func testThemeIconLatestSelectionAndFailureRecovery() async {
        let suite = "icon-tests-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let client = TestAppIconClient()
        let store = AppearanceStore(defaults: defaults, iconClient: client)
        store.setIconsActive(true)
        store.theme = .ferran
        store.theme = .genius
        await settleIcon(store)
        XCTAssertEqual(client.requests, ["AppIcon-studio", "AppIcon-archive"])
        client.shouldFail = true
        store.theme = .dinner
        await settleIcon(store)
        XCTAssertNotNil(store.iconError)
        XCTAssertEqual(store.theme, .dinner)
        XCTAssertEqual(client.alternateIconName, "AppIcon-archive")
        let count = client.requests.count
        store.setIconsActive(true)
        XCTAssertEqual(client.requests.count, count)
        client.shouldFail = false
        store.syncAppIcon()
        await settleIcon(store)
        XCTAssertNil(store.iconError)
        XCTAssertEqual(client.alternateIconName, "AppIcon-editorial")
    }

    @MainActor
    private func settleIcon(_ store: AppearanceStore) async {
        for _ in 0..<100 where store.isChangingIcon {
            try? await Task.sleep(for: .milliseconds(5))
        }
        XCTAssertFalse(store.isChangingIcon)
    }

    @MainActor
    func testPinnedWalkthroughHeaderStaysVisibleWhenTableScrolls() throws {
        let (_, scroll, window, _) = try entryFixture()
        scroll.pinsHeader = true
        scroll.layoutIfNeeded()
        let header = try XCTUnwrap(scroll.subviews.first { $0.accessibilityIdentifier == "navigation.recipes" })
        let before = header.convert(header.bounds, to: window)
        scroll.setContentOffset(CGPoint(x: 100, y: 200), animated: false)
        let after = header.convert(header.bounds, to: window)
        XCTAssertEqual(after.minX, before.minX, accuracy: 0.5)
        XCTAssertEqual(after.minY, before.minY, accuracy: 0.5)
        XCTAssertFalse(header.isHidden)
        XCTAssertTrue(header.isUserInteractionEnabled)
    }

    @MainActor
    private func entryFixture() throws -> (SessionStore, RecipeScrollView, UIWindow, URL) {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        let recipeGraph = try graph()
        var saved = CookingSession(graph: recipeGraph)
        // Pin a distant current action: this test concerns entry animation,
        // not the layout-dependent suggestion after completing a merge.
        saved.progress.current = "mix"
        try JSONEncoder().encode(saved).write(to: url)
        let store = SessionStore(graph: recipeGraph, fileURL: url)
        store.recordScroll(x: 450, y: 850)
        let scroll = RecipeScrollView(store: store, showDetails: { _ in }, backToRecipes: {},
                                      safeInsets: UIEdgeInsets(top: 59, left: 0, bottom: 34, right: 0),
                                      theme: .original, density: .compact)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        let controller = UIViewController()
        window.rootViewController = controller
        window.isHidden = false
        scroll.frame = window.bounds
        controller.view.addSubview(scroll)
        scroll.layoutIfNeeded()
        return (store, scroll, window, url)
    }

    @MainActor
    func testRecipeEntryWaitsForAppearanceAndTitlePause() async throws {
        try XCTSkipIf(UIAccessibility.isReduceMotionEnabled, "Reduced motion intentionally skips the pause")
        let (_, scroll, window, url) = try entryFixture()
        defer { window.isHidden = true; try? FileManager.default.removeItem(at: url) }
        XCTAssertEqual(scroll.contentOffset, .zero, "Saved scrolling must not hide the title on entry")
        try await Task.sleep(for: .milliseconds(250))
        XCTAssertEqual(scroll.contentOffset, .zero, "Layout alone must not trigger centering")
        scroll.scheduleEntryCentering()
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(scroll.contentOffset, .zero, "Keep the heading still during the entry pause")
        try await Task.sleep(for: .milliseconds(700))
        XCTAssertNotEqual(scroll.contentOffset, .zero, "Center the current step after the pause")
    }

    @MainActor
    func testRecipeEntryCancellationDoesNotRearmOnAppearance() async throws {
        for interruption in ["drag", "background", "departure"] {
            let (_, scroll, window, url) = try entryFixture()
            defer { window.isHidden = true; try? FileManager.default.removeItem(at: url) }
            scroll.scheduleEntryCentering()
            switch interruption {
            case "drag": scroll.scrollViewWillBeginDragging(scroll)
            case "background": NotificationCenter.default.post(name: UIApplication.willResignActiveNotification, object: nil)
            default: scroll.removeFromSuperview()
            }
            scroll.scheduleEntryCentering()
            try await Task.sleep(for: .milliseconds(350))
            XCTAssertEqual(scroll.contentOffset, .zero, "\(interruption) must permanently cancel this entry's automatic movement")
        }
    }

    @MainActor
    func testExplicitCenteringSupersedesPendingEntry() async throws {
        let (_, scroll, window, url) = try entryFixture()
        defer { window.isHidden = true; try? FileManager.default.removeItem(at: url) }
        scroll.scheduleEntryCentering()
        scroll.centerCurrent()
        // An explicit request is immediate; the entry timer must not move it again.
        scroll.setContentOffset(CGPoint(x: 30, y: 40), animated: false)
        try await Task.sleep(for: .milliseconds(350))
        XCTAssertEqual(scroll.contentOffset, CGPoint(x: 30, y: 40))
    }

    @MainActor
    func testHeaderReservesTwentyPointsBelowTitleAndUndoAcrossThemes() throws {
        func descendants(_ view: UIView) -> [UIView] {
            view.subviews.flatMap { [$0] + descendants($0) }
        }
        for theme in AppTheme.allCases {
            let store = SessionStore(graph: try graph(), fileURL: URL(fileURLWithPath: "/header-test"), persists: false)
            let scroll = RecipeScrollView(store: store, showDetails: { _ in }, backToRecipes: {},
                                          safeInsets: .zero, theme: theme, density: .compact)
            scroll.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
            scroll.layoutIfNeeded()
            let views = descendants(scroll)
            let heading = try XCTUnwrap(views.first { $0.accessibilityIdentifier == "navigation.recipes" })
            let title = try XCTUnwrap(views.first { $0.accessibilityIdentifier == "recipe.title" } as? UILabel)
            let firstCell = try XCTUnwrap(views.first { $0.accessibilityIdentifier == "cell.preheat" })
            let titleFrame = title.convert(title.bounds, to: scroll)
            let undoBottom = titleFrame.minY + title.font.lineHeight / 2 + 24
            let tableTop = firstCell.convert(firstCell.bounds, to: scroll).minY
            XCTAssertGreaterThanOrEqual(tableTop - undoBottom, 19.9, theme.rawValue)
            XCTAssertGreaterThanOrEqual(tableTop - heading.frame.maxY, 19.9, theme.rawValue)
            let offset = CGPoint(x: 80, y: 30)
            scroll.setContentOffset(offset, animated: false)
            scroll.automaticallyCenters = false
            scroll.refresh()
            XCTAssertTrue(scroll.isScrollEnabled)
            XCTAssertEqual(scroll.contentOffset, offset, "Pausing automatic guidance must not reset the viewport")
        }
    }

    private func runtimeFixture() -> [String: Any] {
        ["schema_version": 1, "id": "example", "title": "Example", "yield": "2 portions",
         "source_url": "https://example.com/recipe",
         "ingredients": [["id": "supply", "name": "Supply", "instruction": "Ingredient detail."]],
         "steps": [
            ["id": "prepare", "action": "Prepare", "inputs": [["ingredient": "supply"]],
             "outputs": [["id": "prepared", "name": "Prepared supply"]], "instruction": "Current cooking instruction."],
            ["id": "finish-dish", "action": "Finish", "inputs": [["output": "prepared"]], "outputs": []]
         ]]
    }
    private func fixtureGraph(_ value: [String: Any]) throws -> RecipeGraph {
        let recipe = try Recipe.decode(JSONSerialization.data(withJSONObject: value))
        return try RecipeGraph(recipe: recipe)
    }
    func testRuntimeContractAndDirectInstructions() throws {
        let graph = try fixtureGraph(runtimeFixture())
        XCTAssertEqual(graph.recipe.schemaVersion, 1)
        XCTAssertEqual(graph.recipe.yield, "2 portions")
        XCTAssertEqual(graph.recipe.sourceUrl, "https://example.com/recipe")
        XCTAssertNil(graph.cells["supply"]?.amount)
        XCTAssertEqual(graph.cells["supply"]?.instruction, "Ingredient detail.")
        XCTAssertEqual(graph.cells["prepare"]?.instruction, "Current cooking instruction.")
        XCTAssertEqual(graph.cells["finish-dish"]?.dependencies, ["prepare"])
    }
    func testBananaMuffinsBundleAndLayoutMatch() throws {
        let recipe = try Recipe.bundled(id: "banana-muffins")
        let graph = try RecipeGraph(recipe: recipe)
        let layout = try RecipeTableLayout.generated(for: graph)
        XCTAssertEqual(recipe.yield, "10–12 muffins")
        XCTAssertEqual(graph.cells["bake-hot"]?.amount, "5 min")
        XCTAssertEqual(graph.cells["bake-through"]?.amount, "16–18 min")
        XCTAssertEqual(Set(layout.order), Set(recipe.ingredients.map(\.id) + recipe.steps.map(\.id)))
        XCTAssertEqual(graph.cells["combine"]?.dependencies.sorted(), ["add-ins", "mix-wet", "whisk-dry"])
        XCTAssertEqual(graph.cells["fill-pan"]?.dependencies.sorted(), ["combine", "prepare-pan"])
        XCTAssertEqual(graph.cells["prepare-pan"]?.dependencies, ["pan-prep"])
        XCTAssertEqual(graph.cells["bake-hot"]?.dependencies.sorted(), ["fill-pan", "preheat"])
        XCTAssertEqual(graph.cells["bake-through"]?.dependencies, ["bake-hot"])
        for laterID in ["pan-prep", "prepare-pan"] {
            XCTAssertGreaterThan(try XCTUnwrap(layout.order.firstIndex(of: laterID)),
                                 try XCTUnwrap(layout.order.firstIndex(of: "whisk-dry")))
            XCTAssertGreaterThan(try XCTUnwrap(layout.order.firstIndex(of: laterID)),
                                 try XCTUnwrap(layout.order.firstIndex(of: "mix-wet")))
        }
        XCTAssertNoThrow(try layout.validate(for: graph))
    }
    func testBananaMuffinsSuggestsCombineBeforeIndependentPreparation() throws {
        let graph = try RecipeGraph(recipe: Recipe.bundled(id: "banana-muffins"))
        var session = CookingSession(graph: graph)
        for ingredient in graph.ingredientOrder { session.toggle(ingredient, graph: graph) }
        session.toggle("whisk-dry", graph: graph)
        session.toggle("mix-wet", graph: graph)
        XCTAssertEqual(session.progress.current, "combine")
        XCTAssertEqual(session.progress.states["preheat"], .pending)
        XCTAssertEqual(session.progress.states["prepare-pan"], .pending)
    }
    @MainActor
    func testBananaMuffinsIngredientSuggestionFollowsTableReadingOrder() throws {
        let graph = try RecipeGraph(recipe: Recipe.bundled(id: "banana-muffins"))
        let layout = try RecipeTableLayout.generated(for: graph)
        let store = SessionStore(graph: graph, fileURL: URL(fileURLWithPath: "/banana-reading-order-memory-only"),
                                 persists: false, layout: layout)
        for id in ["flour", "baking-powder", "baking-soda", "salt", "cinnamon", "nutmeg"] {
            store.toggle(id)
        }
        XCTAssertEqual(store.session.progress.current, "bananas")
        XCTAssertEqual(layout.readingOrder.filter { graph.cells[$0]?.isIngredient == true }
            .drop { $0 != "nutmeg" }.prefix(2), ["nutmeg", "bananas"])
    }
    func testRuntimeContractRejectsInvalidFieldsAndDependencies() throws {
        var bad = runtimeFixture(); bad["schema_version"] = 2
        XCTAssertThrowsError(try fixtureGraph(bad))
        bad = runtimeFixture(); bad["review_issues"] = []
        XCTAssertThrowsError(try fixtureGraph(bad))
        bad = runtimeFixture(); bad["photo"] = "../photo.jpg"
        XCTAssertThrowsError(try fixtureGraph(bad))
        bad = runtimeFixture(); bad["yield"] = NSNull()
        XCTAssertThrowsError(try fixtureGraph(bad))
        bad = runtimeFixture(); bad["id"] = "example\n"
        XCTAssertThrowsError(try fixtureGraph(bad))
        bad = runtimeFixture(); bad["photo"] = "photo.jpg\n"
        XCTAssertThrowsError(try fixtureGraph(bad))
        for alteration in ["ambiguous", "missing", "cycle", "duplicate-output", "range", "unassigned"] {
            bad = runtimeFixture()
            var steps = bad["steps"] as! [[String: Any]]
            switch alteration {
            case "ambiguous": steps[0]["inputs"] = [["ingredient": "supply", "output": "prepared"]]
            case "missing": steps[1]["inputs"] = [["output": "missing"]]
            case "cycle": steps[0]["after"] = ["finish-dish"]
            case "duplicate-output": steps[1]["outputs"] = [["id": "prepared", "name": "Duplicate"]]
            case "range": steps[0]["duration"] = ["min": 20, "max": 10, "unit": "min"]
            default: steps[0]["inputs"] = []
            }
            bad["steps"] = steps
            XCTAssertThrowsError(try fixtureGraph(bad), alteration)
        }
    }
    func testSharedOutputsAndArrayOrderDoNotSerializeBranches() throws {
        var value = runtimeFixture()
        var steps = value["steps"] as! [[String: Any]]
        steps.append(["id": "garnish", "action": "Garnish", "inputs": [["output": "prepared", "optional": true, "allocation": "Reserved"]], "outputs": []])
        value["steps"] = Array(steps.reversed())
        let graph = try fixtureGraph(value)
        XCTAssertEqual(graph.cells["garnish"]?.dependencies, ["prepare"])
        XCTAssertEqual(graph.cells["finish-dish"]?.dependencies, ["prepare"])
    }
    @MainActor
    func testRecipeCompletionDoesNotRequireServeIdentifier() throws {
        let graph = try fixtureGraph(runtimeFixture())
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = SessionStore(graph: graph, fileURL: folder.appendingPathComponent("session.json"))
        XCTAssertFalse(store.isComplete)
        store.toggle("finish-dish")
        XCTAssertTrue(store.isComplete)
        XCTAssertTrue(store.finish())
        XCTAssertFalse(store.isComplete)
        XCTAssertTrue(store.session.history.isEmpty)
    }
    private func graph() throws -> RecipeGraph {
        try RecipeGraph(recipe: Recipe.bundled())
    }

    func testBundledRecipeAndMergeDependencies() throws {
        let graph = try graph()
        XCTAssertEqual(graph.cells.count, 20)
        XCTAssertEqual(Set(graph.cells["roast-eggplant"]!.dependencies), ["preheat", "cut-eggplant"])
        XCTAssertEqual(Set(graph.cells["mix"]!.dependencies), ["extract-flesh", "blend-base"])
        XCTAssertEqual(graph.cells["roast-eggplant"]!.amount, "≈60 min")
        XCTAssertEqual(graph.cells["roast-garlic"]!.amount, "35–40 min")
    }

    func testCompletionAndUndoAreWholeDependencyActions() throws {
        let graph = try graph()
        var session = CookingSession(graph: graph)
        let initial = session.progress
        session.toggle("mix", graph: graph)
        XCTAssertEqual(session.progress.states["roast-garlic"], .complete)
        XCTAssertEqual(session.progress.states["roast-eggplant"], .complete)
        XCTAssertEqual(session.progress.states["serve"], .pending)
        XCTAssertEqual(session.history.count, 1)
        session.undo()
        XCTAssertEqual(session.progress, initial)
    }

    func testCheckingDownstreamCompletesRunningTimerAndUndoRestoresBoth() throws {
        let graph = try graph()
        var session = CookingSession(graph: graph)
        let now = Date(timeIntervalSince1970: 1_000)
        let duration = EditedDuration(min: 60, max: 60, unit: "min", approximate: true)
        session.startTimer("roast-eggplant", duration: duration, graph: graph, now: now)

        XCTAssertEqual(session.progress.states["roast-eggplant"], .running)
        XCTAssertEqual(session.progress.states["preheat"], .complete)
        XCTAssertEqual(session.progress.states["cut-eggplant"], .complete)
        XCTAssertEqual(session.progress.current, "garlic", "The next independent branch becomes current while the oven works")
        XCTAssertEqual(session.progress.timers["roast-eggplant"]?.checkAt, now.addingTimeInterval(3600))

        session.toggle("cool", graph: graph)
        XCTAssertEqual(session.progress.states["roast-eggplant"], .complete)
        XCTAssertNil(session.progress.timers["roast-eggplant"])
        XCTAssertEqual(session.progress.states["cool"], .complete, "Checking a downstream step confirms its running prerequisite")
        session.undo()
        XCTAssertEqual(session.progress.states["roast-eggplant"], .running)
        XCTAssertEqual(session.progress.states["cool"], .pending)
        XCTAssertNotNil(session.progress.timers["roast-eggplant"])
    }

    func testBlendDoesNotSuggestPastRunningBakeOrPendingCool() throws {
        let graph = try graph()
        var session = CookingSession(graph: graph)
        session.startTimer("roast-eggplant",
                           duration: EditedDuration(min: 60, max: 60, unit: "min", approximate: true),
                           graph: graph, now: Date(timeIntervalSince1970: 1_000))
        session.toggle("separate", graph: graph)
        XCTAssertEqual(session.progress.current, "tahini")
        session.toggle("blend-base", graph: graph)

        XCTAssertEqual(session.progress.states["roast-eggplant"], .running)
        XCTAssertNotNil(session.progress.timers["roast-eggplant"])
        XCTAssertEqual(session.progress.states["cool"], .pending)
        XCTAssertEqual(session.progress.states["extract-flesh"], .pending)
        XCTAssertEqual(session.progress.current, "parsley", "Suggest independent work, not a step blocked by Bake")
        session.toggle("parsley", graph: graph)
        XCTAssertNil(session.progress.current, "Nothing else is ready while Bake runs")

        session.completeTimer("roast-eggplant", graph: graph)
        XCTAssertEqual(session.progress.current, "cool")
        session.toggle("cool", graph: graph)
        XCTAssertEqual(session.progress.current, "extract-flesh")
    }

    @MainActor
    func testFocusFallsBackToRunningTimerWhenNothingElseIsReady() async throws {
        let store = SessionStore(graph: try graph(), fileURL: URL(fileURLWithPath: "/timer-focus-memory-only"), persists: false)
        store.toggle("roast-eggplant")
        XCTAssertEqual(store.session.progress.current, "garlic")
        XCTAssertEqual(store.focusTargetID, "garlic", "Actionable work takes priority over a running timer")

        store.toggle("separate")
        store.toggle("blend-base")
        store.toggle("parsley")

        XCTAssertNil(store.session.progress.current, "Waiting on the timer is still not modeled as an actionable step")
        XCTAssertEqual(store.focusTargetID, "roast-eggplant", "Viewport guidance falls back to the sole running blocker")

        let scroll = RecipeScrollView(store: store, showDetails: { _ in }, backToRecipes: {}, safeInsets: .zero,
                                      theme: .original, density: .compact)
        scroll.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        scroll.automaticallyCenters = false
        scroll.layoutIfNeeded()
        scroll.setContentOffset(CGPoint(x: scroll.contentSize.width - scroll.bounds.width, y: 0), animated: false)
        scroll.scrollViewDidScroll(scroll)
        let visibility = expectation(description: "Timer fallback visibility is reported")
        DispatchQueue.main.async { visibility.fulfill() }
        await fulfillment(of: [visibility], timeout: 1)
        XCTAssertFalse(store.currentIsCentered, "An offscreen timer is reported as needing the focus control")

        let request = store.explicitFocusRequest
        store.requestCurrentStep()
        XCTAssertEqual(store.explicitFocusRequest, request + 1, "The focus control accepts the timer fallback")
    }

    @MainActor
    func testTimerTapCompletesAndAdjustmentsUndoExactly() throws {
        let store = SessionStore(graph: try graph(), fileURL: URL(fileURLWithPath: "/timer-test-memory"), persists: false)
        store.toggle("roast-eggplant")
        let original = try XCTUnwrap(store.session.progress.timers["roast-eggplant"])
        // A sheet adjustment must not change focus, even when another cell is current.
        store.toggle("salt")
        let current = store.session.progress.current
        let focusRequest = store.focusRequest
        store.addMinutes(1, to: "roast-eggplant")
        XCTAssertEqual(store.session.progress.current, current)
        XCTAssertEqual(store.focusRequest, focusRequest)
        store.addMinutes(5, to: "roast-eggplant")
        XCTAssertEqual(store.session.progress.current, current)
        XCTAssertEqual(store.focusRequest, focusRequest)
        let extended = try XCTUnwrap(store.session.progress.timers["roast-eggplant"])
        XCTAssertEqual(extended.checkAt, original.checkAt.addingTimeInterval(360))
        XCTAssertEqual(extended.endAt, original.endAt.addingTimeInterval(360))
        store.toggle("roast-eggplant")
        XCTAssertEqual(store.session.progress.states["roast-eggplant"], .complete)
        XCTAssertNil(store.session.progress.timers["roast-eggplant"])
        store.undo()
        XCTAssertEqual(store.session.progress.states["roast-eggplant"], .running)
        XCTAssertEqual(store.session.progress.timers["roast-eggplant"], extended)
        store.undo(); store.undo()
        XCTAssertEqual(store.session.progress.timers["roast-eggplant"], original)
        store.cancelTimer("roast-eggplant")
        XCTAssertEqual(store.session.progress.states["roast-eggplant"], .pending)
        XCTAssertNil(store.session.progress.timers["roast-eggplant"])
        store.undo()
        XCTAssertEqual(store.session.progress.timers["roast-eggplant"], original)
    }

    func testSubtractTimeClampsAtNowAndUndoRestoresTimer() throws {
        let graph = try graph()
        var session = CookingSession(graph: graph)
        let now = Date(timeIntervalSince1970: 2_000)
        session.startTimer("roast-garlic", duration: EditedDuration(min: 2, max: 3, unit: "min", approximate: false), graph: graph, now: now)
        let original = session.progress
        session.addTime(-60, to: "roast-garlic", graph: graph, now: now)
        XCTAssertEqual(session.progress.timers["roast-garlic"]?.checkAt, now.addingTimeInterval(60))
        session.addTime(-300, to: "roast-garlic", graph: graph, now: now)
        XCTAssertEqual(session.progress.timers["roast-garlic"]?.checkAt, now)
        XCTAssertEqual(session.progress.timers["roast-garlic"]?.endAt, now.addingTimeInterval(60))
        XCTAssertEqual(session.progress.current, original.current)
        XCTAssertEqual(session.progress.states["roast-garlic"], .running)
        let count = session.history.count
        session.addTime(-60, to: "roast-garlic", graph: graph, now: now)
        XCTAssertEqual(session.history.count, count)
        _ = try session.validated(for: graph)
        session.undo(); session.undo()
        XCTAssertEqual(session.progress, original)
    }

    func testRangeTimerChecksAtMinimumAndCanBeExtendedOrCancelled() throws {
        let graph = try graph()
        var session = CookingSession(graph: graph)
        let now = Date(timeIntervalSince1970: 2_000)
        let duration = EditedDuration(min: 35, max: 40, unit: "min", approximate: false)
        session.startTimer("roast-garlic", duration: duration, graph: graph, now: now)
        XCTAssertEqual(session.progress.timers["roast-garlic"]?.checkAt, now.addingTimeInterval(35 * 60))
        XCTAssertEqual(session.progress.timers["roast-garlic"]?.endAt, now.addingTimeInterval(40 * 60))
        session.addTime(300, to: "roast-garlic", graph: graph)
        XCTAssertEqual(session.progress.timers["roast-garlic"]?.checkAt, now.addingTimeInterval(40 * 60))
        XCTAssertEqual(session.progress.timers["roast-garlic"]?.endAt, now.addingTimeInterval(45 * 60))
        session.cancelTimer("roast-garlic", graph: graph)
        XCTAssertEqual(session.progress.states["roast-garlic"], .pending)
        XCTAssertNil(session.progress.timers["roast-garlic"])
        session.undo()
        XCTAssertEqual(session.progress.states["roast-garlic"], .running)
    }

    func testEarliestDueTimerWinsAttention() throws {
        let graph = try graph()
        var session = CookingSession(graph: graph)
        let now = Date(timeIntervalSince1970: 3_000)
        session.startTimer("roast-eggplant", duration: .init(min: 60, max: 60, unit: "min", approximate: true), graph: graph, now: now)
        session.startTimer("roast-garlic", duration: .init(min: 35, max: 40, unit: "min", approximate: false), graph: graph, now: now)
        _ = session.reconsiderCurrent(now: now.addingTimeInterval(60 * 60), graph: graph)
        XCTAssertEqual(session.progress.current, "roast-garlic")
        session.completeTimer("roast-garlic", graph: graph)
        _ = session.reconsiderCurrent(now: now.addingTimeInterval(60 * 60), graph: graph)
        XCTAssertEqual(session.progress.current, "roast-eggplant")
    }

    @MainActor
    func testTimerPresentationDoesNotChangeCellGeometry() throws {
        let graph = try graph()
        let store = SessionStore(graph: graph, fileURL: URL(fileURLWithPath: "/timer-geometry-memory-only"), persists: false)
        let traits = UITraitCollection(preferredContentSizeCategory: .large)
        let before = RecipeGridGeometry(cells: graph.order.map { store.cell($0) }, layout: store.layout,
                                        theme: .original, density: .compact, traits: traits).frames
        store.toggle("roast-eggplant")
        let after = RecipeGridGeometry(cells: graph.order.map { store.cell($0) }, layout: store.layout,
                                       theme: .original, density: .compact, traits: traits).frames
        XCTAssertEqual(before, after)
        XCTAssertNotNil(store.timerPresentation(for: "roast-eggplant"))
    }

    @MainActor
    func testRunningTimerGlowBreathesThenSettlesForAttention() throws {
        let button = GridCellButton(cell: try XCTUnwrap(try graph().cells["roast-garlic"]))
        button.frame = CGRect(x: 0, y: 0, width: 160, height: 80)
        let running = TimerPresentation(text: "00:04", accessibilityText: "4 seconds remaining", progress: 0.2, needsAttention: false)

        button.update(state: .running, current: false, density: .compact, timer: running)
        button.layoutIfNeeded()
        XCTAssertTrue(button.timerGlowIsVisible)
        XCTAssertEqual(button.timerGlowIsBreathing, !UIAccessibility.isReduceMotionEnabled)
        let runningLineWidth = button.timerGlowLineWidth
        XCTAssertEqual(button.timerGlowOutlineBounds.insetBy(dx: -runningLineWidth / 2, dy: -runningLineWidth / 2), button.bounds)

        let attention = TimerPresentation(text: "Check", accessibilityText: "Ready to check", progress: 1, needsAttention: true)
        button.update(state: .running, current: true, density: .compact, timer: attention)
        XCTAssertTrue(button.timerGlowIsVisible)
        XCTAssertFalse(button.timerGlowIsBreathing)
        XCTAssertGreaterThan(button.timerGlowLineWidth, runningLineWidth)
        button.layoutIfNeeded()
        let attentionLineWidth = button.timerGlowLineWidth
        XCTAssertEqual(button.timerGlowOutlineBounds.insetBy(dx: -attentionLineWidth / 2, dy: -attentionLineWidth / 2), button.bounds)

        button.frame.size = CGSize(width: 211, height: 103)
        button.layoutIfNeeded()
        XCTAssertEqual(button.timerGlowOutlineBounds.insetBy(dx: -attentionLineWidth / 2, dy: -attentionLineWidth / 2), button.bounds)

        button.update(state: .complete, current: false, density: .compact)
        XCTAssertFalse(button.timerGlowIsVisible)
        XCTAssertFalse(button.timerGlowIsBreathing)
    }

    @MainActor
    func testTimerDurationOverrideEndsEveryTimerAtTenSeconds() throws {
        let graph = try graph()
        let store = SessionStore(graph: graph, fileURL: URL(fileURLWithPath: "/timer-override-memory-only"),
                                 persists: false, timerDurationOverride: 10, timerTickInterval: 0.1)
        store.toggle("roast-garlic")
        let timer = try XCTUnwrap(store.session.progress.timers["roast-garlic"])
        XCTAssertEqual(timer.endAt.timeIntervalSince(timer.startedAt), 10, accuracy: 0.001)
        XCTAssertEqual(timer.checkAt.timeIntervalSince(timer.startedAt), 8.75, accuracy: 0.001)
        XCTAssertEqual(timer.secondsPerRecipeSecond, 1, "Test mode displays the real ten-second countdown")
    }

    func testLegacyProgressWithoutTimersStillDecodes() throws {
        let graph = try graph()
        let legacy = """
        {"version":1,"recipeID":"\(graph.recipe.id)","progress":{"states":{\(graph.order.map { "\"\($0)\":\"pending\"" }.joined(separator: ","))},"current":"\(graph.order[0])"},"history":[],"density":"Compact","scrollX":0,"scrollY":0}
        """
        let restored = try JSONDecoder().decode(CookingSession.self, from: Data(legacy.utf8)).validated(for: graph)
        XCTAssertTrue(restored.progress.timers.isEmpty)
    }

    @MainActor
    func testDeadlinePreparesThenAlertsWithoutDisplayPolling() async throws {
        let store = SessionStore(graph: try graph(), fileURL: URL(fileURLWithPath: "/deadline-memory-only"),
                                 persists: false, timerDurationOverride: 0.8)
        let prepared = expectation(description: "Haptic prepared before expiry")
        let alerted = expectation(description: "Deadline fires without a visible table")
        var events: [String] = []
        store.onPrepareTimerAlert = { events.append("prepare"); prepared.fulfill() }
        store.onTimerAlert = { events.append("alert"); alerted.fulfill() }
        // Let the cached display time go stale before starting a timer.
        try await Task.sleep(for: .milliseconds(100))
        let tappedAt = Date()
        store.toggle("roast-eggplant")
        let timer = try XCTUnwrap(store.session.progress.timers["roast-eggplant"])
        XCTAssertGreaterThanOrEqual(timer.startedAt, tappedAt)
        let displayTime = store.timerNow
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertEqual(store.timerNow, displayTime, "An invisible table does not poll for display updates")
        await fulfillment(of: [prepared, alerted], timeout: 3, enforceOrder: true)
        XCTAssertEqual(events, ["prepare", "alert"])
        XCTAssertEqual(store.session.progress.current, "roast-eggplant")
        XCTAssertEqual(store.timerPresentation(for: "roast-eggplant")?.text, "Time reached")
    }

    @MainActor
    func testCancelledDeadlineDoesNotPrepareOrAlert() async throws {
        let store = SessionStore(graph: try graph(), fileURL: URL(fileURLWithPath: "/cancel-deadline-memory-only"),
                                 persists: false, timerDurationOverride: 0.7)
        let unexpected = expectation(description: "Cancelled timer stays silent")
        unexpected.isInverted = true
        store.onPrepareTimerAlert = { unexpected.fulfill() }
        store.onTimerAlert = { unexpected.fulfill() }
        store.toggle("roast-eggplant")
        store.cancelTimer("roast-eggplant")
        await fulfillment(of: [unexpected], timeout: 1)
        XCTAssertNil(store.timerPresentation(for: "roast-eggplant"))
    }

    func testUnmarkPreservesIndependentBranch() throws {
        let graph = try graph()
        var session = CookingSession(graph: graph)
        session.toggle("serve", graph: graph)
        let complete = session.progress
        session.toggle("garlic", graph: graph)
        for id in ["peel-garlic", "roast-garlic", "separate", "blend-base", "mix", "serve"] {
            XCTAssertEqual(session.progress.states[id], .pending, id)
        }
        XCTAssertEqual(session.progress.states["extract-flesh"], .complete)
        XCTAssertEqual(session.progress.states["olive-oil"], .complete)
        session.undo(); XCTAssertEqual(session.progress, complete)
    }

    func testMiseEnPlaceAndSwitchingBranches() throws {
        let graph = try graph()
        var session = CookingSession(graph: graph)
        session.toggle("garlic", graph: graph)
        XCTAssertEqual(session.progress.current, "olive-oil")
        session.toggle("tahini", graph: graph)
        XCTAssertEqual(session.progress.current, "lemon")
        session.toggle("roast-garlic", graph: graph)
        XCTAssertEqual(session.progress.current, "separate")
        XCTAssertEqual(session.progress.states["olive-oil"], .complete)
        session.toggle("parsley", graph: graph)
        XCTAssertEqual(session.progress.current, "eggplant")
    }

    func testUnmarkKeepsHistoryUntilTheTableIsUntouched() throws {
        let graph = try graph()
        var session = CookingSession(graph: graph)
        session.toggle("garlic", graph: graph)
        session.toggle("salt", graph: graph)
        session.toggle("garlic", graph: graph)
        XCTAssertFalse(session.history.isEmpty)
        session.toggle("salt", graph: graph)
        XCTAssertTrue(session.history.isEmpty)
        XCTAssertTrue(session.isUntouched)
        let restored = try JSONDecoder().decode(CookingSession.self, from: JSONEncoder().encode(session)).validated(for: graph)
        XCTAssertTrue(restored.history.isEmpty)
        session.toggle("garlic", graph: graph)
        XCTAssertEqual(session.history.count, 1)
        session.undo()
        XCTAssertTrue(session.isUntouched)
        XCTAssertTrue(session.history.isEmpty)
    }

    func testFinalIngredientAndReset() throws {
        let graph = try graph()
        var session = CookingSession(graph: graph)
        for id in graph.ingredientOrder { session.toggle(id, graph: graph) }
        XCTAssertEqual(session.progress.current, "preheat")
        session.toggle("serve", graph: graph)
        XCTAssertEqual(session.progress.states["salt"], .complete)
        XCTAssertNil(session.progress.current)
        session.reset(graph: graph)
        XCTAssertTrue(session.progress.states.values.allSatisfy { $0 == .pending })
        XCTAssertTrue(session.history.isEmpty)
        let reset = session.progress
        session.undo(); XCTAssertEqual(session.progress, reset)
        // Manually returning to an untouched table discards the prior run's history.
        session.toggle("garlic", graph: graph)
        session.toggle("garlic", graph: graph)
        XCTAssertTrue(session.history.isEmpty)
        session.undo()
        XCTAssertTrue(session.isUntouched)
        session.reset(graph: graph)
        XCTAssertTrue(session.history.isEmpty)
        XCTAssertEqual(session.progress, reset)
    }

    @MainActor
    func testDiskRestorationIncludesHistoryFocusAndViewport() throws {
        let graph = try graph()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("session.json")
        let store = SessionStore(graph: graph, fileURL: url)
        store.toggle("garlic"); store.toggle("olive-oil")
        store.setDensity(.compact); store.recordScroll(x: 110, y: 90)
        let restored = SessionStore(graph: graph, fileURL: url)
        XCTAssertNil(restored.errorMessage)
        XCTAssertEqual(restored.session.progress, store.session.progress)
        XCTAssertEqual(restored.session.history, store.session.history)
        XCTAssertEqual(restored.session.density, .compact)
        XCTAssertEqual(restored.session.scrollX, 110)
        XCTAssertEqual(restored.session.scrollY, 90)
        restored.undo()
        XCTAssertEqual(restored.session.progress.states["olive-oil"], .pending)
    }

    @MainActor
    func testCelebrationOnlyFollowsNewCompletion() throws {
        let graph = try graph()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("session.json")
        let store = SessionStore(graph: graph, fileURL: url)
        XCTAssertEqual(store.session.density, .compact)
        store.toggle("serve")
        XCTAssertNotNil(store.celebrationID)
        XCTAssertNil(SessionStore(graph: graph, fileURL: url).celebrationID)
        store.toggle("garlic")
        XCTAssertNil(store.celebrationID)
        store.undo()
        XCTAssertNil(store.celebrationID, "Undo restoring a finished recipe must not celebrate")
        store.reset()
        store.toggle("serve")
        XCTAssertNotNil(store.celebrationID)
        store.undo()
        XCTAssertNil(store.celebrationID)
        store.toggle("serve")
        XCTAssertNotNil(store.celebrationID)
        store.reset()
        XCTAssertNil(store.celebrationID)
    }

    func testGridCoversEverySlotExactlyOnce() throws {
        for id in ["baba-ganoush", "banana-muffins", "pickled-onion", "coca-de-recapte", "coconut-chickpea-soup"] {
            let graph = try RecipeGraph(recipe: Recipe.bundled(id: id))
            let layout = try RecipeTableLayout.generated(for: graph)
            var slots = Set<String>()
            for placement in layout.occupiedRegions {
                for row in placement.row..<(placement.row + placement.rows) {
                    for col in placement.column..<(placement.column + placement.columns) {
                        XCTAssertTrue(slots.insert("\(row),\(col)").inserted, "\(id): overlapping cell")
                    }
                }
            }
            XCTAssertEqual(slots.count, layout.rowCount * layout.columnWidths.count, "\(id): uncovered grid slot")
            XCTAssertEqual(layout.placements, try RecipeTableLayout.generated(for: graph).placements,
                           "\(id): generation must be deterministic")
            let repeated = try RecipeTableLayout.generated(for: graph)
            XCTAssertEqual(layout.references, repeated.references)
            XCTAssertEqual(layout.continuations, repeated.continuations)
            XCTAssertEqual(layout.fillers, repeated.fillers)
            XCTAssertEqual(layout.readingOrder, repeated.readingOrder)
            XCTAssertEqual(Set(layout.order), Set(graph.order))
            XCTAssertNoThrow(try layout.validate(for: graph))
        }
    }
    func testSharedInputsHaveOneSemanticCellAndExplicitConnections() throws {
        let graph = try RecipeGraph(recipe: Recipe.bundled(id: "baba-ganoush"))
        let layout = try RecipeTableLayout.generated(for: graph)
        let garnish = try XCTUnwrap(layout.references.first { $0.targetID == "serve" })
        XCTAssertEqual(garnish.sourceID, "sweet-paprika")
        XCTAssertTrue(garnish.optional)
        XCTAssertTrue(garnish.text(sourceLabel: "Paprika").contains("Extra"))
        let oil = try XCTUnwrap(layout.continuations.first)
        XCTAssertEqual(oil.sourceID, "separate")
        XCTAssertEqual(oil.targetID, "serve")
        XCTAssertEqual(oil.materials.map(\.outputID), ["garlic-oil"])
        XCTAssertTrue(oil.materials[0].optional)
        XCTAssertEqual(layout.placements.filter { $0.id == garnish.sourceID }.count, 1)
        XCTAssertTrue(layout.fillers.isEmpty)
        XCTAssertEqual(layout.placements.first { $0.id == "preheat" }?.row, 0)
        XCTAssertEqual(layout.readingOrder.filter { graph.cells[$0]!.isIngredient }.last, "parsley")
        XCTAssertFalse(oil.displayCell(targetLabel: "Serve").cue?.contains("→") ?? false)
        XCTAssertFalse(layout.order.contains(oil.id))
        XCTAssertFalse(layout.readingOrder.contains(oil.id))

        var missingReference = layout
        missingReference.references.removeAll()
        XCTAssertThrowsError(try missingReference.validate(for: graph))
        var duplicateReference = layout
        duplicateReference.references.append(garnish)
        XCTAssertThrowsError(try duplicateReference.validate(for: graph))
        var wrongAllocation = layout
        wrongAllocation.references = [.init(sourceID: garnish.sourceID, targetID: garnish.targetID,
                                            kind: .ingredient, allocation: "All", optional: false)]
        XCTAssertThrowsError(try wrongAllocation.validate(for: graph))
        var missingLane = layout
        missingLane.continuations.removeAll()
        missingLane.fillers.append(oil.region)
        XCTAssertThrowsError(try missingLane.validate(for: graph))
    }

    @MainActor
    func testSharedInputTextTracksEditsAndFitsAccessibleGeometry() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = SessionStore(graph: try graph(), fileURL: directory.appendingPathComponent("session.json"))
        let originalProgress = store.session.progress
        var edit = store.content(for: "sweet-paprika")
        edit.label = "Smoked paprika"
        try store.saveEdit(edit, for: "sweet-paprika")
        let serve = store.cell("serve")
        XCTAssertTrue(serve.inputReferences[0].contains("+ Smoked paprika"))
        XCTAssertEqual(store.content(for: "serve").applying(to: serve).inputReferences, serve.inputReferences)
        XCTAssertEqual(store.session.progress, originalProgress)
        XCTAssertEqual(Set(store.session.progress.states.keys), Set(store.graph.order))
        let traits = UITraitCollection(preferredContentSizeCategory: .accessibilityExtraExtraExtraLarge)
        let geometry = RecipeGridGeometry(cells: store.graph.order.map { store.cell($0) }, layout: store.layout,
                                          theme: .original, density: .compact, traits: traits)
        let frame = try XCTUnwrap(geometry.frames["serve"])
        XCTAssertGreaterThanOrEqual(frame.height, GridCellTextLayout.requiredHeight(cell: serve, theme: .original,
                                                                                  width: frame.width, traits: traits))
        for lane in store.layout.continuations {
            let laneFrame = try XCTUnwrap(geometry.frames[lane.id])
            XCTAssertGreaterThanOrEqual(laneFrame.height, GridCellTextLayout.requiredHeight(
                cell: lane.displayCell(targetLabel: serve.label), theme: .original, width: laneFrame.width, traits: traits))
        }
    }

    func testLateIngredientsFollowPreparationBranches() throws {
        let graph = try fixtureGraph([
            "schema_version": 1, "id": "late-input", "title": "Late input",
            "ingredients": [["id": "garnish", "name": "Garnish"], ["id": "supply", "name": "Supply"]],
            "steps": [
                ["id": "prepare", "action": "Prepare", "inputs": [["ingredient": "supply"]],
                 "outputs": [["id": "prepared", "name": "Prepared"]]],
                ["id": "finish", "action": "Finish", "inputs": [["ingredient": "garnish"], ["output": "prepared"]], "outputs": []]
            ]
        ])
        let layout = try RecipeTableLayout.generated(for: graph)
        XCTAssertEqual(layout.readingOrder.filter { graph.cells[$0]!.isIngredient }, ["supply", "garnish"])
        XCTAssertEqual(Set(graph.cells["finish"]!.dependencies), ["garnish", "prepare"])
        let coca = try RecipeGraph(recipe: Recipe.bundled(id: "coca-de-recapte"))
        let cocaLayout = try RecipeTableLayout.generated(for: coca)
        let order = cocaLayout.readingOrder.filter { coca.cells[$0]!.isIngredient }
        XCTAssertEqual(Array(order.suffix(3)), ["anchovies", "sardines", "black-pepper"])
        XCTAssertEqual(cocaLayout.references.filter { $0.sourceID == "olive-oil" }.count, 2)
    }

    func testGenericContinuationCompactsAndOrdersUnrelatedRecipe() throws {
        for supplies in [["a"], ["a", "b"]] {
            let graph = try fixtureGraph([
                "schema_version": 1, "id": "generic-split", "title": "Generic split",
                "ingredients": (supplies + ["finish"]).map { ["id": $0, "name": $0] },
                "steps": [
                    ["id": "prepare", "action": "Prepare", "inputs": supplies.map { ["ingredient": $0] },
                     "outputs": [["id": "main", "name": "Main portion"], ["id": "held", "name": "Held portion"]]],
                    ["id": "cook", "action": "Cook", "inputs": [["output": "main"]],
                     "outputs": [["id": "cooked", "name": "Cooked portion"]]],
                    ["id": "finish-dish", "action": "Finish", "inputs": [["output": "cooked"], ["output": "held"], ["ingredient": "finish"]], "outputs": []]
                ]
            ])
            let layout = try RecipeTableLayout.generated(for: graph)
            XCTAssertTrue(layout.fillers.isEmpty)
            XCTAssertEqual(layout.rowCount, 3, "Reuse two input rows, or stretch the single input path")
            XCTAssertEqual(layout.readingOrder.filter { graph.cells[$0]!.isIngredient }.last, "finish")
            XCTAssertEqual(layout.continuations.first?.sourceID, "prepare")
            XCTAssertEqual(layout.continuations.first?.targetID, "finish-dish")
            XCTAssertEqual(layout.continuations.first?.materials.map(\.outputID), ["held"])
            XCTAssertEqual(layout.placements, try RecipeTableLayout.generated(for: graph).placements)
            XCTAssertNoThrow(try layout.validate(for: graph))
        }
    }

    @MainActor
    func testContinuationButtonsShareProducerActionsAndState() throws {
        let store = SessionStore(graph: try graph(), fileURL: URL(fileURLWithPath: "/tmp/unused-lane-test.json"), persists: false)
        let scroll = RecipeScrollView(store: store, showDetails: { _ in }, backToRecipes: {}, safeInsets: .zero,
                                      theme: .original, density: .compact)
        func find(_ view: UIView, _ id: String) -> GridCellButton? {
            if let button = view as? GridCellButton, button.accessibilityIdentifier == id { return button }
            return view.subviews.compactMap { find($0, id) }.first
        }
        let producer = try XCTUnwrap(find(scroll, "cell.separate"))
        let lane = try XCTUnwrap(find(scroll, "continuation:separate:serve"))
        producer.onTap?()
        scroll.refresh()
        XCTAssertEqual(producer.progressState, .complete)
        XCTAssertEqual(lane.progressState, .complete)
        lane.onTap?()
        scroll.refresh()
        XCTAssertEqual(producer.progressState, .pending)
        XCTAssertEqual(lane.progressState, .pending)
        lane.onTap?()
        scroll.refresh()
        XCTAssertEqual(producer.progressState, .complete)
        XCTAssertEqual(lane.progressState, .complete)
        XCTAssertNil(store.session.progress.states[lane.cell.id])
        store.undo()
        scroll.refresh()
        XCTAssertEqual(producer.progressState, .pending)
        XCTAssertEqual(lane.progressState, .pending)
    }

    func testGridRejectsStackedDependencies() throws {
        let graph = try fixtureGraph(runtimeFixture())
        let stacked = RecipeTableLayout(placements: [
            .init(id: "supply", row: 0, column: 0, rows: 2),
            .init(id: "prepare", row: 0, column: 1),
            .init(id: "finish-dish", row: 1, column: 1)
        ], columnWidths: [100, 100])
        XCTAssertThrowsError(try stacked.validate(for: graph)) { error in
            XCTAssertTrue(error.localizedDescription.contains("left-to-right"))
        }
    }
    func testGridRejectsUndeclaredVisualDependency() throws {
        let graph = try fixtureGraph([
            "schema_version": 1, "id": "visual-dependency", "title": "Visual dependency",
            "ingredients": [["id": "a", "name": "A"], ["id": "b", "name": "B"]],
            "steps": [
                ["id": "prepare-a", "action": "Prepare A", "inputs": [["ingredient": "a"]],
                 "outputs": [["id": "prepared-a", "name": "Prepared A"]]],
                ["id": "prepare-b", "action": "Prepare B", "inputs": [["ingredient": "b"]], "outputs": []],
                ["id": "finish", "action": "Finish", "inputs": [["output": "prepared-a"]], "outputs": []]
            ]
        ])
        let misleading = RecipeTableLayout(placements: [
            .init(id: "a", row: 0, column: 0), .init(id: "b", row: 1, column: 0),
            .init(id: "prepare-a", row: 0, column: 1), .init(id: "prepare-b", row: 1, column: 1),
            .init(id: "finish", row: 0, column: 2, rows: 2)
        ], columnWidths: [100, 100, 100])
        XCTAssertThrowsError(try misleading.validate(for: graph)) { error in
            XCTAssertTrue(error.localizedDescription.contains("unexpected prepare-b"))
        }
    }
    @MainActor
    func testEditsPersistIndependentlyOfProgressAndReset() throws {
        let graph = try graph()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("session.json")
        let store = SessionStore(graph: graph, fileURL: url)
        store.toggle("garlic")
        let progress = store.session.progress, history = store.session.history
        var ingredient = store.content(for: "garlic")
        ingredient.label = "Garlic cloves"; ingredient.quantity = "6"; ingredient.cue = ""; ingredient.instruction = "Peel before cooking."
        try store.saveEdit(ingredient, for: "garlic")
        var operation = store.content(for: "roast-eggplant")
        XCTAssertEqual(operation.duration?.approximate, true)
        operation.duration = EditedDuration(min: 50, max: 60, unit: "min", approximate: true)
        try store.saveEdit(operation, for: "roast-eggplant")
        XCTAssertEqual(store.session.progress, progress)
        XCTAssertEqual(store.session.history, history)
        XCTAssertEqual(store.cell("roast-eggplant").amount, "≈50–60 min")
        XCTAssertEqual(store.cell("garlic").dependencies, graph.cells["garlic"]!.dependencies)
        store.reset(); store.undo()
        let restored = SessionStore(graph: graph, fileURL: url)
        XCTAssertEqual(restored.cell("garlic").label, "Garlic cloves")
        XCTAssertEqual(restored.cell("garlic").amount, "6")
        XCTAssertEqual(restored.cell("garlic").cue, "")
        XCTAssertTrue(restored.session.progress.states.values.allSatisfy { $0 == .pending })
        XCTAssertTrue(restored.session.history.isEmpty)
        XCTAssertEqual(restored.content(for: "roast-eggplant"), operation)
    }

    @MainActor
    func testInvalidEditsDoNotReplaceSavedContent() throws {
        let graph = try graph()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = SessionStore(graph: graph, fileURL: directory.appendingPathComponent("session.json"))
        var edit = store.content(for: "roast-garlic")
        let original = edit
        edit.duration = EditedDuration(min: 40, max: 30, unit: "min", approximate: false)
        XCTAssertThrowsError(try store.saveEdit(edit, for: "roast-garlic"))
        edit = original; edit.label = "  "
        XCTAssertThrowsError(try store.saveEdit(edit, for: "roast-garlic"))
        XCTAssertEqual(store.content(for: "roast-garlic"), original)
        XCTAssertTrue(store.session.history.isEmpty)
    }

    @MainActor
    func testAppearancePersistenceAndFallbacks() {
        let suite = "kitchen-table-tests-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("unknown", forKey: "theme")
        let preferences = AppearanceStore(defaults: defaults)
        XCTAssertEqual(preferences.theme, .original)
        XCTAssertEqual(preferences.mode, .system)
        XCTAssertFalse(preferences.keepScreenAwake)
        XCTAssertEqual(AppTheme.allCases.map(\.name), ["Original", "Studio", "Editorial", "Archive", "Classic"])
        preferences.keepScreenAwake = true
        XCTAssertTrue(AppearanceStore(defaults: defaults).keepScreenAwake)
        preferences.keepScreenAwake = false
        XCTAssertFalse(AppearanceStore(defaults: defaults).keepScreenAwake)
        for theme in AppTheme.allCases {
            preferences.theme = theme
            preferences.mode = .dark
            preferences.density = .comfortable
            let restored = AppearanceStore(defaults: defaults)
            XCTAssertEqual(restored.theme, theme)
            XCTAssertEqual(restored.mode, .dark)
            XCTAssertEqual(restored.density, .comfortable)
        }
    }

    func testScreenAwakeOnlyWhileEnabledAndActivelyCooking() {
        for enabled in [false, true] {
            for visible in [false, true] {
                for phase in [ScenePhase.active, .inactive, .background] {
                    XCTAssertEqual(CookingScreenAwakePolicy.preventsLocking(enabled: enabled, visible: visible, phase: phase),
                                   enabled && visible && phase == .active)
                }
            }
        }
    }

    @MainActor
    func testJournalRecordsOnlyExplicitFinishesAndPersists() throws {
        let graph = try graph()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("session.json")
        let store = SessionStore(graph: graph, fileURL: url)
        XCTAssertFalse(store.finish(), "An unfinished table must not count")
        store.toggle("serve")
        XCTAssertTrue(store.isComplete)
        XCTAssertEqual(store.session.statistics?.dishesCompleted ?? 0, 0)
        store.undo(); store.toggle("serve"); store.cancelCelebration()
        XCTAssertEqual(store.session.statistics?.dishesCompleted ?? 0, 0)
        let restored = SessionStore(graph: graph, fileURL: url)
        XCTAssertTrue(restored.isComplete, "Stay and relaunch preserve the unfinalized table")
        XCTAssertTrue(restored.finish())
        XCTAssertEqual(restored.session.statistics?.dishesCompleted, 1)
        XCTAssertNotNil(restored.session.statistics?.lastCompleted)
        XCTAssertEqual(restored.session.statistics?.journalEntries.count, 1)
        XCTAssertEqual(restored.session.statistics?.journalEntries.first?.dishName, "Baba Ganoush")
        XCTAssertTrue(restored.session.history.isEmpty)
        XCTAssertTrue(restored.session.progress.states.values.allSatisfy { $0 == .pending })
        XCTAssertFalse(restored.finish(), "A repeated action must not count again")
        XCTAssertEqual(SessionStore(graph: graph, fileURL: url).session.statistics?.dishesCompleted, 1)
        restored.toggle("serve"); restored.reset()
        XCTAssertEqual(restored.session.statistics?.dishesCompleted, 1, "Plain reset discards the run without counting it")
        restored.toggle("serve"); XCTAssertTrue(restored.finish())
        XCTAssertEqual(restored.session.statistics?.dishesCompleted, 2)
        XCTAssertEqual(restored.session.statistics?.journalEntries.count, 2)
    }



    @MainActor
    func testJournalCombinesRecipesMostRecentFirst() throws {
        let graph = try graph()
        let bananaRecipe = try Recipe.bundled(id: "banana-muffins")
        let bananaGraph = try RecipeGraph(recipe: bananaRecipe)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let olderURL = directory.appendingPathComponent("older.json")
        let newerURL = directory.appendingPathComponent("newer.json")
        var older = CookingSession(graph: graph)
        older.statistics = CookingStatistics(dishesCompleted: 4, journalEntries: [
            CookingJournalEntry(recipeID: graph.recipe.id, dishName: "Older dish", completedAt: Date(timeIntervalSince1970: 100))
        ])
        var newer = CookingSession(graph: bananaGraph)
        newer.statistics = CookingStatistics(dishesCompleted: 1, journalEntries: [
            CookingJournalEntry(recipeID: bananaGraph.recipe.id, dishName: "Newer dish", completedAt: Date(timeIntervalSince1970: 200))
        ])
        try JSONEncoder().encode(older).write(to: olderURL)
        try JSONEncoder().encode(newer).write(to: newerURL)
        let library = RecipeLibrary(stores: [SessionStore(graph: graph, fileURL: olderURL),
                                             SessionStore(graph: bananaGraph, fileURL: newerURL)])
        XCTAssertEqual(library.journalEntries.map(\.dishName), ["Newer dish", "Older dish"])
        XCTAssertEqual(library.dishesCooked, 5, "Recorded runs contribute to the total")
        XCTAssertEqual(library.uniqueDishesCooked, 2)
    }



    @MainActor
    func testFinishSaveFailureKeepsTableAvailableForRetry() throws {
        let graph = try graph()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("session.json")
        let store = SessionStore(graph: graph, fileURL: url)
        store.toggle("serve")
        try FileManager.default.removeItem(at: url)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        XCTAssertFalse(store.finish())
        XCTAssertTrue(store.isComplete)
        XCTAssertFalse(store.session.history.isEmpty)
        XCTAssertEqual(store.session.statistics?.dishesCompleted ?? 0, 0)
        XCTAssertNotNil(store.errorMessage)
        try FileManager.default.removeItem(at: url)
        XCTAssertTrue(store.finish())
        XCTAssertEqual(SessionStore(graph: graph, fileURL: url).session.statistics?.dishesCompleted, 1)
    }



    @MainActor
    func testSegmentStylingUpdatesInPlaceWithTheme() {
        let control = ThemeSegmentControl(items: ["Compact", "Comfort"])
        control.selectedSegmentIndex = 1
        control.theme = .ferran; control.applyTheme()
        let first = control.titleTextAttributes(for: .normal)?[.font] as? UIFont
        control.theme = .genius; control.applyTheme()
        let second = control.titleTextAttributes(for: .normal)?[.font] as? UIFont
        XCTAssertNotEqual(first?.familyName, second?.familyName)
        XCTAssertEqual(second?.familyName, AppTheme.genius.textFont(.subheadline).familyName)
        XCTAssertEqual(control.selectedSegmentIndex, 1)
        for style: UIUserInterfaceStyle in [.light, .dark] {
            let traits = UITraitCollection(userInterfaceStyle: style)
            XCTAssertEqual(control.selectedSegmentTintColor?.resolvedColor(with: traits), AppTheme.genius.accent.resolvedColor(with: traits))
            let foreground = control.titleTextAttributes(for: .selected)?[.foregroundColor] as? UIColor
            XCTAssertEqual(foreground?.resolvedColor(with: traits), AppTheme.genius.onAccent.resolvedColor(with: traits))
        }
    }

    func testAccessibleGridKeepsShortNamesWholeAndCellsCovered() throws {
        let graph = try graph()
        let layout = try RecipeTableLayout.generated(for: graph)
        let cells = graph.order.map { graph.cells[$0]! }
        for theme in AppTheme.allCases {
            for density in GridDensity.allCases {
                for category: UIContentSizeCategory in [.large, .extraExtraExtraLarge, .accessibilityExtraExtraExtraLarge] {
                    let traits = UITraitCollection(traitsFrom: [UITraitCollection(preferredContentSizeCategory: category), UITraitCollection(displayScale: 3)])
                    let grid = RecipeGridGeometry(cells: cells, layout: layout, theme: theme, density: density, traits: traits)
                    for id in ["eggplant", "cut-eggplant", "cool", "garlic"] {
                        let cell = graph.cells[id]!
                        let lines = GridCellTextLayout.lines(cell: cell, theme: theme, width: grid.frames[id]!.width - 24, traits: traits)
                        XCTAssertEqual(lines.first?.text, cell.label, "\(theme) \(density) \(category) \(id)")
                    }
                    let area = grid.frames.values.reduce(CGFloat(0)) { $0 + $1.width * $1.height }
                    XCTAssertEqual(area, grid.size.width * grid.size.height, accuracy: 1)
                    for cell in cells {
                        XCTAssertGreaterThanOrEqual(grid.frames[cell.id]!.height + 1, GridCellTextLayout.requiredHeight(cell: cell, theme: theme, width: grid.frames[cell.id]!.width, traits: traits))
                    }
                }
            }
        }
    }

    @MainActor
    func testWalkthroughGridUsesNaturalScrollableWidth() throws {
        let traits = UITraitCollection(traitsFrom: [
            UITraitCollection(preferredContentSizeCategory: .large),
            UITraitCollection(displayScale: 3)
        ])
        let cells = WalkthroughStore.graph.order.map { WalkthroughStore.graph.cells[$0]! }
        let layout = try RecipeTableLayout.generated(for: WalkthroughStore.graph)
        let natural = RecipeGridGeometry(cells: cells, layout: layout, theme: .original, density: .compact, traits: traits)
        let availableWidth: CGFloat = 354
        let fitted = natural

        XCTAssertGreaterThan(natural.size.width, availableWidth)
        XCTAssertFalse(layout.fillsAvailableWidth)
        XCTAssertEqual(fitted.frames["garlic"]!.minX, 0)
        XCTAssertEqual(fitted.frames["serve"]!.minX, fitted.frames["cook"]!.maxX, accuracy: 1 / 3)
        XCTAssertEqual(fitted.frames["serve"]!.minY, fitted.frames["cook"]!.minY, accuracy: 1 / 3)
        XCTAssertEqual(fitted.frames["bread"]!.minY, fitted.frames["serve"]!.maxY, accuracy: 1 / 3)
        XCTAssertEqual(fitted.frames["toast"]!.maxX, fitted.frames["serve"]!.maxX, accuracy: 1 / 3)
        XCTAssertEqual(fitted.frames["toast"]!.minY, fitted.frames["bread"]!.minY, accuracy: 1 / 3)
        XCTAssertEqual(fitted.frames["serve-spread"]!.minX, fitted.frames["serve"]!.maxX, accuracy: 1 / 3)
        XCTAssertEqual(fitted.frames["serve-spread"]!.minY, fitted.frames["serve"]!.minY, accuracy: 1 / 3)
        XCTAssertEqual(fitted.frames["serve-spread"]!.maxY, fitted.frames["toast"]!.maxY, accuracy: 1 / 3)
        XCTAssertEqual(fitted.frames["serve-spread"]!.maxX, natural.size.width, accuracy: 1 / 3)
        let area = fitted.frames.values.reduce(CGFloat(0)) { $0 + $1.width * $1.height }
        XCTAssertEqual(area, fitted.size.width * fitted.size.height, accuracy: 1)
    }

    func testMetadataUsesQuieterStableFontsInEveryTheme() {
        for theme in AppTheme.allCases {
            let action = theme.cellFont(size: 14)
            let metadata = theme.cellFont(size: 14, secondary: true)
            let completedMetadata = theme.cellFont(size: 14, completed: true, secondary: true)
            XCTAssertNotEqual(action.fontName, metadata.fontName, theme.rawValue)
            XCTAssertEqual(metadata, completedMetadata, "Metadata does not change weight when checked")
            XCTAssertFalse(metadata.fontDescriptor.symbolicTraits.contains(.traitBold))
        }
    }

    func testClassicUsesBundledDistressedTypewriterForDisplayText() {
        let displayFonts = [
            AppTheme.manual.titleFont(size: 34),
            AppTheme.manual.cellFont(size: 14),
            AppTheme.manual.textFont(.headline)
        ]
        for font in displayFonts {
            XCTAssertEqual(font.familyName, "Special Elite")
            let attributes = AppTheme.manual.textDrawingAttributes(font: font, color: .black)
            XCTAssertEqual(attributes[.strokeWidth] as? CGFloat, -2)
        }
        XCTAssertEqual(AppTheme.manual.cellFont(size: 12, secondary: true).fontName, "CourierNewPSMT")
        XCTAssertNil(AppTheme.manual.textDrawingAttributes(
            font: AppTheme.manual.cellFont(size: 12, secondary: true),
            color: .black
        )[.strokeWidth])
        for theme in AppTheme.allCases where theme != .manual {
            XCTAssertNil(theme.textDrawingAttributes(font: theme.titleFont(size: 20), color: .black)[.strokeWidth])
        }
    }

    func testEditorIssuesIdentifyFieldsAndTrackCorrections() throws {
        var content = CellContent(label: "", quantity: "1\n2", cue: "brief\nparagraph", instruction: "")
        XCTAssertEqual(content.issues.map(\.field), [.label, .quantity, .cue])
        content.label = "Garlic"; content.quantity = "6"; content.cue = "Peeled"
        XCTAssertTrue(content.issues.isEmpty)
        content.label = "A deliberately longer action name that can still be saved"
        XCTAssertNoThrow(try content.validated(), "Copy targets remain soft")
        var duration = DurationInput(minimum: "", maximum: "40", unit: "min", approximate: false)
        XCTAssertEqual(duration.issues.first?.field, .minimum)
        duration.minimum = "50"
        XCTAssertEqual(duration.issues.first?.field, .maximum)
        duration.maximum = "60"
        XCTAssertTrue(duration.issues.isEmpty)
        duration.minimum = "-1"
        XCTAssertEqual(duration.issues.first?.field, .minimum)
        duration.maximum = "invalid"
        XCTAssertEqual(Set(duration.issues.map(\.field)), [.minimum, .maximum], "One invalid input must not hide another field’s error")
        duration.minimum = "1,5"; duration.maximum = "2,5"
        XCTAssertTrue(duration.issues.isEmpty)
        XCTAssertEqual(duration.value?.min, 1.5)
        XCTAssertEqual(duration.value?.max, 2.5)
        duration.minimum = ""; duration.maximum = ""
        XCTAssertTrue(duration.issues.isEmpty)
        XCTAssertNil(duration.value)
        duration.minimum = "infinity"
        XCTAssertFalse(duration.issues.isEmpty)
    }

}

@MainActor
final class WalkthroughTests: XCTestCase {
    private func defaults() -> UserDefaults {
        let name = "walkthrough.tests.\(UUID().uuidString)"
        let value = UserDefaults(suiteName: name)!
        addTeardownBlock { value.removePersistentDomain(forName: name) }
        return value
    }
    func testIngredientsMustBeMarkedIndividuallyAndControlsDoNotCook() {
        let tour = WalkthroughStore(defaults: defaults())
        XCTAssertEqual(WalkthroughStore.graph.recipe.title, "Garlic spread")
        XCTAssertEqual(WalkthroughStore.graph.cells["olive-oil"]?.amount, "¼ cup, plus more")
        XCTAssertEqual(WalkthroughStore.graph.cells["olive-oil"]?.cue, "Enough to cover")
        XCTAssertEqual(WalkthroughStore.graph.cells["cook"]?.label, "Confit")
        XCTAssertEqual(WalkthroughStore.graph.cells["cook"]?.cue, "Very low heat · barely bubbling")
        XCTAssertEqual(WalkthroughStore.graph.cells["serve"]?.label, "Mash")
        XCTAssertEqual(WalkthroughStore.graph.cells["serve"]?.cue, "Reserve the oil")
        XCTAssertEqual(WalkthroughStore.graph.cells["serve"]?.instruction, "Lift the cloves out of the oil and mash with a fork until smooth and spreadable. Reserve the garlic oil for another use.")
        XCTAssertEqual(WalkthroughStore.graph.cells["serve"]?.dependencies, ["cook"])
        XCTAssertEqual(WalkthroughStore.graph.cells["bread"]?.amount, "2 slices")
        XCTAssertEqual(WalkthroughStore.graph.cells["toast"]?.label, "Toast")
        XCTAssertEqual(WalkthroughStore.graph.cells["toast"]?.dependencies, ["bread"])
        XCTAssertEqual(WalkthroughStore.graph.cells["serve-spread"]?.label, "Serve")
        XCTAssertEqual(WalkthroughStore.graph.cells["serve-spread"]?.dependencies, ["serve", "toast"])
        tour.start(); tour.tap("cook")
        XCTAssertEqual(tour.lesson, .ingredients)
        XCTAssertEqual(tour.practice.session.progress.states["garlic"], .pending)
        tour.tap("olive-oil"); tour.tap("garlic")
        XCTAssertEqual(tour.lesson, .ingredients)
        tour.tap("bread")
        XCTAssertEqual(tour.lesson, .details)
        XCTAssertEqual(tour.practice.session.progress.current, "peel")
        tour.tap("peel")
        XCTAssertEqual(tour.practice.session.progress.states["peel"], .pending)
        tour.detailsClosed()
        XCTAssertEqual(tour.lesson, .peel)
        tour.tap("peel")
        XCTAssertEqual(tour.lesson, .cook)
        XCTAssertFalse(tour.practice.isComplete)
        tour.tap("cook")
        XCTAssertEqual(tour.lesson, .toast)
        XCTAssertEqual(tour.practice.session.progress.states["cook"], .running)
        XCTAssertEqual(tour.practice.session.progress.states["serve"], .pending)
        XCTAssertEqual(tour.practice.session.progress.states["serve-spread"], .pending)
        if let timer = tour.practice.session.progress.timers["cook"] {
            XCTAssertEqual(timer.checkAt.timeIntervalSince(timer.startedAt), 35 * 60, accuracy: 0.001)
            XCTAssertEqual(timer.endAt.timeIntervalSince(timer.startedAt), 40 * 60, accuracy: 0.001)
            XCTAssertEqual(timer.secondsPerRecipeSecond, 1)
        } else {
            XCTFail("Confit should start the walkthrough timer")
        }
        XCTAssertEqual(tour.practice.timerPresentation(for: "cook")?.text, "35:00")
        XCTAssertEqual(tour.practice.session.progress.current, "toast")
        tour.tap("toast")
        XCTAssertEqual(tour.practice.session.progress.states["cook"], .running)
        XCTAssertEqual(tour.lesson, .timerReady)
        XCTAssertEqual(tour.practice.session.progress.current, "cook")
        tour.tap("cook")
        XCTAssertEqual(tour.practice.session.progress.states["cook"], .complete)
        XCTAssertEqual(tour.lesson, .serve)
        XCTAssertEqual(tour.practice.session.progress.current, "serve")
        tour.tap("serve")
        XCTAssertEqual(tour.lesson, .controls)
        XCTAssertEqual(tour.practice.session.progress.current, "serve-spread")
        XCTAssertFalse(tour.practice.isComplete)
        tour.acknowledgeControls()
        XCTAssertEqual(tour.lesson, .plating)
        XCTAssertEqual(tour.practice.session.progress.current, "serve-spread")
        tour.tap("serve-spread")
        XCTAssertTrue(tour.practice.isComplete)
        XCTAssertTrue(tour.hasCompleted)
        XCTAssertEqual(tour.practice.session.statistics?.dishesCompleted ?? 0, 0)
    }
    func testCheckpointRestoresLessonAndEditsButNotPartialIngredientProgress() throws {
        let preferences = defaults()
        let tour = WalkthroughStore(defaults: preferences)
        tour.start(); tour.tap("garlic"); tour.later()
        let resumed = WalkthroughStore(defaults: preferences)
        XCTAssertTrue(resumed.presented); XCTAssertTrue(resumed.resumePrompt)
        XCTAssertEqual(resumed.practice.session.progress.states["garlic"], .pending)
        resumed.tap("garlic"); resumed.tap("olive-oil"); resumed.tap("bread"); resumed.tap("peel")
        var edit = resumed.practice.content(for: "cook"); edit.cue = "Stir occasionally"
        try resumed.practice.saveEdit(edit, for: "cook")
        resumed.save()
        let restored = WalkthroughStore(defaults: preferences)
        XCTAssertEqual(restored.lesson, .details)
        XCTAssertEqual(restored.practice.cell("cook").cue, "Stir occasionally")
        XCTAssertEqual(restored.practice.session.progress.states["peel"], .pending)
        XCTAssertEqual(restored.practice.session.progress.states["cook"], .pending)
    }
    func testBackOnlyUndoesCookAndReplayDoesNotReenableFirstLaunch() {
        let preferences = defaults()
        let tour = WalkthroughStore(defaults: preferences)
        tour.start(); tour.tap("garlic"); tour.tap("olive-oil"); tour.tap("bread"); tour.tap("peel")
        tour.detailsClosed(); tour.tap("peel"); tour.tap("cook")
        tour.tap("toast"); tour.completeTimer("cook"); tour.tap("serve"); tour.acknowledgeControls(); tour.tap("serve-spread")
        tour.completionBack()
        XCTAssertEqual(tour.lesson, .plating)
        XCTAssertEqual(tour.practice.session.progress.states["peel"], .complete)
        XCTAssertEqual(tour.practice.session.progress.states["cook"], .complete)
        XCTAssertEqual(tour.practice.session.progress.states["serve"], .complete)
        XCTAssertEqual(tour.practice.session.progress.states["toast"], .complete)
        XCTAssertEqual(tour.practice.session.progress.states["serve-spread"], .pending)
        tour.tap("serve-spread"); tour.finish(); tour.open()
        XCTAssertEqual(tour.lesson, .welcome)
        tour.start(); tour.later()
        XCTAssertFalse(WalkthroughStore(defaults: preferences).presented)
        XCTAssertTrue(tour.hasCompleted)
        XCTAssertFalse(FileManager.default.fileExists(atPath: tour.practice.fileURL.path))
    }
}

extension WalkthroughTests {
    func testReadyToServeAllowsEveryEarlierCellAndUndoRestoresLesson() {
        let expected: [String: WalkthroughStore.Lesson] = [
            "garlic": .ingredients, "olive-oil": .ingredients, "bread": .ingredients,
            "peel": .peel, "cook": .cook, "serve": .serve, "toast": .toast
        ]
        for (id, lesson) in expected {
            let tour = WalkthroughStore(defaults: defaults())
            tour.start(); tour.tap("garlic"); tour.tap("olive-oil"); tour.tap("bread")
            tour.detailsClosed(); tour.tap("peel"); tour.tap("cook"); tour.tap("toast")
            tour.tap("cook"); tour.tap("serve"); tour.acknowledgeControls()
            XCTAssertEqual(tour.lesson, .plating)
            let before = tour.practice.session.progress
            tour.tap(id)
            XCTAssertEqual(tour.lesson, lesson, id)
            XCTAssertEqual(tour.practice.session.progress.states[id], .pending, id)
            XCTAssertEqual(tour.practice.session.progress.states["serve-spread"], .pending)
            tour.undo()
            XCTAssertEqual(tour.lesson, .plating, id)
            XCTAssertEqual(tour.practice.session.progress, before, id)
        }
    }

    func testUndoTraversesLessonsAndIndividualIngredientTaps() throws {
        let preferences = defaults()
        let tour = WalkthroughStore(defaults: preferences)
        tour.start(); tour.tap("olive-oil"); tour.tap("garlic"); tour.tap("bread"); tour.tap("peel")
        var edit = tour.practice.content(for: "cook"); edit.cue = "Stir occasionally"
        try tour.practice.saveEdit(edit, for: "cook")
        tour.detailsClosed(); tour.tap("peel")
        tour.undo()
        XCTAssertEqual(tour.lesson, .peel)
        XCTAssertEqual(tour.practice.cell("cook").cue, "Stir occasionally")
        tour.undo()
        XCTAssertEqual(tour.lesson, .details)
        XCTAssertEqual(tour.practice.session.progress.states["peel"], .pending)
        tour.undo()
        XCTAssertEqual(tour.lesson, .ingredients)
        XCTAssertEqual(tour.practice.session.progress.states["bread"], .pending)
        XCTAssertEqual(tour.practice.session.progress.states["garlic"], .complete)
        tour.undo()
        XCTAssertEqual(tour.practice.session.progress.states["garlic"], .pending)
        XCTAssertEqual(tour.practice.session.progress.states["olive-oil"], .complete)
        tour.undo()
        XCTAssertEqual(tour.practice.session.progress.states["olive-oil"], .pending)
        XCTAssertFalse(tour.canUndo)
        tour.undo()
        XCTAssertEqual(tour.lesson, .ingredients)
        XCTAssertFalse(tour.canUndo)
    }
    func testMenuPreservesHistoryAndResumeKeepsIngredientOrder() {
        let preferences = defaults()
        let tour = WalkthroughStore(defaults: preferences)
        tour.start(); tour.tap("olive-oil"); tour.tap("bread"); tour.tap("garlic")
        tour.initialMenu()
        XCTAssertTrue(tour.presented); XCTAssertTrue(tour.resumePrompt)
        XCTAssertEqual(tour.lesson, .details)
        let restored = WalkthroughStore(defaults: preferences)
        restored.undo()
        XCTAssertEqual(restored.lesson, .ingredients)
        XCTAssertEqual(restored.practice.session.progress.states["olive-oil"], .complete)
        XCTAssertEqual(restored.practice.session.progress.states["garlic"], .pending)
        XCTAssertEqual(restored.practice.session.progress.states["bread"], .complete)
        restored.restart()
        XCTAssertEqual(restored.lesson, .welcome)
        XCTAssertFalse(restored.canUndo)
        XCTAssertTrue(restored.practice.session.progress.states.values.allSatisfy { $0 == .pending })
    }
}

final class IncomingRecipeTests: XCTestCase {
    private func repository() throws -> IncomingRecipeRepository {
        try IncomingRecipeRepository(directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
    }

    func testCapturePersistsDistinctSourcesAndDeduplicatesPendingRecipe() throws {
        let repository = try repository()
        defer { try? FileManager.default.removeItem(at: repository.fileURL.deletingLastPathComponent()) }
        XCTAssertTrue(try repository.capture(url: URL(string: "https://example.com/recipe#ingredients")!, title: "Dinner"))
        XCTAssertFalse(try repository.capture(url: URL(string: "https://example.com/recipe#method")!, title: "Dinner again"))
        let otherProcess = try IncomingRecipeRepository(directory: repository.fileURL.deletingLastPathComponent())
        XCTAssertTrue(try otherProcess.capture(url: URL(string: "https://example.com/another")!, title: nil))
        XCTAssertEqual(try repository.load().items.map(\.title), ["Dinner", "example.com"])
        XCTAssertThrowsError(try repository.capture(url: URL(string: "file:///tmp/recipe")!, title: nil))
    }

    func testUnreadableStorageIsNeverOverwritten() throws {
        let repository = try repository()
        defer { try? FileManager.default.removeItem(at: repository.fileURL.deletingLastPathComponent()) }
        let original = Data("unreadable original".utf8)
        try original.write(to: repository.fileURL)
        XCTAssertThrowsError(try repository.capture(url: URL(string: "https://example.com/recipe")!, title: nil))
        XCTAssertEqual(try Data(contentsOf: repository.fileURL), original)
    }

    @MainActor
    func testQueuePausesRecoversAndCreatesIndependentRecipes() async throws {
        let repository = try repository()
        let directory = repository.fileURL.deletingLastPathComponent()
        defer { try? FileManager.default.removeItem(at: directory) }
        try repository.capture(url: URL(string: "https://example.com/one")!, title: "One")
        try repository.capture(url: URL(string: "https://example.com/two")!, title: "Two")
        let incoming = try IncomingRecipeStore(repository: repository, delay: .milliseconds(80))
        let ids = incoming.items.map(\.id)
        incoming.setActive(true)
        incoming.prepare(ids[0]); incoming.prepare(ids[1]); incoming.prepare(ids[0])
        try await Task.sleep(for: .milliseconds(20))
        XCTAssertEqual(incoming.items.map(\.status), [.preparing, .waiting])
        incoming.setActive(false)
        try await Task.sleep(for: .milliseconds(120))
        XCTAssertEqual(incoming.items.map(\.status), [.waiting, .waiting])
        // Recover a durable in-flight record as after a force quit.
        try repository.update { $0.items[0].status = .preparing }
        let restored = try IncomingRecipeStore(repository: repository, delay: .milliseconds(20))
        let library = RecipeLibrary(stores: [], incoming: restored, directory: directory)
        restored.setActive(true)
        for _ in 0..<100 {
            if restored.items.allSatisfy({ $0.status == .complete }) { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertEqual(restored.items.map(\.status), [.complete, .complete])
        XCTAssertEqual(restored.items.compactMap(\.mockTemplateID), ["baba-ganoush", "banana-muffins"])
        XCTAssertEqual(Set(library.stores.map { $0.graph.recipe.title }), ["Baba Ganoush", "Banana Muffins"])
        let first = try XCTUnwrap(library.store(for: "import-" + ids[0]))
        let second = try XCTUnwrap(library.store(for: "import-" + ids[1]))
        first.toggle("garlic")
        XCTAssertEqual(second.session.progress.states["flour"], .pending)
        XCTAssertNotEqual(first.fileURL, second.fileURL)
        try first.layout.validate(for: first.graph)
        try second.layout.validate(for: second.graph)
        let babaGraph = try RecipeGraph(recipe: Recipe.bundled(id: "baba-ganoush"))
        let bananaGraph = try RecipeGraph(recipe: Recipe.bundled(id: "banana-muffins"))
        XCTAssertEqual(first.layout.placements,
                       try RecipeTableLayout.generated(for: babaGraph).placements)
        XCTAssertEqual(second.layout.placements,
                       try RecipeTableLayout.generated(for: bananaGraph).placements)
        restored.setActive(false)
        let reopened = try IncomingRecipeStore(repository: repository)
        let reopenedLibrary = RecipeLibrary(stores: [], incoming: reopened, directory: directory)
        XCTAssertEqual(reopenedLibrary.stores.count, 2)
        XCTAssertEqual(reopenedLibrary.store(for: first.graph.recipe.id)?.session.progress.states["garlic"], .complete)
        XCTAssertTrue(reopenedLibrary.setRemoved(first.graph.recipe.id, removed: true))
        reopened.refresh()
        XCTAssertNil(reopenedLibrary.store(for: first.graph.recipe.id), "Refreshing imports must not resurrect removed recipes")
        let afterRemoval = RecipeLibrary(stores: [], incoming: try IncomingRecipeStore(repository: repository), directory: directory)
        XCTAssertEqual(afterRemoval.stores.count, 1)
        XCTAssertTrue(afterRemoval.setRemoved(first.graph.recipe.id, removed: false))
        XCTAssertEqual(afterRemoval.store(for: first.graph.recipe.id)?.session.progress.states["garlic"], .complete)
        XCTAssertEqual(try repository.load().nextMockTemplateIndex, 2)
        XCTAssertTrue(try repository.capture(url: URL(string: "https://example.com/one")!, title: "Again"))
    }

    @MainActor
    func testMockImportsBalanceAndPersistNumberedCopies() async throws {
        let repository = try repository()
        defer { try? FileManager.default.removeItem(at: repository.fileURL.deletingLastPathComponent()) }
        for number in 1...10 {
            try repository.capture(url: URL(string: "https://example.com/\(number)")!, title: nil)
        }
        let incoming = try IncomingRecipeStore(repository: repository, delay: .milliseconds(1))
        incoming.setActive(true)
        defer { incoming.setActive(false) }
        for item in incoming.items { incoming.prepare(item.id) }
        for _ in 0..<100 where !incoming.items.allSatisfy({ $0.status == .complete }) {
            try await Task.sleep(for: .milliseconds(10))
        }
        let titles = try incoming.items.map { item in
            try JSONDecoder().decode(Recipe.self, from: XCTUnwrap(item.preparedRecipe)).title
        }
        let originals = ["Baba Ganoush", "Banana Muffins", "Pickled Onion", "Coca de Recapte", "Coconut Chickpea Soup"]
        XCTAssertEqual(titles, originals + originals.map { "\($0) (2)" })
        XCTAssertEqual(try repository.load().nextMockTemplateIndex, 0)
        let reopened = try IncomingRecipeStore(repository: repository)
        let library = RecipeLibrary(stores: [], incoming: reopened, directory: repository.fileURL.deletingLastPathComponent())
        XCTAssertEqual(library.stores.count, 10)
        XCTAssertEqual(Set(library.stores.map { $0.graph.recipe.title }), Set(titles))
    }

    @MainActor
    func testRemovingActiveRecipeDoesNotCreateGhostCopyOrBlockNext() async throws {
        let repository = try repository()
        defer { try? FileManager.default.removeItem(at: repository.fileURL.deletingLastPathComponent()) }
        try repository.capture(url: URL(string: "https://example.com/one")!, title: "One")
        try repository.capture(url: URL(string: "https://example.com/two")!, title: "Two")
        let incoming = try IncomingRecipeStore(repository: repository, delay: .milliseconds(50))
        let ids = incoming.items.map(\.id)
        incoming.setActive(true)
        incoming.prepare(ids[0]); incoming.prepare(ids[1])
        try await Task.sleep(for: .milliseconds(10))
        incoming.remove(ids[0])
        for _ in 0..<100 {
            if incoming.items.first?.status == .complete { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertEqual(incoming.items.count, 1)
        XCTAssertEqual(incoming.items.first?.status, .complete)
        incoming.setActive(false)
    }
}


extension IncomingRecipeTests {
    @MainActor
    func testManualCaptureUsesSamePendingQueueAsSharing() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = try IncomingRecipeRepository(directory: directory)
        let url = try XCTUnwrap(RecipeSource.webURL(from: "  example.com/recipe#method  "))
        XCTAssertEqual(url.absoluteString, "https://example.com/recipe")
        for invalid in ["", "not a link", "file:///tmp/recipe", "javascript:alert(1)", "https://user:secret@example.com/recipe"] {
            XCTAssertNil(RecipeSource.webURL(from: invalid))
        }
        try repository.capture(url: url, title: "Shared recipe")
        let incoming = try IncomingRecipeStore(repository: repository)
        let original = try XCTUnwrap(incoming.items.first)
        XCTAssertEqual(try incoming.capture(url), original.id)
        XCTAssertEqual(incoming.items.count, 1)
        XCTAssertEqual(incoming.items.first?.title, "Shared recipe")
        let secondID = try incoming.capture(URL(string: "https://example.org/other")!)
        XCTAssertEqual(incoming.visibleItems.first?.id, secondID)
        XCTAssertTrue(incoming.items.allSatisfy { $0.status == .ready })
        XCTAssertEqual(try repository.load().items.count, 2)
    }
}


extension IncomingRecipeTests {
    @MainActor
    func testRecipeRemovalPreservesHistoryAndProgressAcrossRelaunch() throws {
        let repository = try repository()
        let directory = repository.fileURL.deletingLastPathComponent()
        defer { try? FileManager.default.removeItem(at: directory) }
        let recipe = try Recipe.bundled(id: "banana-muffins")
        let graph = try RecipeGraph(recipe: recipe)
        let url = directory.appendingPathComponent("session.json")
        var session = CookingSession(graph: graph)
        session.statistics = CookingStatistics(dishesCompleted: 4, journalEntries: [
            CookingJournalEntry(recipeID: recipe.id, dishName: recipe.title, completedAt: Date())
        ])
        session.toggle(graph.order[0], graph: graph)
        try JSONEncoder().encode(session).write(to: url)
        let store = SessionStore(graph: graph, fileURL: url)
        var edit = store.content(for: "flour")
        edit.label = "Plain flour"
        try store.saveEdit(edit, for: "flour")
        let library = RecipeLibrary(stores: [store], directory: directory)
        XCTAssertTrue(library.setRemoved(recipe.id, removed: true))
        XCTAssertTrue(library.stores.isEmpty)
        XCTAssertTrue(store.recipeRemoved)
        XCTAssertEqual(library.dishesCooked, 4)
        XCTAssertEqual(library.uniqueDishesCooked, 1)
        XCTAssertEqual(library.journalEntries.count, 1)
        let restoredStore = SessionStore(graph: graph, fileURL: url)
        let restored = RecipeLibrary(stores: [restoredStore], directory: directory)
        XCTAssertTrue(restored.stores.isEmpty)
        XCTAssertEqual(restored.dishesCooked, 4)
        XCTAssertTrue(restored.setRemoved(recipe.id, removed: false))
        XCTAssertEqual(restored.stores.count, 1)
        XCTAssertEqual(restoredStore.session.progress.states, session.progress.states)
        XCTAssertEqual(restoredStore.cell("flour").label, "Plain flour")
        XCTAssertFalse(restoredStore.recipeRemoved)
    }

    @MainActor
    func testRemovalWriteFailureLeavesRecipeVisible() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try Data("file instead of directory".utf8).write(to: directory)
        let recipe = try Recipe.bundled(id: "banana-muffins")
        let graph = try RecipeGraph(recipe: recipe)
        let store = SessionStore(graph: graph, fileURL: directory.appendingPathComponent("session.json"), persists: false)
        let library = RecipeLibrary(stores: [store], directory: directory)
        XCTAssertFalse(library.setRemoved(recipe.id, removed: true))
        XCTAssertEqual(library.stores.count, 1)
        XCTAssertNotNil(library.errorMessage)
    }
}

@MainActor
private final class TestAppIconClient: AppIconClient {
    var supportsAlternateIcons = true
    var alternateIconName: String?
    var requests: [String?] = []
    var shouldFail = false
    func changeIcon(to name: String?) async throws {
        requests.append(name)
        await Task.yield()
        if shouldFail { throw NSError(domain: "IconTest", code: 1) }
        alternateIconName = name
    }
}


extension IncomingRecipeTests {
    @MainActor
    func testDiscardUndoRestoresIdentityOrderAndPersistsWithoutDuplicatingCaptures() throws {
        let repository = try repository()
        defer { try? FileManager.default.removeItem(at: repository.fileURL.deletingLastPathComponent()) }
        try repository.capture(url: URL(string: "https://example.com/one")!, title: "One")
        try repository.capture(url: URL(string: "https://example.com/two")!, title: "Two")
        let incoming = try IncomingRecipeStore(repository: repository)
        let originalIDs = incoming.items.map(\.id)
        let discarded = try XCTUnwrap(incoming.remove(originalIDs[0]))
        XCTAssertEqual(try repository.load().items.count, 1)
        XCTAssertTrue(incoming.restore(discarded))
        XCTAssertEqual(incoming.items.map(\.id), originalIDs)
        XCTAssertEqual(incoming.items.first?.status, .ready)
        XCTAssertEqual(try IncomingRecipeStore(repository: repository).items.map(\.id), originalIDs)
        let again = try XCTUnwrap(incoming.remove(originalIDs[0]))
        try repository.capture(url: URL(string: "https://example.com/one")!, title: "New capture")
        XCTAssertTrue(incoming.restore(again))
        XCTAssertEqual(incoming.items.filter { $0.source == again.item.source }.count, 1)
        let original = try Data(contentsOf: repository.fileURL)
        try Data("corrupt".utf8).write(to: repository.fileURL)
        XCTAssertNil(incoming.remove(incoming.items[0].id))
        XCTAssertFalse(incoming.restore(discarded))
        XCTAssertEqual(try Data(contentsOf: repository.fileURL), Data("corrupt".utf8))
        try original.write(to: repository.fileURL)
    }

    @MainActor
    func testUndoDiscardDuringPreparationResumesWithoutGhostRecipes() async throws {
        let repository = try repository()
        defer { try? FileManager.default.removeItem(at: repository.fileURL.deletingLastPathComponent()) }
        try repository.capture(url: URL(string: "https://example.com/one")!, title: "One")
        let incoming = try IncomingRecipeStore(repository: repository, delay: .milliseconds(80))
        let id = incoming.items[0].id
        incoming.setActive(true)
        defer { incoming.setActive(false) }
        incoming.prepare(id)
        for _ in 0..<20 {
            if incoming.items.first?.status == .preparing { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        let discarded = try XCTUnwrap(incoming.remove(id))
        XCTAssertEqual(discarded.item.status, .preparing)
        XCTAssertTrue(incoming.items.isEmpty)
        XCTAssertTrue(incoming.restore(discarded))
        for _ in 0..<100 {
            if incoming.items.first?.status == .complete { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(incoming.items.count, 1)
        XCTAssertEqual(incoming.items.first?.id, id)
        XCTAssertEqual(incoming.items.first?.status, .complete)
        XCTAssertEqual(try repository.load().nextMockTemplateIndex, 1)
        XCTAssertNil(incoming.remove(id), "Completed recipes use library removal")
    }
}


extension IncomingRecipeTests {
    @MainActor
    func testRecipeOrderPersistsAndSurvivesRemovalUndo() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let stores = try ["baba-ganoush", "banana-muffins"].map { id in
            SessionStore(graph: try RecipeGraph(recipe: Recipe.bundled(id: id)), fileURL: directory.appendingPathComponent("\(id).json"), persists: false)
        }
        let library = RecipeLibrary(stores: stores, directory: directory)
        library.moveRecipes(from: IndexSet(integer: 1), to: 0)
        XCTAssertEqual(library.stores.map { $0.graph.recipe.id }, ["banana-muffins", "baba-ganoush"])
        let restored = RecipeLibrary(stores: stores, directory: directory)
        XCTAssertEqual(restored.stores.map { $0.graph.recipe.id }, ["banana-muffins", "baba-ganoush"])
        XCTAssertTrue(restored.setRemoved("banana-muffins", removed: true))
        restored.moveRecipes(from: IndexSet(integer: 0), to: 1)
        XCTAssertTrue(restored.setRemoved("banana-muffins", removed: false))
        XCTAssertEqual(restored.stores.map { $0.graph.recipe.id }, ["banana-muffins", "baba-ganoush"])
    }

    @MainActor
    func testRecipeOrderWriteFailureKeepsPreviousOrder() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try Data("not a directory".utf8).write(to: directory)
        let stores = try ["baba-ganoush", "banana-muffins"].map { id in
            SessionStore(graph: try RecipeGraph(recipe: Recipe.bundled(id: id)), fileURL: directory.appendingPathComponent("\(id).json"), persists: false)
        }
        let library = RecipeLibrary(stores: stores, directory: directory)
        library.moveRecipes(from: IndexSet(integer: 1), to: 0)
        XCTAssertEqual(library.stores.map { $0.graph.recipe.id }, ["baba-ganoush", "banana-muffins"])
        XCTAssertNotNil(library.errorMessage)
    }
}

extension IncomingRecipeTests {
    @MainActor
    func testMockImportUsesVisibleBookAndReplacesRemovedRecipe() async throws {
        let repository = try repository()
        let directory = repository.fileURL.deletingLastPathComponent()
        defer { try? FileManager.default.removeItem(at: directory) }
        let incoming = try IncomingRecipeStore(repository: repository, delay: .milliseconds(1))
        let initial = try ["baba-ganoush", "banana-muffins"].map { id in
            SessionStore(graph: try RecipeGraph(recipe: Recipe.bundled(id: id)),
                         fileURL: directory.appendingPathComponent(id + ".json"), persists: false)
        }
        let library = RecipeLibrary(stores: initial, incoming: incoming, directory: directory)
        incoming.setActive(true)
        defer { incoming.setActive(false) }
        for number in 0..<3 {
            let id = try incoming.capture(URL(string: "https://example.com/missing/\(number)")!)
            incoming.prepare(id)
        }
        for _ in 0..<100 where incoming.items.contains(where: { $0.status != .complete }) {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(Set(library.stores.map { $0.graph.recipe.title }),
                       Set(["Baba Ganoush", "Banana Muffins", "Pickled Onion", "Coca de Recapte", "Coconut Chickpea Soup"]))
        let removed = try XCTUnwrap(library.stores.first { $0.graph.recipe.title == "Pickled Onion" })
        XCTAssertTrue(library.setRemoved(removed.graph.recipe.id, removed: true))
        let replacementID = try incoming.capture(URL(string: "https://example.com/replacement")!)
        incoming.prepare(replacementID)
        for _ in 0..<100 where incoming.items.last?.status != .complete {
            try await Task.sleep(for: .milliseconds(10))
        }
        let item = try XCTUnwrap(incoming.items.last)
        XCTAssertEqual(item.status, .complete)
        let replacement = try XCTUnwrap(library.store(for: item.recipeID))
        XCTAssertEqual(replacement.graph.recipe.title, "Pickled Onion")
        XCTAssertEqual(library.stores.count, 5)
    }

    @MainActor
    func testMockSelectionBalancesTitleFamiliesAndAvoidsSuffixCollisions() throws {
        let templates = try ["baba-ganoush", "banana-muffins"].map { try Recipe.bundled(id: $0) }
        var result = IncomingRecipeStore.selectMockRecipe(templates: templates,
            titles: ["Baba Ganoush", "Baba Ganoush (2)", "Banana Muffins"], startingAt: 0)
        XCTAssertEqual(result.index, 1)
        XCTAssertEqual(result.title, "Banana Muffins (2)")
        result = IncomingRecipeStore.selectMockRecipe(templates: templates,
            titles: [" BABA GANOUSH ", "Baba Ganoush (3)", "Banana Muffins", "Banana Muffins (2)"], startingAt: 0)
        XCTAssertEqual(result.title, "Baba Ganoush (2)")
        result = IncomingRecipeStore.selectMockRecipe(templates: templates,
            titles: ["Baba Ganoush", "Baba Ganoush (2)", "Baba Ganoush (10)", "Banana Muffins", "Banana Muffins (2)"], startingAt: 0)
        XCTAssertEqual(result.title, "Banana Muffins (3)")
    }
}
