import XCTest

// Taps through the app on a simulator with sample data (`-demo off|ld`, DemoBackend: nothing is sent anywhere).
// Mirrors the website's browser tests in tests/e2e.
final class DriverLogUITests: XCTestCase {
    private func launch(_ demo: String, screen: String? = nil, extra: [String] = []) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-demo", demo] + (screen.map { ["-screen", $0] } ?? []) + extra
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 60), "the app started")
        return app
    }

    /// Waits until a button can be tapped (the screen shows before the log finishes loading).
    private func ready(_ button: XCUIElement, _ what: String) {
        XCTAssertTrue(button.waitForExistence(timeout: 15), "\(what) exists")
        let enabled = expectation(for: NSPredicate(format: "isEnabled == true"), evaluatedWith: button)
        wait(for: [enabled], timeout: 15)
    }

    private func tab(_ app: XCUIApplication, _ name: String) {
        let button = app.tabBars.buttons[name]
        XCTAssertTrue(button.waitForExistence(timeout: 15), "\(name) tab")
        button.tap()
    }

    func testTutorialOnFirstLaunch() {
        let app = launch("off", extra: ["-tutorial", "show"])
        XCTAssertTrue(app.staticTexts["Welcome to Driver Log"].waitForExistence(timeout: 15), "the cards open on first launch")
        for _ in 0..<4 { app.buttons["Next"].tap() }
        XCTAssertTrue(app.staticTexts["Pulled over?"].waitForExistence(timeout: 5), "last card")
        app.buttons["Show me around"].tap()
        let titles = ["Local day? Start here", "Your day, the way an officer reads it", "LD day: tap what you're doing", "Your hours", "Pulled over or inspected?"]
        for (i, title) in titles.enumerated() {
            XCTAssertTrue(app.staticTexts[title].waitForExistence(timeout: 10), "tip \(i + 1): \(title)")
            app.buttons[i == titles.count - 1 ? "Done" : "Next"].tap()
        }
        XCTAssertFalse(app.staticTexts["Pulled over or inspected?"].waitForExistence(timeout: 2), "the tips close after Done")
        XCTAssertTrue(app.buttons["Inspection view"].exists, "back on the LD tab")
    }

    func testTutorialReplaysFromSettings() {
        let app = launch("off")
        let gear = app.buttons["Driver and vehicle settings"]
        XCTAssertTrue(gear.waitForExistence(timeout: 15))
        XCTAssertFalse(app.staticTexts["Welcome to Driver Log"].exists, "not shown once seen")
        gear.tap()
        let replay = app.buttons["Show tutorial again"]
        XCTAssertTrue(replay.waitForExistence(timeout: 5))
        replay.tap()
        XCTAssertTrue(app.staticTexts["Welcome to Driver Log"].waitForExistence(timeout: 10), "replayed from Settings")
        app.buttons["Skip"].tap()
        XCTAssertFalse(app.staticTexts["Welcome to Driver Log"].waitForExistence(timeout: 3), "Skip closes it")
    }

    func testClockInFromOffTheClock() {
        let app = launch("off")
        tab(app, "LD")
        XCTAssertTrue(app.staticTexts["Off the clock"].waitForExistence(timeout: 10), "LD tab starts off the clock")
        ready(app.buttons["Clock in"], "Clock in")
        app.buttons["Clock in"].tap()
        XCTAssertTrue(app.buttons["Preston office"].waitForExistence(timeout: 5), "Preston office option. Buttons: \(app.buttons.allElementsBoundByIndex.map(\.label))")
        app.buttons["Save"].tap()
        XCTAssertTrue(app.staticTexts["Pre-trip inspection"].waitForExistence(timeout: 10), "heading after clock in. Texts: \(app.staticTexts.allElementsBoundByIndex.prefix(30).map(\.label))")
        XCTAssertTrue(app.staticTexts["Driving left"].waitForExistence(timeout: 5), "hours clocks show once clocked in")
    }

    func testFuelStopWithOtherPlace() {
        let app = launch("ld")
        tab(app, "LD")
        ready(app.buttons["Fuel stop"], "Fuel stop")
        app.buttons["Fuel stop"].tap()
        app.buttons["Other"].tap()
        let field = app.textFields["City, address or hotel"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("Cle Elum")
        app.buttons["Save"].tap()
        XCTAssertTrue(app.staticTexts["Fueling"].waitForExistence(timeout: 10))
    }

    func testClearDayResetsTheLdTab() {
        let app = launch("ld")
        tab(app, "LD")
        XCTAssertTrue(app.staticTexts["Driving"].firstMatch.waitForExistence(timeout: 10), "LD tab shows the drive")
        let clear = app.buttons["ld-clear-day"]
        XCTAssertTrue(clear.waitForExistence(timeout: 5), "Clear day button. Buttons: \(app.buttons.allElementsBoundByIndex.map(\.label))")
        ready(clear, "Clear day")
        for _ in 0..<4 where !clear.isHittable { app.swipeUp() }
        clear.tap()
        let confirm = app.alerts.buttons["Clear day"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5), "confirmation. Alerts: \(app.alerts.allElementsBoundByIndex.map(\.label))")
        confirm.tap()
        XCTAssertTrue(app.staticTexts["Off the clock"].waitForExistence(timeout: 10), "reset after clearing. Texts: \(app.staticTexts.allElementsBoundByIndex.prefix(30).map(\.label))")
    }

    func testInspectionView() {
        let app = launch("ld")
        tab(app, "LD")
        let button = app.buttons["Inspection view"]
        XCTAssertTrue(button.waitForExistence(timeout: 10))
        app.swipeUp()
        button.tap()
        XCTAssertTrue(app.staticTexts["Record of duty status"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Sample Driver"].exists)
    }

    func testHistoryShowsTheLdTrip() {
        let app = launch("ld")
        tab(app, "History")
        XCTAssertTrue(app.staticTexts["LD"].firstMatch.waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["2 days · 501.0 mi"].exists || app.staticTexts.containing(NSPredicate(format: "label CONTAINS '2 days'")).firstMatch.exists)
    }

    func testTodayEditDayOpensTheShift() {
        let app = launch("ld")
        let previous = app.buttons["Previous day"]
        XCTAssertTrue(previous.waitForExistence(timeout: 15))
        // Four days back is the second day of the sample LD trip.
        for _ in 0..<4 { previous.tap() }
        let edit = app.buttons["Edit day"]
        XCTAssertTrue(edit.waitForExistence(timeout: 5))
        edit.tap()
        XCTAssertTrue(app.staticTexts["Fix this day"].waitForExistence(timeout: 10) || app.navigationBars["Fix this day"].exists)
    }
}
