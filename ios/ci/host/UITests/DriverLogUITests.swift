import XCTest

// Taps through the app on a simulator with sample data (`-demo off|ld`, DemoBackend: nothing is sent anywhere).
// Mirrors the website's browser tests in tests/e2e.
final class DriverLogUITests: XCTestCase {
    private func launch(_ demo: String, screen: String? = nil) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-demo", demo] + (screen.map { ["-screen", $0] } ?? [])
        app.launch()
        return app
    }

    private func tab(_ app: XCUIApplication, _ name: String) {
        let button = app.tabBars.buttons[name]
        XCTAssertTrue(button.waitForExistence(timeout: 15), "\(name) tab")
        button.tap()
    }

    func testClockInFromOffTheClock() {
        let app = launch("off")
        tab(app, "LD")
        XCTAssertTrue(app.staticTexts["Off the clock"].waitForExistence(timeout: 10))
        app.buttons["Clock in"].tap()
        XCTAssertTrue(app.buttons["Preston office"].waitForExistence(timeout: 5))
        app.buttons["Save"].tap()
        XCTAssertTrue(app.staticTexts["Pre-trip inspection"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Driving left"].exists, "hours clocks show once clocked in")
    }

    func testFuelStopWithOtherPlace() {
        let app = launch("ld")
        tab(app, "LD")
        XCTAssertTrue(app.buttons["Fuel stop"].waitForExistence(timeout: 10))
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
        XCTAssertTrue(app.staticTexts["Driving"].waitForExistence(timeout: 10))
        let clear = app.buttons["ld-clear-day"]
        app.swipeUp()
        app.swipeUp()
        clear.tap()
        let confirm = app.alerts.buttons["Clear day"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        confirm.tap()
        XCTAssertTrue(app.staticTexts["Off the clock"].waitForExistence(timeout: 10))
    }

    func testInspectionView() {
        let app = launch("ld")
        tab(app, "LD")
        let button = app.buttons["Inspection view"]
        XCTAssertTrue(button.waitForExistence(timeout: 10))
        app.swipeUp()
        button.tap()
        XCTAssertTrue(app.staticTexts["Record of duty status"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Eric Talanoa"].exists)
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
