import XCTest

extension XCUIApplication {
    /// Opens Settings through `openSettings` for each theme and brightness and picks both. Then audits
    /// (with `auditTypes`) and photographs `screen`; with `auditsSettings`, the sheet before it too.
    /// Ends on the defaults, Felt and System, so later tests start from them.
    func sweepThemes(screen: String, auditTypes: XCUIAccessibilityAuditType = .all, auditsSettings: Bool = false,
                     openSettings: () -> Void) {
        let themes = [("Felt", "felt"), ("Neon", "neon"), ("Rubin", "ruby"), ("Royal", "royal")]
        let brightnesses = [("Light", "light"), ("Dark", "dark")]
        for (themeLabel, theme) in themes {
            for (brightnessLabel, brightness) in brightnesses {
                openSettings()
                pick(theme: themeLabel, brightness: brightnessLabel, on: screen)
                if auditsSettings {
                    audit(self, screen: "settings")
                    attachScreenshot("settings-\(theme)-\(brightness)")
                }
                closeSettings(on: screen)
                audit(self, screen: screen, types: auditTypes)
                attachScreenshot("\(screen)-\(theme)-\(brightness)")
            }
        }
        openSettings()
        pick(theme: "Felt", brightness: "System", on: screen)
        if auditsSettings {
            audit(self, screen: "settings")
            attachScreenshot("settings-felt-system")
        }
        closeSettings(on: screen)
    }

    /// Picks both in the open Settings sheet and waits until the sheet shows them.
    private func pick(theme: String, brightness: String, on screen: String) {
        // The menu picker's row reads "Theme, <current theme>".
        let picker = buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Theme, ")).firstMatch
        XCTAssertTrue(picker.waitForExistence(timeout: 10), "Settings sheet not shown on \(screen)")
        picker.tap()
        // Taps wait for their element and fail naming it, so no extra wait before them.
        buttons[theme].tap()
        let segment = segmentedControls.buttons[brightness]
        segment.tap()
        // A launch argument or a missed tap would keep the old theme: fail instead of auditing it again.
        waitFor(picker, "label == %@", "Theme, \(theme)", "Theme picker does not show \(theme)")
        waitFor(segment, "isSelected == %@", true, "Brightness \(brightness) not selected")
    }

    private func closeSettings(on screen: String) {
        let done = navigationBars["Settings"].buttons["Done"]
        done.tap()
        waitFor(done, "exists == %@", false, "Settings sheet did not close on \(screen)")
    }

    /// Waits until `object` (an element or a query) matches `format` with `value`, or fails with `message`.
    func waitFor(_ object: Any, _ format: String, _ value: Any, _ message: String, timeout: TimeInterval = 10) {
        let predicate = NSPredicate(format: format, argumentArray: [value])
        let result = XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: object)], timeout: timeout)
        XCTAssertEqual(result, .completed, message)
    }

    /// Keeps a screenshot of the app in the result bundle under `name`.
    func attachScreenshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        XCTContext.runActivity(named: name) { $0.add(attachment) }
    }
}

/// Runs the accessibility audit for `types` on what `app` shows now, named `screen`; known findings pass.
@MainActor
func audit(_ app: XCUIApplication, screen: String, types: XCUIAccessibilityAuditType = .all) {
    do {
        try app.performAccessibilityAudit(for: types) { KnownAuditIssues.ignores($0, on: screen) }
    } catch {
        XCTFail("accessibility audit of \(screen) could not run: \(error)")
    }
}
