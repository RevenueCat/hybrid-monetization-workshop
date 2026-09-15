import XCTest

/// Keep one instance across relaunches; create a new instance for each independent test.
/// A fresh ID isolates RevenueCat Test Store history, not Apple sandbox accounts or local app data.
struct RevenueCatTestCustomer {
    let id = "workshop-ui-" + UUID().uuidString
    var launchArguments: [String] { ["--ui-testing", "--revenuecat-test-user", id] }
}

/// Ignore typographic whitespace while retaining wording, numbers and punctuation.
private func normalizedAccessibilityText(_ text: String) -> String {
    text.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
}

/// Native controls can expose the same accessibility value as text or NSNumber.
private func accessibilityValueText(_ value: Any?) -> String? {
    value as? String ?? (value as? NSNumber)?.stringValue
}

extension XCTestCase {
    @MainActor
    func expectLabel(_ expected: String, of element: XCUIElement, timeout: TimeInterval = 4,
                     file: StaticString = #filePath, line: UInt = #line) {
        let expectedText = normalizedAccessibilityText(expected)
        expect(element, matching: NSPredicate { candidate, _ in
            guard let element = candidate as? XCUIElement, element.exists else { return false }
            return normalizedAccessibilityText(element.label) == expectedText
        }, timeout: timeout, file: file, line: line)
    }

    @MainActor
    func expectValue(_ expected: String, of element: XCUIElement, timeout: TimeInterval = 4,
                     file: StaticString = #filePath, line: UInt = #line) {
        expect(element, matching: NSPredicate { candidate, _ in
            guard let element = candidate as? XCUIElement, element.exists else { return false }
            return accessibilityValueText(element.value) == expected
        }, timeout: timeout, file: file, line: line)
    }

    @MainActor
    func expectEnabled(_ element: XCUIElement, timeout: TimeInterval = 5,
                       file: StaticString = #filePath, line: UInt = #line) {
        expect(element, matching: NSPredicate(format: "exists == true AND enabled == true"),
               timeout: timeout, file: file, line: line)
    }

    @MainActor
    func expect(_ element: XCUIElement, matching predicate: NSPredicate, timeout: TimeInterval = 5,
                file: StaticString = #filePath, line: UInt = #line) {
        // Avoid the expectation's initial polling delay when the state is already ready,
        // especially for transient controls such as the three-second Undo notification.
        if predicate.evaluate(with: element) { return }
        let settled = XCTNSPredicateExpectation(predicate: predicate, object: element)
        let result = XCTWaiter.wait(for: [settled], timeout: timeout)
        if result != .completed {
            let actual = element.exists ? "value: \(String(describing: element.value)); frame: \(element.frame)" : "element is absent"
            XCTFail("Timed out waiting for \(element) to match \(predicate). Actual \(actual)", file: file, line: line)
        }
    }
}

final class UITestSupportTests: XCTestCase {
    func testAccessibilityNormalizationPreservesMeaning() {
        XCTAssertEqual(normalizedAccessibilityText("  Ready\u{00A0}to\u{202F}import\n"), "Ready to import")
        XCTAssertNotEqual(normalizedAccessibilityText("20–30 min"), normalizedAccessibilityText("20–40 min"))
        XCTAssertNotEqual(normalizedAccessibilityText("Import recipe"), normalizedAccessibilityText("Import recipes"))
        XCTAssertNotEqual(normalizedAccessibilityText("Import recipe"), normalizedAccessibilityText("import recipe"))
        XCTAssertNotEqual(normalizedAccessibilityText("Import discarded. Undo"), normalizedAccessibilityText("Import discarded Undo"))
        XCTAssertEqual(accessibilityValueText("1"), accessibilityValueText(NSNumber(value: 1)))
        XCTAssertEqual(accessibilityValueText(NSNumber(value: 0)), "0")
        XCTAssertNotEqual(accessibilityValueText(NSNumber(value: 1)), "0")
        XCTAssertNil(accessibilityValueText(nil))
    }

    @MainActor
    func testCustomerIdentityAndWaitingForAppReadiness() {
        let customer = RevenueCatTestCustomer()
        XCTAssertNotEqual(customer.id, RevenueCatTestCustomer().id)
        XCTAssertEqual(customer.launchArguments.last, customer.id)
        XCTAssertEqual(customer.launchArguments, customer.launchArguments)
        let app = XCUIApplication()
        app.launchArguments = customer.launchArguments + ["--skip-walkthrough", "--reset-session"]
        app.launch()
        expectEnabled(app.buttons["book.menu"], timeout: 10)
    }
}
