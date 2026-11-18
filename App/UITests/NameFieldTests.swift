import XCTest

@MainActor
final class NameFieldTests: XCTestCase {
    override func setUp() async throws {
        continueAfterFailure = false
    }

    func testNameFieldStopsAt32Characters() {
        let app = XCUIApplication.launched(storedPlayerName: "")
        let field = app.textFields["playerName"]
        XCTAssertTrue(field.waitForExistence(timeout: 10), "name field not shown")
        field.tap()
        field.clearText()
        field.typeText("abcdefghijklmnopqrstuvwxyz123456")
        // One key at a time: a burst past the limit can outrun the truncation (#154).
        for key in "7890ABCD" { field.typeText(String(key)) }
        XCTAssertEqual(field.value as? String, "abcdefghijklmnopqrstuvwxyz123456")
    }

    func testPrefilledLongNameIsLimitedBeforeEditing() {
        assertPrefilledName(
            "abcdefghijklmnopqrstuvwxyz1234567890ABCD",
            becomes: "abcdefghijklmnopqrstuvwxyz123456", screenshot: "restored-ascii-name")
    }

    func testPrefilledUnicodeNameKeepsWholeCharacters() {
        assertPrefilledName(
            String(repeating: "👩🏽‍💻e\u{301}", count: 20),
            becomes: String(repeating: "👩🏽‍💻e\u{301}", count: 16), screenshot: "restored-unicode-name")
    }

    func testPrefilledValidNameIsPreserved() {
        let app = XCUIApplication.launched(theme: "felt", appearance: "light", storedPlayerName: "  Anna  ")
        defer { app.terminate() }
        let field = app.textFields["playerName"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        XCTAssertEqual(field.value as? String, "  Anna  ")
    }

    func testPrefilledEmptyNameStaysEmpty() {
        let app = XCUIApplication.launched(theme: "felt", appearance: "light", storedPlayerName: "")
        defer { app.terminate() }
        let field = app.textFields["playerName"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        let value = field.value as? String
        XCTAssertTrue(value == "" || value == field.placeholderValue)
    }

    private func assertPrefilledName(_ name: String, becomes expected: String, screenshot: String) {
        let app = XCUIApplication.launched(theme: "felt", appearance: "light", storedPlayerName: name)
        let field = app.textFields["playerName"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        // Swift equality also accepts canonically equivalent Unicode spellings returned by accessibility.
        let limited = NSPredicate { _, _ in field.value as? String == expected }
        let result = XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: limited, object: nil)], timeout: 10)
        XCTAssertEqual(field.value as? String, expected)
        XCTAssertEqual(result, .completed, "prefilled name was not limited before editing")
        app.attachScreenshot(screenshot)
        app.terminate()

        // Relaunch without seeding a name to check the shortened value was persisted.
        let reopened = XCUIApplication.launched(theme: "felt", appearance: "light")
        defer { reopened.terminate() }
        let restored = reopened.textFields["playerName"]
        XCTAssertTrue(restored.waitForExistence(timeout: 10))
        XCTAssertEqual(restored.value as? String, expected)
    }
}
