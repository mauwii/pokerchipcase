import XCTest

extension XCUIApplication {
    /// Launches the app in English with the given debug launch arguments.
    /// `theme` and `appearance` pin the look; sweeps never pass them, because a
    /// launch argument wins over the Settings sheet.
    /// `storedPlayerName` seeds the saved preference without overriding subsequent writes.
    @discardableResult
    static func launched(
        debugTable: Bool = false,
        stop: String? = nil,
        digitalCards: Bool = false,
        fourColorDeck: Bool = false,
        playerName: String? = nil,
        theme: String? = nil,
        appearance: String? = nil,
        storedPlayerName: String? = nil
    ) -> XCUIApplication {
        let app = XCUIApplication()
        var args = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        if debugTable { args.append("-debugTable") }
        if let stop { args += ["-debugStop", stop] }
        if digitalCards { args += ["-digitalCards", "YES"] }
        if fourColorDeck { args += ["-fourColorDeck", "YES"] }
        if let playerName { args += ["-playerName", playerName] }
        if let theme { args += ["-theme", theme] }
        if let appearance { args += ["-appearance", appearance] }
        app.launchArguments = args
        if let storedPlayerName { app.launchEnvironment["POKERCHIPCASE_STORED_PLAYER_NAME"] = storedPlayerName }
        app.launch()
        return app
    }
}

extension XCUIApplication {
    /// Waits until the debug table rests at `stop`: `turn` is the host's own turn
    /// (enabled Fold button), `payout` is a digital game after its first paid-out
    /// showdown (Next hand button). Fails the test when `timeout` passes first.
    func waitForTableStop(_ stop: String, timeout: TimeInterval = 120) {
        let button = switch stop {
        case "turn": buttons["Fold"]
        case "payout": buttons["Next hand"]
        default: preconditionFailure("unknown table stop \(stop)")
        }
        let reached = NSPredicate(format: "exists == true AND isEnabled == true")
        let result = XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: reached, object: button)], timeout: timeout)
        XCTAssertEqual(result, .completed, "table did not reach stop \(stop)")
    }
}

extension XCUIElement {
    /// Deletes the current text value, if any. Taps the trailing edge first so
    /// the caret sits at the end, where delete keys remove text.
    func clearText() {
        guard let value = value as? String, !value.isEmpty, value != placeholderValue else { return }
        coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: 0.5)).tap()
        typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: value.count))
    }
}
