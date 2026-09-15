import XCTest

final class KitchenTableUITests: XCTestCase {
    @MainActor
    private func capture(_ name: String, app: XCUIApplication) {
        // Call after the test's expected UI state; XCTest synchronizes the screenshot.
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    private func openRecipe(_ app: XCUIApplication) {
        let recipe = app.buttons["book.open.baba-ganoush"]
        XCTAssertTrue(recipe.waitForExistence(timeout: 10))
        recipe.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
    }

    @MainActor
    func testFreeTierCanCookAndScenarioTwoPaywallCanBeDismissed() {
        continueAfterFailure = false
        let customer = RevenueCatTestCustomer()
        let app = XCUIApplication()
        app.launchArguments = customer.launchArguments + ["--skip-walkthrough", "--reset-session", "--disable-ads"]
        app.launch()

        let recipe = app.buttons["book.open.baba-ganoush"]
        XCTAssertTrue(recipe.waitForExistence(timeout: 10))
        recipe.tap()

        XCTAssertTrue(app.scrollViews["recipe.grid"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["Kitchen Table Plus"].exists)
        app.buttons["navigation.recipes"].tap()
        XCTAssertTrue(app.buttons["book.menu"].waitForExistence(timeout: 5))
        app.buttons["book.menu"].tap()
        app.buttons["Settings"].tap()
        XCTAssertTrue(app.buttons["settings.plan.upgrade"].waitForExistence(timeout: 10))
        app.buttons["settings.plan.upgrade"].tap()

        XCTAssertTrue(app.staticTexts["Kitchen Table Plus"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Cook without ads"].exists)
        XCTAssertTrue(app.staticTexts["Studio, Editorial, Archive and Classic themes"].exists)
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "29,99")).count, 1)
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "4,99")).count, 1)

        app.buttons["Close"].tap()
        XCTAssertTrue(app.staticTexts["settings.plan.name"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Kitchen Table Plus"].exists)
    }

    @MainActor
    func testPlanSectionShowsFreeAndCanUpgrade() {
        continueAfterFailure = false
        let customer = RevenueCatTestCustomer()
        let app = XCUIApplication()
        app.launchArguments = customer.launchArguments + ["--skip-walkthrough", "--reset-session", "--disable-ads"]
        app.launch()

        XCTAssertTrue(app.buttons["book.menu"].waitForExistence(timeout: 10))
        app.buttons["book.menu"].tap()
        app.buttons["Settings"].tap()
        XCTAssertTrue(app.staticTexts["settings.plan.name"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.staticTexts["settings.plan.name"].label, "Free")
        XCTAssertTrue(app.buttons["settings.plan.upgrade"].exists)
        XCTAssertTrue(app.buttons["settings.plan.restore"].exists)

        app.buttons["settings.plan.upgrade"].tap()
        XCTAssertTrue(app.staticTexts["Kitchen Table Plus"].waitForExistence(timeout: 10))
        app.buttons["Close"].tap()
        XCTAssertTrue(app.staticTexts["settings.plan.name"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["settings.plan.name"].label, "Free")
    }

    @MainActor
    func testPlanPurchaseRestoreAndManagement() {
        continueAfterFailure = false
        let customer = RevenueCatTestCustomer()
        print("RevenueCat Test Store customer: \(customer.id)")
        let app = XCUIApplication()
        app.launchArguments = customer.launchArguments + ["--skip-walkthrough", "--reset-session", "--disable-ads"]
        app.launch()

        XCTAssertTrue(app.buttons["book.menu"].waitForExistence(timeout: 10))
        app.buttons["book.menu"].tap()
        app.buttons["Settings"].tap()
        XCTAssertTrue(app.buttons["settings.plan.upgrade"].waitForExistence(timeout: 10))
        app.buttons["settings.plan.upgrade"].tap()
        XCTAssertTrue(app.buttons["Subscribe"].waitForExistence(timeout: 10))
        app.buttons["Subscribe"].tap()
        XCTAssertTrue(app.buttons["Test valid purchase"].waitForExistence(timeout: 10))
        app.buttons["Test valid purchase"].tap()

        let planName = app.staticTexts["settings.plan.name"]
        XCTAssertTrue(planName.waitForExistence(timeout: 10))
        XCTAssertEqual(planName.label, "Plus Yearly")
        XCTAssertTrue(app.buttons["settings.plan.manage"].exists)
        capture("plan-plus-yearly", app: app)

        app.buttons["settings.plan.restore"].tap()
        XCTAssertTrue(app.staticTexts["Kitchen Table Plus has been restored."].waitForExistence(timeout: 10))
        app.buttons["OK"].tap()

        app.buttons["settings.plan.manage"].tap()
        XCTAssertTrue(app.buttons["circled_close_button"].waitForExistence(timeout: 10))
        capture("plan-customer-center", app: app)
        app.buttons["circled_close_button"].tap()
        XCTAssertTrue(app.buttons["settings.plan.manage"].waitForExistence(timeout: 5))

        app.terminate()
        app.launchArguments = customer.launchArguments + ["--skip-walkthrough", "-theme", "ferran"]
        app.launch()
        XCTAssertTrue(app.buttons["book.menu"].waitForExistence(timeout: 10))
        app.buttons["book.menu"].tap()
        app.buttons["Settings"].tap()
        XCTAssertTrue(planName.waitForExistence(timeout: 10))
        XCTAssertEqual(planName.label, "Plus Yearly")
        XCTAssertTrue(app.buttons["settings.plan.manage"].exists)
        capture("plan-plus-yearly-studio", app: app)
    }

    @MainActor
    func testKeepScreenOnFromTablePersistsAndChangesActionLabel() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--skip-walkthrough", "--reset-session"]
        app.launch()
        openRecipe(app)
        let button = app.buttons["grid.keepScreenOn"]
        XCTAssertTrue(button.waitForExistence(timeout: 5))
        expectLabel("Keep screen on", of: button)
        button.tap()
        expectLabel("Allow auto-lock", of: button)
        expectValue("On", of: button)
        let feedback = app.staticTexts["Screen will stay on"]
        XCTAssertTrue(feedback.waitForExistence(timeout: 2))
        capture("screen-on-notification", app: app)
        let dismissed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: feedback)
        XCTAssertEqual(XCTWaiter.wait(for: [dismissed], timeout: 5), .completed)
        app.terminate()
        app.launchArguments = ["--ui-testing", "--skip-walkthrough"]
        app.launch(); openRecipe(app)
        expectLabel("Allow auto-lock", of: button)
        button.tap()
        expectLabel("Keep screen on", of: button)
        expectValue("Off", of: button)
        XCTAssertTrue(app.staticTexts["Automatic locking restored"].waitForExistence(timeout: 2))
    }

    @MainActor
    func testSharedIngredientReferenceAndHeldOilLane() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--skip-walkthrough", "--reset-session"]
        app.launch()
        openRecipe(app)
        let grid = app.scrollViews["recipe.grid"]
        XCTAssertTrue(grid.waitForExistence(timeout: 5))
        let serve = app.buttons["cell.serve"]
        XCTAssertTrue(serve.label.contains("+ Paprika"))
        XCTAssertEqual(app.buttons.matching(identifier: "cell.sweet-paprika").count, 1)
        let lane = app.descendants(matching: .any).matching(identifier: "continuation:separate:serve").firstMatch
        XCTAssertTrue(lane.exists)
        XCTAssertTrue(lane.label.contains("Garlic oil"))
        XCTAssertTrue(app.buttons["continuation:separate:serve"].exists)
        for _ in 0..<5 { grid.swipeLeft() }
        for _ in 0..<5 {
            if lane.frame.maxY < grid.frame.maxY - 120 { break }
            grid.swipeUp()
        }
        capture("shared-inputs-serving-and-oil-lane", app: app)
        XCTAssertTrue(lane.frame.intersects(grid.frame))
        lane.tap()
        let sharedComplete = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value BEGINSWITH %@", "complete"), object: lane)
        XCTAssertEqual(XCTWaiter.wait(for: [sharedComplete], timeout: 4), .completed)
        XCTAssertTrue((app.buttons["cell.separate"].value as? String)?.hasPrefix("complete") == true)
    }

    @MainActor
    func testCanonicalExtractionDetailsAndPreview() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--skip-walkthrough", "--reset-session"]
        app.launch()
        let entry = app.buttons["book.open.baba-ganoush"]
        XCTAssertTrue(entry.waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["book.open.baba-ganoush-new"].exists)
        entry.tap()
        let grid = app.scrollViews["recipe.grid"]
        XCTAssertTrue(grid.waitForExistence(timeout: 5))
        grid.swipeLeft()
        let extraction = app.buttons["cell.extract-flesh"]
        XCTAssertTrue(extraction.isHittable)
        capture("canonical-extraction-table", app: app)
        extraction.press(forDuration: 0.7)
        XCTAssertTrue(app.buttons["cell.edit"].waitForExistence(timeout: 5))
        capture("canonical-extraction-details", app: app)
        app.buttons["cell.edit"].tap()
        let preview = app.buttons["edit.preview"]
        XCTAssertTrue(preview.waitForExistence(timeout: 5))
        capture("canonical-extraction-preview", app: app)
        app.buttons["edit.cancel"].tap()
        app.buttons["details.back"].tap()
        XCTAssertFalse(app.buttons["progress.undo"].exists)
    }

    @MainActor
    func testTapDetailsUndoResetAndRestore() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--skip-walkthrough", "--reset-session"]
        app.launch()
        openRecipe(app)
        let garlic = app.buttons["cell.garlic"]
        XCTAssertTrue(garlic.waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["navigation.recipes"].isHittable)
        XCTAssertFalse(app.segmentedControls["grid.density"].exists)
        XCTAssertFalse(app.staticTexts["Tap to mark · Hold for details"].exists)
        XCTAssertFalse(app.buttons["grid.current"].exists)
        XCTAssertFalse(app.buttons["progress.undo"].exists)
        garlic.tap()
        XCTAssertTrue(app.buttons["progress.undo"].waitForExistence(timeout: 3))
        let oil = app.buttons["cell.olive-oil"]
        expectValue("pending, current", of: oil)
        oil.press(forDuration: 0.7)
        XCTAssertFalse(app.buttons["cell.skip"].exists)
        app.buttons["details.back"].tap()
        XCTAssertTrue(oil.waitForExistence(timeout: 3))
        expectValue("pending, current", of: oil)
        oil.tap()
        let undo = app.buttons["progress.undo"]
        undo.tap()
        expectValue("pending, current", of: oil)
        undo.press(forDuration: 0.8)
        expectValue("complete", of: garlic)
        undo.press(forDuration: 2.2)
        expectValue("pending", of: garlic)
        XCTAssertTrue(undo.waitForNonExistence(timeout: 3))
        garlic.tap()
        undo.tap()
        expectValue("pending", of: garlic)
        XCTAssertTrue(undo.waitForNonExistence(timeout: 3))
        garlic.tap()
        expectValue("complete", of: garlic)
        app.terminate()
        app.launchArguments = ["--ui-testing", "--skip-walkthrough"]
        app.launch()
        openRecipe(app)
        XCTAssertTrue(garlic.waitForExistence(timeout: 10))
        expectValue("complete", of: garlic)
        expectValue("pending, current", of: oil)
        XCTAssertFalse(app.segmentedControls["grid.density"].exists)
        expectValue("pending, current", of: oil)

        let grid = app.scrollViews["recipe.grid"]
        let undoPosition = undo.frame
        grid.swipeUp()
        XCTAssertFalse(app.buttons["navigation.recipes"].isHittable)
        XCTAssertTrue(undo.isHittable)
        XCTAssertEqual(undo.frame.minY, undoPosition.minY, accuracy: 1)
        XCTAssertTrue(oil.isHittable, "Recenter should be available even while the cell remains visible")
        XCTAssertTrue(app.buttons["grid.current"].waitForExistence(timeout: 4))
        grid.swipeLeft()
        let returnButton = app.buttons["grid.current"]
        XCTAssertTrue(returnButton.waitForExistence(timeout: 4))
        returnButton.tap()
        XCTAssertTrue(returnButton.waitForNonExistence(timeout: 4))
        XCTAssertTrue(oil.isHittable)
        expectValue("pending, current", of: oil)
    }

    @MainActor
    func testUndoKeepsTopMarginWhenScrolledAndRotated() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--skip-walkthrough", "--reset-session"]
        XCUIDevice.shared.orientation = .portrait
        defer { XCUIDevice.shared.orientation = .portrait }
        app.launch()
        openRecipe(app)
        app.buttons["cell.garlic"].tap()

        let grid = app.scrollViews["recipe.grid"]
        let undo = app.buttons["progress.undo"]
        XCTAssertTrue(undo.waitForExistence(timeout: 3))
        grid.swipeUp()
        XCUIDevice.shared.orientation = .landscapeLeft
        let landscape = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in app.frame.width > app.frame.height }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [landscape], timeout: 5), .completed)
        grid.swipeUp()

        XCTAssertGreaterThanOrEqual(undo.frame.minY - app.frame.minY, 23,
                                    "Undo keeps its top margin when the scrolled table rotates")
    }

    @MainActor
    func testCompletionCelebrationAndCookAgain() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--skip-walkthrough", "--reset-session"]
        app.launch()
        openRecipe(app)
        let grid = app.scrollViews["recipe.grid"]
        XCTAssertTrue(grid.waitForExistence(timeout: 10))
        for _ in 0..<4 { grid.swipeLeft() }
        let serve = app.buttons["cell.serve"]
        XCTAssertTrue(serve.isHittable)
        serve.tap()
        XCTAssertTrue(app.staticTexts["recipe.finished"].waitForExistence(timeout: 5))
        capture("completion-original-light", app: app)
        let completionTitle = app.staticTexts["recipe.finished"]
        let titleY = completionTitle.frame.minY
        let dragStart = completionTitle.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0)).withOffset(CGVector(dx: 0, dy: -160))
        dragStart.press(forDuration: 0.1, thenDragTo: dragStart.withOffset(CGVector(dx: 0, dy: -230)))
        let fixedPosition = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in abs(completionTitle.frame.minY - titleY) < 2 }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [fixedPosition], timeout: 3), .completed)
        XCTAssertTrue(app.buttons["recipe.stay"].isHittable)
        XCTAssertEqual(app.buttons["recipe.finish"].label, "Finish")
        app.buttons["recipe.finish"].tap()
        let entry = app.buttons["book.open.baba-ganoush"]
        XCTAssertTrue(entry.waitForExistence(timeout: 4))
        XCTAssertTrue(entry.label.contains("Start cooking"))
        openRecipe(app)
        expectValue("pending", of: serve)
        XCTAssertFalse(app.buttons["progress.undo"].exists)
        for cell in app.buttons.allElementsBoundByIndex where cell.identifier.hasPrefix("cell.") {
            XCTAssertTrue((cell.value as? String)?.hasPrefix("pending") == true, cell.identifier)
        }
        XCTAssertFalse(app.staticTexts["recipe.finished"].exists)
        app.terminate()
        app.launchArguments = ["--ui-testing", "--skip-walkthrough"]
        app.launch()
        openRecipe(app)
        XCTAssertTrue(serve.waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["recipe.finished"].exists)
        expectValue("pending", of: serve)
        XCTAssertFalse(app.buttons["progress.undo"].exists)
        for _ in 0..<4 { grid.swipeLeft() }
        serve.tap()
        XCTAssertTrue(app.buttons["recipe.stay"].waitForExistence(timeout: 5))
        app.buttons["recipe.stay"].tap()
        app.terminate(); app.launch(); openRecipe(app)
        expectValue("complete", of: serve)
        XCTAssertFalse(app.staticTexts["recipe.finished"].exists)
        serve.tap()
        expectValue("pending, current", of: serve)
        serve.tap()
        XCTAssertTrue(app.staticTexts["recipe.finished"].waitForExistence(timeout: 5))
        app.buttons["recipe.again"].tap()
        let preheat = app.buttons["cell.preheat"]
        expectValue("pending, current", of: preheat)
        XCTAssertTrue(app.buttons["progress.undo"].waitForNonExistence(timeout: 3))
        XCTAssertFalse(app.staticTexts["recipe.finished"].exists)
        grid.swipeDown()
        app.buttons["navigation.recipes"].tap()
        XCTAssertTrue(app.buttons["book.open.baba-ganoush"].label.contains("Start cooking"))
    }

    @MainActor
    func testRecipeBookNavigationPreservesProgressAndCentersCurrent() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--skip-walkthrough", "--reset-session"]
        app.launch()
        let entry = app.buttons["book.open.baba-ganoush"]
        XCTAssertTrue(entry.waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["book.title"].exists)
        XCTAssertTrue(app.staticTexts["2 recipes"].exists)
        XCTAssertTrue(entry.label.contains("Start cooking"))
        XCTAssertTrue(app.buttons["book.open.banana-muffins"].exists)
        XCTAssertFalse(app.descendants(matching: .any).matching(identifier: "book.unavailable.coca-de-recapte").firstMatch.exists)
        XCTAssertFalse(app.staticTexts["Coca de Recapte"].exists)
        XCTAssertFalse(app.staticTexts["Hummus"].exists)
        XCTAssertFalse(app.staticTexts["Table coming soon"].exists)
        openRecipe(app)
        let garlic = app.buttons["cell.garlic"]
        garlic.tap()
        let oil = app.buttons["cell.olive-oil"]
        expectValue("pending, current", of: oil)
        app.scrollViews["recipe.grid"].swipeDown()
        app.scrollViews["recipe.grid"].swipeLeft()
        XCTAssertTrue(app.buttons["grid.current"].waitForExistence(timeout: 4))
        app.buttons["navigation.recipes"].tap()
        XCTAssertTrue(entry.waitForExistence(timeout: 4))
        XCTAssertTrue(entry.label.contains("1 completed"))
        openRecipe(app)
        expectValue("pending, current", of: oil)
        XCTAssertTrue(app.buttons["grid.current"].waitForNonExistence(timeout: 5))
        XCTAssertTrue(oil.isHittable)
        app.buttons["progress.undo"].tap()
        expectValue("pending", of: garlic)
        app.buttons["navigation.recipes"].tap()
        XCTAssertTrue(entry.waitForExistence(timeout: 4))
        XCTAssertTrue(entry.label.contains("Start cooking"))
    }

    @MainActor
    func testBananaMuffinsOpensFromRecipeBook() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--skip-walkthrough", "--reset-session"]
        app.launch()
        let entry = app.buttons["book.open.banana-muffins"]
        XCTAssertTrue(entry.waitForExistence(timeout: 10))
        entry.tap()
        XCTAssertTrue(app.staticTexts["recipe.title"].waitForExistence(timeout: 4))
        XCTAssertEqual(app.staticTexts["recipe.title"].label, "Banana Muffins")
        XCTAssertTrue(app.buttons["cell.add-ins"].exists)
        XCTAssertTrue(app.buttons["cell.combine"].exists)
        XCTAssertFalse(app.buttons["cell.fold-add-ins"].exists)
        XCTAssertTrue(app.buttons["cell.prepare-pan"].exists)
        XCTAssertTrue(app.buttons["cell.fill-pan"].exists)
        XCTAssertTrue(app.buttons["cell.preheat"].exists)
        XCTAssertTrue(app.buttons["cell.bake-hot"].exists)
        XCTAssertTrue(app.buttons["cell.bake-through"].exists)
    }

    @MainActor
    func testMenuPagesThemesAndDensity() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--skip-walkthrough", "--reset-session"]
        app.launch()
        func page(_ title: String) {
            app.buttons["book.menu"].tap()
            app.buttons[title].tap()
            XCTAssertTrue(app.buttons["page.back"].waitForExistence(timeout: 4))
        }
        page("Settings")
        XCTAssertTrue(app.staticTexts["PLAN"].exists)
        XCTAssertEqual(app.staticTexts["settings.plan.name"].label, "Free")
        XCTAssertTrue(app.buttons["settings.plan.upgrade"].exists)
        XCTAssertTrue(app.buttons["settings.plan.restore"].exists)
        XCTAssertTrue(app.staticTexts["COOKING"].exists)
        XCTAssertTrue(app.staticTexts["DISPLAY"].exists)
        let keepScreenOn = app.switches["settings.keepScreenAwake"]
        XCTAssertTrue(keepScreenOn.exists)
        XCTAssertEqual(keepScreenOn.label, "Keep screen on")
        XCTAssertEqual(keepScreenOn.value as? String, "0")
        keepScreenOn.tap()
        XCTAssertEqual(keepScreenOn.value as? String, "1")
        keepScreenOn.tap()
        let appearance = app.segmentedControls["settings.appearance"]
        appearance.buttons["Dark"].tap()
        app.segmentedControls["settings.density"].buttons["Comfort"].tap()
        capture("settings-dark", app: app)
        app.buttons["page.back"].tap()
        page("Themes")
        for theme in ["original", "ferran", "dinner", "genius", "manual"] {
            let button = app.buttons["theme." + theme]
            if !button.isHittable { app.scrollViews.firstMatch.swipeUp() }
            button.tap()
            XCTAssertTrue(button.isSelected)
        }
        capture("themes-classic-dark", app: app)
        app.scrollViews.firstMatch.swipeDown()
        app.buttons["page.back"].tap()
        page("Settings")
        capture("settings-classic-dark", app: app)
        appearance.buttons["Light"].tap()
        XCTAssertTrue(appearance.buttons["Light"].isSelected)
        capture("settings-classic-light", app: app)
        appearance.buttons["Dark"].tap()
        app.buttons["page.back"].tap()
        openRecipe(app)
        XCTAssertFalse(app.buttons["book.menu"].exists)
        let comfortableWidth = app.buttons["cell.garlic"].frame.width
        app.buttons["cell.garlic"].press(forDuration: 0.7)
        XCTAssertFalse(app.buttons["cell.skip"].exists)
        capture("details-inline-actions", app: app)
        app.buttons["cell.edit"].tap()
        XCTAssertEqual(app.buttons["edit.save"].frame.minY, app.buttons["edit.cancel"].frame.minY, accuracy: 1)
        capture("editor-inline-actions", app: app)
        app.buttons["edit.cancel"].tap()
        app.buttons["details.back"].tap()
        app.terminate(); app.launchArguments = ["--ui-testing", "--skip-walkthrough"]; app.launch()
        page("Settings")
        XCTAssertTrue(appearance.buttons["Dark"].isSelected)
        XCTAssertTrue(app.segmentedControls["settings.density"].buttons["Comfort"].isSelected)
        app.segmentedControls["settings.density"].buttons["Compact"].tap()
        app.buttons["page.back"].tap()
        openRecipe(app)
        XCTAssertLessThan(app.buttons["cell.garlic"].frame.width, comfortableWidth)
    }

    @MainActor
    func testCellEditingSaveCancelAndRelaunch() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--skip-walkthrough", "--reset-session"]
        app.launch(); openRecipe(app)
        let garlic = app.buttons["cell.garlic"]
        garlic.tap()
        expectValue("complete", of: garlic)
        garlic.press(forDuration: 0.7)
        app.buttons["cell.edit"].tap()
        let name = app.textFields["edit.label"]
        XCTAssertTrue(name.waitForExistence(timeout: 4))
        capture("editor-original-light", app: app)
        name.tap()
        name.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 6) + "Garlic cloves")
        app.buttons["edit.save"].tap()
        XCTAssertTrue(app.buttons["cell.edit"].waitForExistence(timeout: 4))
        app.buttons["details.back"].tap()
        XCTAssertTrue(garlic.label.contains("Garlic cloves"))
        expectValue("complete", of: garlic)
        garlic.press(forDuration: 0.7)
        app.buttons["cell.edit"].tap()
        name.tap(); name.typeText(" temporary")
        app.buttons["edit.cancel"].tap()
        app.buttons["details.back"].tap()
        XCTAssertFalse(garlic.label.contains("temporary"))
        app.terminate(); app.launchArguments = ["--ui-testing", "--skip-walkthrough"]; app.launch(); openRecipe(app)
        XCTAssertTrue(garlic.label.contains("Garlic cloves"))
        expectValue("complete", of: garlic)
        app.buttons["progress.undo"].tap()
        expectValue("pending", of: garlic)
        XCTAssertTrue(garlic.label.contains("Garlic cloves"))
    }

    @MainActor
    func testSharedPageHeadingsAcrossThemes() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        for theme in ["original", "ferran", "dinner", "genius", "manual"] {
            app.launchArguments = ["--ui-testing", "--reset-session", "-theme", theme]
            app.launch()
            let welcomeBrand = app.staticTexts["walkthrough.brand"]
            XCTAssertTrue(welcomeBrand.waitForExistence(timeout: 10))
            let welcomeBrandFrame = welcomeBrand.frame
            capture("shared-walkthrough-heading-\(theme)", app: app)
            app.buttons["walkthrough.later"].tap()
            let title = app.staticTexts["book.title"]
            XCTAssertTrue(title.waitForExistence(timeout: 10))
            let bookBrandFrame = app.staticTexts["book.brand"].frame
            XCTAssertEqual(welcomeBrandFrame.minX, bookBrandFrame.minX, accuracy: 1)
            XCTAssertEqual(welcomeBrandFrame.minY, bookBrandFrame.minY, accuracy: 1)
            XCTAssertEqual(welcomeBrandFrame.height, bookBrandFrame.height, accuracy: 1)
            let bookTitleFrame = title.frame
            XCTAssertEqual(app.buttons["book.menu"].frame.midY, bookTitleFrame.midY, accuracy: 2)
            XCTAssertGreaterThanOrEqual(bookTitleFrame.minY - app.staticTexts["book.brand"].frame.maxY, 5.5)
            capture("shared-book-heading-\(theme)", app: app)

            app.buttons["book.menu"].tap(); app.buttons["Settings"].tap()
            let settingsTitle = app.staticTexts["page.title"]
            XCTAssertTrue(settingsTitle.waitForExistence(timeout: 4))
            XCTAssertEqual(settingsTitle.frame.minY, bookTitleFrame.minY, accuracy: 1)
            XCTAssertEqual(settingsTitle.frame.height, bookTitleFrame.height, accuracy: 1)
            capture("shared-settings-heading-\(theme)", app: app)
            app.buttons["page.back"].tap()

            openRecipe(app)
            app.buttons["cell.garlic"].tap()
            app.scrollViews["recipe.grid"].swipeDown()
            XCTAssertEqual(app.buttons["progress.undo"].frame.midY, bookTitleFrame.midY, accuracy: 2)
            capture("shared-recipe-heading-\(theme)", app: app)
            app.terminate()
        }
    }

    @MainActor
    func testFloatingControlsAlignWithTitleFirstLine() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--skip-walkthrough", "--reset-session"]
        app.launch()
        for theme in ["original", "ferran", "dinner", "genius"] {
            XCTAssertTrue(app.buttons["book.menu"].waitForExistence(timeout: 10))
            app.buttons["book.menu"].tap(); app.buttons["Themes"].tap()
            let choice = app.buttons["theme.\(theme)"]
            if !choice.isHittable { app.scrollViews.firstMatch.swipeUp() }
            choice.tap()
            app.scrollViews.firstMatch.swipeDown()
            app.buttons["page.back"].tap()
            let menu = app.buttons["book.menu"]
            let title = app.staticTexts["book.title"]
            XCTAssertEqual(menu.frame.midY, title.frame.midY, accuracy: 2)
            XCTAssertGreaterThanOrEqual(menu.frame.minX - title.frame.maxX, 15)
            capture("book-title-alignment-\(theme)", app: app)
            let menuY = menu.frame.midY
            app.scrollViews.firstMatch.swipeUp()
            XCTAssertTrue(!menu.isHittable || menu.frame.midY < menuY - 20,
                          "The book menu scrolls away with the header")
            app.scrollViews.firstMatch.swipeDown()
            openRecipe(app)
            app.buttons["cell.garlic"].tap()
            let grid = app.scrollViews["recipe.grid"]
            grid.swipeDown()
            let undo = app.buttons["progress.undo"]
            XCTAssertEqual(undo.frame.midY, menuY, accuracy: 2)
            XCTAssertGreaterThanOrEqual(undo.frame.minX - app.buttons["navigation.recipes"].frame.maxX, 15)
            capture("recipe-title-alignment-\(theme)", app: app)
            grid.swipeUp()
            XCTAssertLessThanOrEqual(undo.frame.midY, menuY + 1)
            XCTAssertTrue(undo.isHittable, "Undo remains available in its compact utility position")
            grid.swipeDown()
            undo.press(forDuration: 2.2)
            app.buttons["navigation.recipes"].tap()
        }
    }

    @MainActor
    func testFloatingControlsStayBesideWrappedTitle() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--skip-walkthrough", "--reset-session", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        let menu = app.buttons["book.menu"]
        XCTAssertTrue(menu.waitForExistence(timeout: 10))
        let title = app.staticTexts["book.title"]
        // A wrapped title extends below its control, without using the block's midpoint.
        XCTAssertGreaterThan(title.frame.height, menu.frame.height * 2)
        XCTAssertLessThan(menu.frame.midY, title.frame.midY - 15)
        XCTAssertGreaterThanOrEqual(menu.frame.minX - title.frame.maxX, 15)
        let menuY = menu.frame.midY
        capture("book-wrapped-title-alignment", app: app)
        openRecipe(app)
        app.buttons["cell.garlic"].tap()
        let grid = app.scrollViews["recipe.grid"]
        let heading = app.buttons["navigation.recipes"]
        for _ in 0..<8 {
            if heading.frame.minY >= 0 { break }
            grid.swipeDown()
        }
        XCTAssertTrue(heading.isHittable)
        let undo = app.buttons["progress.undo"]
        XCTAssertEqual(undo.frame.midY, menuY, accuracy: 2)
        XCTAssertGreaterThanOrEqual(undo.frame.minX - app.buttons["navigation.recipes"].frame.maxX, 15)
        capture("recipe-wrapped-title-alignment", app: app)
        grid.swipeUp()
        XCTAssertLessThanOrEqual(undo.frame.midY, menuY + 1)
        XCTAssertTrue(undo.isHittable)
    }

    @MainActor
    func testEditorPreviewMatchesNarrowAndMergedCells() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--skip-walkthrough", "--reset-session"]
        app.launch()
        for density in ["Compact", "Comfort"] {
            app.buttons["book.menu"].tap(); app.buttons["Settings"].tap()
            app.segmentedControls["settings.density"].buttons[density].tap()
            app.buttons["page.back"].tap()
            openRecipe(app)
            for id in ["garlic", "tahini"] {
                let cell = app.buttons["cell.\(id)"]
                if !cell.isHittable { app.scrollViews["recipe.grid"].swipeUp() }
                let actual = cell.frame.size
                let cookingState = cell.value as? String
                cell.press(forDuration: 0.7)
                app.buttons["cell.edit"].tap()
                let preview = app.buttons["edit.preview"]
                for _ in 0..<6 {
                    if preview.isHittable { break }
                    app.scrollViews.firstMatch.swipeUp()
                }
                XCTAssertTrue(preview.isHittable)
                XCTAssertEqual(preview.frame.width, actual.width, accuracy: 1)
                XCTAssertEqual(preview.frame.height, actual.height, accuracy: 1)
                capture("preview-\(id)-\(density)", app: app)
                XCTAssertEqual(preview.value as? String, "Unchecked")
                preview.tap(); expectValue("Current step", of: preview)
                if id == "garlic" && density == "Compact" { capture("preview-current", app: app) }
                preview.tap(); expectValue("Checked", of: preview)
                if id == "garlic" && density == "Compact" { capture("preview-checked", app: app) }
                preview.tap(); expectValue("Unchecked", of: preview)
                XCTAssertEqual(preview.frame.width, actual.width, accuracy: 1)
                XCTAssertEqual(preview.frame.height, actual.height, accuracy: 1)
                app.buttons["edit.cancel"].tap(); app.buttons["details.back"].tap()
                XCTAssertEqual(cell.value as? String, cookingState)
            }
            app.scrollViews["recipe.grid"].swipeDown()
            app.buttons["navigation.recipes"].tap()
        }
    }

    @MainActor
    func testAccessibilitySettingsChoicesAndReadableGrid() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--skip-walkthrough", "--reset-session", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        app.buttons["book.menu"].tap(); app.buttons["Settings"].tap()
        XCTAssertFalse(app.segmentedControls["settings.appearance"].exists)
        let system = app.buttons["System"]
        let light = app.buttons["Light"]
        XCTAssertTrue(system.isSelected)
        XCTAssertGreaterThan(light.frame.minY, system.frame.maxY)
        light.tap()
        XCTAssertTrue(light.isSelected)
        capture("accessible-appearance", app: app)
        let compact = app.buttons["Compact"]
        for _ in 0..<4 { if compact.isHittable { break }; app.scrollViews.firstMatch.swipeUp() }
        XCTAssertTrue(compact.isSelected)
        app.buttons["Comfort"].tap()
        XCTAssertTrue(app.buttons["Comfort"].isSelected)
        capture("accessible-spacing", app: app)
        for _ in 0..<5 { if app.buttons["page.back"].isHittable { break }; app.scrollViews.firstMatch.swipeDown() }
        app.buttons["page.back"].tap()
        openRecipe(app)
        let garlic = app.buttons["cell.garlic"]
        XCTAssertTrue(garlic.waitForExistence(timeout: 5))
        XCTAssertGreaterThan(garlic.frame.width, 250)
        capture("accessible-grid", app: app)
    }

    @MainActor
    func testStayThenFinishResetsOnlyOnFinish() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--skip-walkthrough", "--reset-session"]
        app.launch(); openRecipe(app)
        let grid = app.scrollViews["recipe.grid"]
        for _ in 0..<4 { grid.swipeLeft() }
        app.buttons["cell.serve"].tap()
        XCTAssertTrue(app.buttons["recipe.stay"].waitForExistence(timeout: 5))
        app.buttons["recipe.stay"].tap()
        XCTAssertTrue(app.buttons["grid.finish"].waitForExistence(timeout: 3))
        capture("completed-table-finish", app: app)
        grid.swipeDown()
        app.buttons["navigation.recipes"].tap()
        XCTAssertTrue(app.buttons["book.open.baba-ganoush"].label.contains("Ready to finish"))
        app.terminate(); app.launchArguments = ["--ui-testing", "--skip-walkthrough"]; app.launch(); openRecipe(app)
        XCTAssertTrue(app.buttons["grid.finish"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.staticTexts["recipe.finished"].exists)
        app.buttons["grid.finish"].tap()
        XCTAssertTrue(app.buttons["book.open.baba-ganoush"].waitForExistence(timeout: 4))
        XCTAssertTrue(app.buttons["book.open.baba-ganoush"].label.contains("Start cooking"))
        openRecipe(app)
        XCTAssertFalse(app.buttons["grid.finish"].exists)
        XCTAssertFalse(app.buttons["progress.undo"].exists)
    }

    @MainActor
    func testCompactDetailsAndQuieterGeniusMetadata() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--skip-walkthrough", "--reset-session"]
        app.launch()
        app.buttons["book.menu"].tap(); app.buttons["Themes"].tap()
        let genius = app.buttons["theme.genius"]
        if !genius.isHittable { app.scrollViews.firstMatch.swipeUp() }
        genius.tap(); app.scrollViews.firstMatch.swipeDown(); app.buttons["page.back"].tap()
        for mode in ["Light", "Dark"] {
            app.buttons["book.menu"].tap(); app.buttons["Settings"].tap()
            app.segmentedControls["settings.appearance"].buttons[mode].tap()
            app.buttons["page.back"].tap(); openRecipe(app)
            capture("quiet-metadata-genius-\(mode)", app: app)
            app.buttons["cell.garlic"].press(forDuration: 0.7)
            let back = app.buttons["details.back"]
            XCTAssertTrue(back.waitForExistence(timeout: 4))
            let title = app.staticTexts["details.title"]
            XCTAssertLessThan(back.frame.maxY - title.frame.minY, 180, "Short details should not have a blank middle")
            XCTAssertEqual(back.frame.minY, app.buttons["cell.edit"].frame.minY, accuracy: 1)
            capture("compact-details-\(mode)", app: app)
            app.buttons["cell.edit"].tap()
            XCTAssertTrue(app.buttons["edit.save"].waitForExistence(timeout: 4))
            app.buttons["edit.cancel"].tap()
            XCTAssertTrue(back.waitForExistence(timeout: 4))
            XCTAssertLessThan(back.frame.maxY - title.frame.minY, 180, "Leaving Edit should restore the compact sheet")
            back.tap()
            app.buttons["navigation.recipes"].tap()
        }
    }

    @MainActor
    func testInlineEditorErrorsClearWhileCorrecting() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--skip-walkthrough", "--reset-session"]
        app.launch(); openRecipe(app)
        app.buttons["cell.preheat"].press(forDuration: 0.7)
        app.buttons["cell.edit"].tap()
        let name = app.textFields["edit.label"]
        XCTAssertTrue(name.waitForExistence(timeout: 4))
        capture("editor-field-hierarchy-collapsed", app: app)
        name.tap(); name.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 7))
        app.buttons["edit.save"].tap()
        let nameError = app.descendants(matching: .any)["edit.label.error"].firstMatch
        XCTAssertTrue(nameError.waitForExistence(timeout: 3))
        XCTAssertGreaterThanOrEqual(nameError.frame.minY, name.frame.maxY)
        XCTAssertLessThan(nameError.frame.minY - name.frame.maxY, 24)
        XCTAssertFalse(app.staticTexts["edit.error"].exists)
        capture("inline-name-error", app: app)
        name.tap(); name.typeText("Preheat")
        XCTAssertTrue(nameError.waitForNonExistence(timeout: 3))
        let duration = app.switches["edit.duration"]
        XCTAssertTrue(duration.exists)
        // The bundled Preheat step already has a duration. Exercise hiding it
        // before testing validation, rather than assuming the fixture has none.
        expectValue("1", of: duration)
        duration.tap()
        XCTAssertTrue(app.textFields["edit.min"].waitForNonExistence(timeout: 3))
        duration.tap()
        let minimum = app.textFields["edit.min"]
        let maximum = app.textFields["edit.max"]
        minimum.tap()
        let existingMinimum = minimum.value as? String ?? ""
        minimum.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: existingMinimum.count) + "20")
        maximum.tap(); maximum.typeText("10")
        app.buttons["edit.save"].tap()
        let rangeError = app.descendants(matching: .any)["edit.max.error"].firstMatch
        XCTAssertTrue(rangeError.waitForExistence(timeout: 3))
        XCTAssertGreaterThanOrEqual(rangeError.frame.minY, maximum.frame.maxY)
        capture("inline-duration-error", app: app)
        maximum.tap(); maximum.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 2) + "30")
        XCTAssertTrue(rangeError.waitForNonExistence(timeout: 3))
        duration.tap()
        XCTAssertTrue(minimum.waitForNonExistence(timeout: 3))
        XCTAssertTrue(app.switches["edit.approximate"].waitForNonExistence(timeout: 3))
        duration.tap()
        expectValue("20", of: minimum)
        expectValue("30", of: maximum)
        app.buttons["edit.save"].tap()
        XCTAssertTrue(app.buttons["details.back"].waitForExistence(timeout: 4))
        app.buttons["details.back"].tap()
        XCTAssertTrue(app.buttons["cell.preheat"].label.contains("20–30 min"))
        app.buttons["cell.preheat"].press(forDuration: 0.7)
        app.buttons["cell.edit"].tap()
        expectValue("1", of: duration)
        duration.tap()
        app.buttons["edit.save"].tap()
        app.buttons["details.back"].tap()
        XCTAssertFalse(app.buttons["cell.preheat"].label.contains("20–30 min"))
        app.buttons["cell.preheat"].press(forDuration: 0.7)
        app.buttons["cell.edit"].tap()
        expectValue("0", of: duration)
        capture("editor-duration-off", app: app)
        duration.tap()
        app.buttons["edit.save"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["edit.min.error"].firstMatch.waitForExistence(timeout: 3))
        duration.tap()
        app.buttons["edit.save"].tap()
        XCTAssertTrue(app.buttons["details.back"].waitForExistence(timeout: 4))
    }

}

final class WalkthroughUITests: XCTestCase {
    @MainActor
    func testReplayFromCompletionStartsFreshTable() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--reset-session"]
        app.launch()
        app.buttons["walkthrough.start"].tap()
        for id in ["garlic", "olive-oil", "bread"] { app.buttons["cell.\(id)"].tap() }
        app.buttons["cell.peel"].press(forDuration: 0.7)
        app.buttons["details.back"].tap()
        for id in ["peel", "cook", "toast", "cook", "serve"] {
            app.buttons["cell.\(id)"].tap()
        }
        app.buttons["walkthrough.gotIt"].tap()
        app.buttons["cell.serve-spread"].tap()
        let again = app.buttons["recipe.again"]
        XCTAssertTrue(again.waitForExistence(timeout: 5))
        XCTAssertEqual(again.label, "Start again")
        again.tap()
        XCTAssertTrue(app.buttons["cell.garlic"].waitForExistence(timeout: 5))
        for id in ["garlic", "olive-oil", "bread", "peel", "cook", "toast", "serve", "serve-spread"] {
            XCTAssertTrue((app.buttons["cell.\(id)"].value as? String)?.hasPrefix("pending") == true)
        }
        XCTAssertFalse(app.buttons["progress.undo"].exists)
        XCTAssertFalse(app.buttons["recipe.finish"].exists)
    }

    @MainActor
    func testWalkthroughEditingControlsCompletionAndReplay() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--reset-session"]
        XCUIDevice.shared.orientation = .portrait
        app.launch()
        XCTAssertTrue(app.buttons["walkthrough.start"].waitForExistence(timeout: 5))
        app.buttons["walkthrough.start"].tap()
        app.buttons["cell.olive-oil"].tap()
        app.buttons["cell.garlic"].tap()
        app.buttons["cell.bread"].tap()
        // Inspect Peel before completing it, while Confit is still pending.
        app.buttons["cell.peel"].press(forDuration: 0.7)
        XCTAssertTrue(app.buttons["cell.edit"].waitForExistence(timeout: 3))
        app.buttons["cell.edit"].tap()
        // Saving unchanged must work without typing.
        app.buttons["edit.save"].tap()
        app.buttons["details.back"].tap()
        app.buttons["progress.undo"].tap()
        XCTAssertFalse(app.buttons["walkthrough.showDetails"].exists)
        XCTAssertFalse(app.buttons["walkthrough.gotIt"].exists)
        app.buttons["cell.peel"].press(forDuration: 0.7)
        app.buttons["details.back"].tap()
        app.buttons["cell.peel"].tap()
        let cook = XCTAttachment(screenshot: app.screenshot()); cook.name = "Walkthrough final Confit"; cook.lifetime = .keepAlways; add(cook)
        app.buttons["cell.cook"].tap()
        XCTAssertTrue((app.buttons["cell.cook"].value as? String)?.hasPrefix("running") == true)
        let toast = app.buttons["cell.toast"]
        toast.tap()
        if (toast.value as? String)?.hasPrefix("pending") == true { toast.tap() }
        app.buttons["cell.cook"].press(forDuration: 0.7)
        XCTAssertTrue(app.buttons["timer.addOne"].waitForExistence(timeout: 3))
        for (minus, plus) in [("timer.subtractOne", "timer.addOne"), ("timer.subtractFive", "timer.addFive")] {
            XCTAssertEqual(app.buttons[minus].frame.midY, app.buttons[plus].frame.midY, accuracy: 1)
            XCTAssertLessThan(app.buttons[minus].frame.maxX, app.buttons[plus].frame.minX)
        }
        app.buttons["timer.addOne"].tap()
        app.buttons["timer.addFive"].tap()
        app.buttons["timer.subtractOne"].tap()
        app.buttons["timer.subtractFive"].tap()
        XCTAssertTrue(app.staticTexts["timer.countdown"].exists)
        XCTAssertTrue(app.buttons["timer.complete"].exists, "Adding time keeps the sheet open")
        let timerSheet = XCTAttachment(screenshot: app.screenshot())
        timerSheet.name = "Running timer details"; timerSheet.lifetime = .keepAlways; add(timerSheet)
        app.buttons["details.back"].tap()
        app.buttons["cell.cook"].tap()
        XCTAssertFalse(app.buttons["walkthrough.gotIt"].exists)
        let serve = app.buttons["cell.serve"]
        serve.tap()
        // A first synthetic tap can finish the automatic reveal rather than activate the cell.
        if (serve.value as? String)?.hasPrefix("pending") == true { serve.tap() }
        XCTAssertTrue(app.buttons["walkthrough.gotIt"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["grid.current"].exists, "Explain focus even while centered")
        XCTAssertTrue(app.buttons["grid.keepScreenOn"].exists)
        let tips = XCTAttachment(screenshot: app.screenshot()); tips.name = "Walkthrough control tips"; tips.lifetime = .keepAlways; add(tips)
        let toastX = app.buttons["cell.toast"].frame.minX
        app.scrollViews["recipe.grid"].swipeRight()
        XCTAssertGreaterThan(app.buttons["cell.toast"].frame.minX, toastX + 10, "The controls lesson must allow horizontal scrolling")
        app.scrollViews["recipe.grid"].swipeLeft()
        app.buttons["progress.undo"].tap()
        XCTAssertFalse(app.buttons["walkthrough.gotIt"].exists)
        serve.tap()
        if (serve.value as? String)?.hasPrefix("pending") == true { serve.tap() }
        XCTAssertTrue(app.buttons["walkthrough.gotIt"].waitForExistence(timeout: 3))
        app.buttons["walkthrough.gotIt"].tap()
        serve.tap()
        if (serve.value as? String)?.hasPrefix("complete") == true { serve.tap() }
        XCTAssertEqual(app.staticTexts["walkthrough.lesson"].label, "Bring it all together")
        app.buttons["progress.undo"].tap()
        XCTAssertEqual(app.staticTexts["walkthrough.lesson"].label, "Ready to serve")
        let serveSpread = app.buttons["cell.serve-spread"]
        serveSpread.tap()
        if (serveSpread.value as? String)?.hasPrefix("pending") == true { serveSpread.tap() }
        XCTAssertTrue(app.buttons["recipe.back"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["recipe.again"].label, "Start again")
        app.buttons["recipe.back"].tap()
        serveSpread.tap()
        XCTAssertTrue(app.buttons["recipe.finish"].waitForExistence(timeout: 5))
        app.buttons["recipe.finish"].tap()
        XCTAssertTrue(app.buttons["book.menu"].waitForExistence(timeout: 5))
        app.terminate(); app.launchArguments = ["--ui-testing"]; app.launch()
        XCTAssertTrue(app.buttons["book.menu"].waitForExistence(timeout: 5))
        app.buttons["book.menu"].tap(); app.buttons["Walkthrough"].tap()
        XCTAssertTrue(app.buttons["walkthrough.start"].waitForExistence(timeout: 5))
    }
    @MainActor
    func testLaterResumesAndCancelOrDoneSkipsEditing() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--reset-session"]
        app.launch(); app.buttons["walkthrough.start"].tap()
        app.buttons["cell.garlic"].tap(); app.buttons["cell.olive-oil"].tap(); app.buttons["cell.bread"].tap(); app.buttons["cell.peel"].tap()
        app.buttons["walkthrough.later"].tap()
        app.terminate(); app.launchArguments = ["--ui-testing"]; app.launch()
        XCTAssertTrue(app.buttons["walkthrough.resume"].waitForExistence(timeout: 5))
        app.buttons["walkthrough.resume"].tap()
        app.buttons["cell.garlic"].press(forDuration: 0.7)
        app.buttons["cell.edit"].tap(); app.buttons["edit.cancel"].tap()
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", "Ready to prep"),
                                              object: app.staticTexts["walkthrough.lesson"])
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 3), .completed)
        app.buttons["cell.peel"].tap()
        XCTAssertEqual(app.staticTexts["walkthrough.lesson"].label, "Start a timer")
    }
}


extension WalkthroughUITests {
    @MainActor
    func testLandscapeWalkthroughCanFinishWithoutEditing() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--reset-session"]
        XCUIDevice.shared.orientation = .portrait
        defer { XCUIDevice.shared.orientation = .portrait }
        app.launch(); app.buttons["walkthrough.start"].tap()
        app.buttons["cell.garlic"].tap(); app.buttons["cell.olive-oil"].tap(); app.buttons["cell.bread"].tap(); app.buttons["cell.peel"].tap()
        app.buttons["cell.peel"].press(forDuration: 0.7)
        app.buttons["details.back"].tap()
        app.buttons["cell.peel"].tap()
        XCUIDevice.shared.orientation = .landscapeLeft
        let landscape = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in app.frame.width > app.frame.height }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [landscape], timeout: 5), .completed)
        app.buttons["cell.cook"].tap()
        let toast = app.buttons["cell.toast"]
        toast.tap()
        if (toast.value as? String)?.hasPrefix("pending") == true { toast.tap() }
        app.buttons["cell.cook"].press(forDuration: 0.7)
        let cancelTimer = app.buttons["timer.cancel"]
        if !cancelTimer.isHittable { app.scrollViews.containing(.button, identifier: "timer.cancel").firstMatch.swipeUp() }
        cancelTimer.tap()
        XCTAssertTrue((app.buttons["cell.cook"].value as? String)?.hasPrefix("pending") == true)
        app.buttons["cell.cook"].tap()
        app.buttons["cell.cook"].press(forDuration: 0.7)
        let completeTimer = app.buttons["timer.complete"]
        if !completeTimer.isHittable { app.scrollViews.containing(.button, identifier: "timer.complete").firstMatch.swipeUp() }
        completeTimer.tap()
        let serve = app.buttons["cell.serve"]
        serve.tap()
        // A first synthetic tap can finish the automatic reveal rather than activate the cell.
        if (serve.value as? String)?.hasPrefix("pending") == true { serve.tap() }
        let gotIt = app.buttons["walkthrough.gotIt"]
        XCTAssertTrue(gotIt.waitForExistence(timeout: 3))
        for _ in 0..<12 {
            if gotIt.isHittable { break }
            app.scrollViews.containing(.button, identifier: "walkthrough.later").firstMatch.swipeUp()
        }
        gotIt.tap()
        let serveSpread = app.buttons["cell.serve-spread"]
        serveSpread.tap()
        if (serveSpread.value as? String)?.hasPrefix("pending") == true { serveSpread.tap() }
        XCTAssertTrue(app.buttons["recipe.finish"].waitForExistence(timeout: 5))
        let finish = app.buttons["recipe.finish"]
        finish.tap()
        XCTAssertTrue(app.buttons["book.menu"].waitForExistence(timeout: 5))
        let result = XCTAttachment(screenshot: app.screenshot()); result.name = "Walkthrough landscape finished"; result.lifetime = .keepAlways; add(result)
    }
}


extension WalkthroughUITests {
    @MainActor
    func testWalkthroughMenuUndoAndHoldReset() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--reset-session"]
        app.launch(); app.buttons["walkthrough.start"].tap()
        app.buttons["cell.olive-oil"].tap()
        app.buttons["progress.undo"].tap()
        XCTAssertEqual(app.buttons["cell.olive-oil"].value as? String, "pending")
        app.buttons["navigation.recipes"].tap()
        XCTAssertTrue(app.buttons["walkthrough.resume"].waitForExistence(timeout: 3))
        app.buttons["walkthrough.resume"].tap()
        app.buttons["cell.garlic"].tap()
        app.buttons["progress.undo"].press(forDuration: 2.2)
        XCTAssertTrue(app.buttons["walkthrough.start"].waitForExistence(timeout: 3))
        app.buttons["walkthrough.start"].tap()
        app.buttons["cell.garlic"].tap(); app.buttons["cell.olive-oil"].tap(); app.buttons["cell.bread"].tap()
        XCTAssertEqual(app.staticTexts["walkthrough.lesson"].label, "A closer look")
    }
}

extension KitchenTableUITests {
    @MainActor
    func testNewMockRecipesImportAndOpenCookingTables() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--skip-walkthrough", "--reset-session"]
        app.launch()
        for (slug, title, action) in [("pickled-onion", "Pickled Onion", "marinate"),
                                       ("coca-de-recapte", "Coca de Recapte", "bake"),
                                       ("coconut-chickpea-soup", "Coconut Chickpea Soup", "reserve")] {
            app.buttons["book.addRecipe"].tap()
            let field = app.textFields["addRecipe.url"]
            XCTAssertTrue(field.waitForExistence(timeout: 3))
            field.tap()
            field.typeText("https://\(slug).example.org/recipe")
            app.buttons["addRecipe.save"].tap()
            XCTAssertTrue(app.staticTexts[title].waitForExistence(timeout: 10))
            app.buttons["incoming.action.\(slug).example.org"].tap()
            XCTAssertTrue(app.scrollViews["recipe.grid"].waitForExistence(timeout: 5))
            XCTAssertEqual(app.staticTexts["recipe.title"].label, title)
            XCTAssertTrue(app.buttons["cell.\(action)"].exists)
            capture("\(slug)-cooking-table", app: app)
            app.buttons["navigation.recipes"].tap()
        }
    }

    @MainActor
    func testIncomingRecipesPrepareAndPersistAcrossRelaunch() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--skip-walkthrough", "--reset-session", "--seed-imports"]
        app.launch()
        let first = app.buttons["incoming.action.Sunday baking"]
        let second = app.buttons["incoming.action.Dinner inspiration"]
        XCTAssertTrue(first.waitForExistence(timeout: 8))
        XCTAssertTrue(second.exists)
        let before = XCTAttachment(screenshot: app.screenshot())
        before.name = "incoming-recipes"; before.lifetime = .keepAlways; add(before)
        first.tap()
        second.tap()
        let prepared = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", "Start cooking"), object: first)
        XCTAssertEqual(XCTWaiter.wait(for: [prepared], timeout: 8), .completed)
        let secondPrepared = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", "Start cooking"), object: second)
        XCTAssertEqual(XCTWaiter.wait(for: [secondPrepared], timeout: 8), .completed)
        XCTAssertTrue(app.staticTexts["Pickled Onion"].exists)
        XCTAssertTrue(app.staticTexts["Coca de Recapte"].exists)
        XCTAssertFalse(app.staticTexts["Pickled Onion (1)"].exists)
        XCTAssertFalse(app.staticTexts["Coca de Recapte (1)"].exists)
        let after = XCTAttachment(screenshot: app.screenshot())
        after.name = "prepared-recipes"; after.lifetime = .keepAlways; add(after)
        first.tap()
        XCTAssertTrue(app.scrollViews["recipe.grid"].waitForExistence(timeout: 5))
        app.terminate()
        app.launchArguments = ["--ui-testing", "--skip-walkthrough"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Pickled Onion"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["Coca de Recapte"].exists)
        XCTAssertFalse(app.staticTexts["Recipes to import"].exists)
    }
}

extension KitchenTableUITests {
    @MainActor
    func testIncomingRecipeDiscardUndoAndPersistence() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--skip-walkthrough", "--reset-session", "--seed-imports"]
        app.launch()
        let first = app.buttons["incoming.action.Sunday baking"]
        XCTAssertTrue(first.waitForExistence(timeout: 8))
        let remove = app.buttons["incoming.remove.Sunday baking"]
        let originalY = first.frame.minY
        remove.tap()
        let undo = app.buttons["book.removal.undo"]
        XCTAssertTrue(undo.waitForExistence(timeout: 2))
        expectLabel("Import discarded. Undo", of: undo)
        XCTAssertFalse(app.alerts.firstMatch.exists)
        XCTAssertFalse(app.staticTexts["discardRecipe.title"].exists)
        expect(first, matching: NSPredicate(format: "exists == false"), timeout: 3)
        undo.tap()
        XCTAssertTrue(first.waitForExistence(timeout: 2))
        expect(first, matching: NSPredicate { _, _ in
            abs(first.frame.minY - originalY) <= 1
        })
        expectLabel("Import recipe", of: first)
        remove.tap()
        XCTAssertTrue(undo.waitForExistence(timeout: 2))
        let image = XCTAttachment(screenshot: app.screenshot())
        image.name = "import-discarded-undo"; image.lifetime = .keepAlways; add(image)
        app.terminate()
        app.launchArguments = ["--ui-testing", "--skip-walkthrough"]
        app.launch()
        XCTAssertTrue(app.buttons["incoming.action.Dinner inspiration"].waitForExistence(timeout: 8))
        expect(first, matching: NSPredicate(format: "exists == false"), timeout: 3)
    }

}

extension KitchenTableUITests {
    @MainActor
    func testManualRecipeLinkValidationDeduplicationAndImport() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--skip-walkthrough", "--reset-session"]
        app.launch()
        let add = app.buttons["book.addRecipe"]
        XCTAssertTrue(add.waitForExistence(timeout: 8))
        XCTAssertEqual(add.label, "Import recipe")
        XCTAssertGreaterThan(add.frame.midX, app.frame.minX + app.frame.width * 0.75, "Button: \(add.frame), app: \(app.frame)")
        XCTAssertGreaterThan(add.frame.midY, app.frame.minY + app.frame.height * 0.75, "Button: \(add.frame), app: \(app.frame)")
        XCTAssertGreaterThanOrEqual(add.frame.width, 44)
        let floatingButton = XCTAttachment(screenshot: app.screenshot())
        floatingButton.name = "floating-import-button"; floatingButton.lifetime = .keepAlways; self.add(floatingButton)
        XCTAssertEqual(app.buttons["book.menu"].frame.midY, app.staticTexts["book.title"].frame.midY, accuracy: 2)
        XCTAssertFalse(app.staticTexts["Recipes to import"].exists)
        XCTAssertFalse(app.staticTexts["Your recipes (2)"].exists)
        add.tap()
        let field = app.textFields["addRecipe.url"]
        let save = app.buttons["addRecipe.save"]
        XCTAssertTrue(field.waitForExistence(timeout: 3))
        XCTAssertEqual(save.label, "Import recipe")
        let paste = app.buttons["addRecipe.paste"]
        XCTAssertTrue(paste.exists)
        XCTAssertGreaterThan(paste.frame.minX, field.frame.maxX)
        XCTAssertEqual(paste.frame.midY, field.frame.midY, accuracy: 1)
        let emptySheet = XCTAttachment(screenshot: app.screenshot())
        emptySheet.name = "import-link-placeholder"; emptySheet.lifetime = .keepAlways; self.add(emptySheet)
        expect(save, matching: NSPredicate(format: "exists == true AND enabled == false"))
        field.tap(); field.typeText("not a link")
        expect(save, matching: NSPredicate(format: "exists == true AND enabled == false"))
        app.buttons["addRecipe.cancel"].tap()
        XCTAssertFalse(app.buttons["incoming.action.example.com"].exists)
        add.tap(); field.tap(); field.typeText("https://example.com/manual")
        expectEnabled(save)
        let sheet = XCTAttachment(screenshot: app.screenshot())
        sheet.name = "add-from-link"; sheet.lifetime = .keepAlways; self.add(sheet)
        save.tap()
        // Manual confirmation starts processing without a second tap on the row.
        let imported = app.buttons["incoming.action.example.com"]
        XCTAssertTrue(imported.waitForExistence(timeout: 8))
        expectLabel("Start cooking", of: imported)
        XCTAssertTrue(app.staticTexts["3 recipes"].waitForExistence(timeout: 3))
        XCTAssertLessThan(imported.frame.minY, app.buttons["book.open.baba-ganoush"].frame.minY)
        app.terminate()
        app.launchArguments = ["--ui-testing", "--skip-walkthrough"]
        app.launch()
        let recipe = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Pickled Onion")).firstMatch
        XCTAssertTrue(recipe.waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["3 recipes"].waitForExistence(timeout: 3))
        recipe.tap()
        XCTAssertTrue(app.scrollViews["recipe.grid"].waitForExistence(timeout: 5))
    }
}


extension KitchenTableUITests {
    @MainActor
    func testPendingRecipeTintAcrossThemes() {
        continueAfterFailure = false
        let app = XCUIApplication()
        for mode in ["Light", "Dark"] {
            for theme in ["original", "ferran", "dinner", "genius", "manual"] {
                app.launchArguments = ["--ui-testing", "--skip-walkthrough", "--reset-session", "--seed-imports", "-theme", theme, "-mode", mode]
                app.launch()
                let action = app.buttons["incoming.action.Sunday baking"]
                XCTAssertTrue(action.waitForExistence(timeout: 8))
                XCTAssertTrue(action.isHittable)
                XCTAssertTrue(app.buttons["incoming.remove.Sunday baking"].isHittable)
                XCTAssertEqual(app.staticTexts.matching(NSPredicate(format: "label == %@", "Ready to import")).count, 2)
                let image = XCTAttachment(screenshot: app.screenshot())
                image.name = "pending-\(theme)-\(mode)"
                image.lifetime = .keepAlways
                add(image)
                app.terminate()
            }
        }
    }
}


extension KitchenTableUITests {
    @MainActor
    func testRecipeRemovalUndoAndRelaunch() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--skip-walkthrough", "--reset-session"]
        app.launch()
        let recipe = app.buttons["book.open.banana-muffins"]
        XCTAssertTrue(recipe.waitForExistence(timeout: 8))
        recipe.swipeLeft()
        let swipeBin = app.buttons["Remove Banana Muffins"]
        XCTAssertTrue(swipeBin.waitForExistence(timeout: 2))
        XCTAssertGreaterThan(swipeBin.frame.midX, app.frame.midX)
        let swipeImage = XCTAttachment(screenshot: app.screenshot())
        swipeImage.name = "plain-swipe-bin"; swipeImage.lifetime = .keepAlways; add(swipeImage)
        swipeBin.tap()
        let undo = app.buttons["book.removal.undo"]
        XCTAssertTrue(undo.waitForExistence(timeout: 2))
        XCTAssertFalse(recipe.exists)
        undo.tap()
        XCTAssertTrue(recipe.waitForExistence(timeout: 2))
        app.buttons["book.menu"].tap()
        app.buttons["Edit recipes"].tap()
        let done = app.buttons["book.edit.done"]
        XCTAssertTrue(done.isHittable)
        XCTAssertGreaterThan(app.buttons["Remove Banana Muffins"].frame.midX, app.frame.midX)
        XCTAssertFalse(app.buttons["book.addRecipe"].exists)
        done.tap()
        XCTAssertTrue(recipe.waitForExistence(timeout: 2))
        XCTAssertFalse(app.buttons["Remove Banana Muffins"].exists)
        XCTAssertTrue(app.buttons["book.addRecipe"].isHittable)
        app.buttons["book.menu"].tap()
        app.buttons["Edit recipes"].tap()
        let editingImage = XCTAttachment(screenshot: app.screenshot())
        editingImage.name = "edit-recipes-fixed-separators"; editingImage.lifetime = .keepAlways; add(editingImage)
        app.buttons["Remove Banana Muffins"].tap()
        XCTAssertFalse(recipe.exists)
        app.buttons["book.edit.done"].tap()
        XCTAssertTrue(app.buttons["book.open.baba-ganoush"].waitForExistence(timeout: 2))
        XCTAssertFalse(app.buttons["book.edit.done"].exists)
        let image = XCTAttachment(screenshot: app.screenshot())
        image.name = "recipe-removed-notification"; image.lifetime = .keepAlways; add(image)
        app.terminate()
        app.launchArguments = ["--ui-testing", "--skip-walkthrough"]
        app.launch()
        XCTAssertTrue(app.buttons["book.open.baba-ganoush"].waitForExistence(timeout: 8))
        XCTAssertFalse(recipe.exists)
        XCTAssertTrue(app.staticTexts["1 recipe"].exists)
    }
}


extension KitchenTableUITests {
    @MainActor
    func testSwipeRevealClosesOnReverseOutsideTapAndAnotherRow() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--skip-walkthrough", "--reset-session"]
        app.launch()
        let recipe = app.buttons["book.open.banana-muffins"]
        let bin = app.buttons["Remove Banana Muffins"]
        XCTAssertTrue(recipe.waitForExistence(timeout: 8))
        recipe.swipeLeft()
        XCTAssertTrue(bin.waitForExistence(timeout: 2))
        app.staticTexts["book.title"].tap()
        XCTAssertTrue(recipe.waitForExistence(timeout: 2))
        XCTAssertFalse(bin.exists)
        recipe.swipeLeft()
        XCTAssertTrue(bin.waitForExistence(timeout: 2))
        app.staticTexts["Banana Muffins"].swipeRight()
        XCTAssertTrue(recipe.waitForExistence(timeout: 2))
        XCTAssertFalse(bin.exists)
        recipe.swipeLeft()
        XCTAssertTrue(bin.waitForExistence(timeout: 2))
        app.buttons["book.open.baba-ganoush"].swipeLeft()
        XCTAssertTrue(app.buttons["Remove Baba Ganoush"].waitForExistence(timeout: 2))
        XCTAssertFalse(bin.exists)
        app.staticTexts["book.title"].tap()
        XCTAssertTrue(app.buttons["book.open.baba-ganoush"].waitForExistence(timeout: 2))
        recipe.tap()
        XCTAssertTrue(app.scrollViews["recipe.grid"].waitForExistence(timeout: 5))
    }
}


extension KitchenTableUITests {
    @MainActor
    func testRecipeDragOrderPersistsAfterEditingAndRelaunch() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--skip-walkthrough", "--reset-session"]
        app.launch()
        let banana = app.buttons["book.open.banana-muffins"]
        let baba = app.buttons["book.open.baba-ganoush"]
        XCTAssertTrue(banana.waitForExistence(timeout: 8))
        XCTAssertGreaterThan(banana.frame.midY, baba.frame.midY)
        app.buttons["book.menu"].tap()
        app.buttons["Edit recipes"].tap()
        let origin = app.coordinate(withNormalizedOffset: .zero)
        let start = origin.withOffset(CGVector(dx: app.frame.width * 0.4, dy: banana.frame.midY))
        let end = origin.withOffset(CGVector(dx: app.frame.width * 0.4, dy: baba.frame.minY + 5))
        start.press(forDuration: 0.8, thenDragTo: end)
        let reordered = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in banana.frame.midY < baba.frame.midY }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [reordered], timeout: 3), .completed)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "reordered-recipes-edit-mode"; screenshot.lifetime = .keepAlways; add(screenshot)
        app.buttons["book.edit.done"].tap()
        XCTAssertLessThan(banana.frame.midY, baba.frame.midY)
        app.terminate()
        app.launchArguments = ["--ui-testing", "--skip-walkthrough"]
        app.launch()
        XCTAssertTrue(banana.waitForExistence(timeout: 8))
        XCTAssertLessThan(banana.frame.midY, baba.frame.midY)
        banana.tap()
        XCTAssertTrue(app.scrollViews["recipe.grid"].waitForExistence(timeout: 5))
    }
}
