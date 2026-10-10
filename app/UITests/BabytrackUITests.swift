import XCTest

@MainActor final class BabytrackUITests: XCTestCase {
    func testBottleDiaperSleepAndLibrary() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-testing"]; app.launch()
        XCTAssertTrue(app.buttons["quickBottle"].waitForExistence(timeout: 15))
        app.buttons["quickBottle"].tap()
        XCTAssertTrue(app.buttons["saveRecord"].waitForExistence(timeout: 5)); app.buttons["saveRecord"].tap()
        XCTAssertTrue(app.buttons["quickDiaper"].waitForExistence(timeout: 5)); app.buttons["quickDiaper"].tap()
        app.buttons["saveRecord"].tap()
        app.buttons["toggleSleep"].tap()
        XCTAssertTrue(app.staticTexts["sleepTimer"].waitForExistence(timeout: 5))
        app.buttons["toggleSleep"].tap()
        XCTAssertTrue(app.buttons["Start sleep"].waitForExistence(timeout: 5))
        navigate(app, "Library")
        XCTAssertTrue(app.staticTexts["Goodnight Moon"].waitForExistence(timeout: 5))
        app.buttons["addItem"].tap(); app.textFields["recordTitle"].tap(); app.textFields["recordTitle"]
            .typeText("Sample Story")
        app.buttons["saveRecord"].tap()
        XCTAssertTrue(app.staticTexts["Sample Story"].waitForExistence(timeout: 5))
    }

    func testScreenshots() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-testing"]; app.launch()
        XCTAssertTrue(app.buttons["quickBottle"].waitForExistence(timeout: 15))
        let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = "Today"; attachment
            .lifetime = .keepAlways; add(attachment)
        app.buttons["toggleSleep"].tap()
        XCTAssertTrue(app.staticTexts["sleepTimer"].waitForExistence(timeout: 5))
        capture(app, "Sleeping")
        navigate(app, "Library")
        XCTAssertTrue(app.staticTexts["Goodnight Moon"].waitForExistence(timeout: 5)); capture(app, "Library")
        navigate(app, "Health")
        capture(app, "Health")
    }

    func testIsolatedBackendBottleSync() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-http-test"]; app.launch()
        XCTAssertTrue(app.buttons["trySample"].waitForExistence(timeout: 10)); app.buttons["trySample"].tap()
        XCTAssertTrue(app.buttons["quickBottle"].waitForExistence(timeout: 15)); app.buttons["quickBottle"].tap()
        app.buttons["saveRecord"].tap()
        XCTAssertTrue(app.staticTexts["12.0 oz"].waitForExistence(timeout: 15))
    }

    private func navigate(_ app: XCUIApplication, _ name: String) {
        let sidebar = app.buttons["nav-\(name)"]
        if sidebar.exists { sidebar.tap() } else { app.buttons[name].tap() }
    }

    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = name; attachment
            .lifetime = .keepAlways; add(attachment)
    }
}
