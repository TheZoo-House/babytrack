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

    func testCustomFormulaAndEditorScreenshots() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-testing"]; app.launch()
        XCTAssertTrue(app.buttons["quickBottle"].waitForExistence(timeout: 15))
        app.buttons["quickBottle"].tap(); capture(app, "Bottle editor")
        app.buttons["formulaPicker"].tap(); app.buttons["Custom…"].tap()
        app.textFields["customFormulaName"].tap(); app.textFields["customFormulaName"].typeText("Example custom")
        app.buttons["addCustomFormula"].tap()
        XCTAssertTrue(app.buttons["formulaPicker"].waitForExistence(timeout: 5)); capture(app, "Custom formula selected")
        app.buttons["saveRecord"].tap(); app.buttons["quickBottle"].tap()
        XCTAssertTrue(app.buttons["formulaPicker"].waitForExistence(timeout: 5)); XCTAssertEqual(app.buttons["formulaPicker"].value as? String, "Example custom"); capture(app, "Remembered formula")
        app.buttons["Cancel"].tap(); app.buttons["quickDiaper"].tap(); capture(app, "Diaper editor"); app.buttons["Cancel"].tap()
        navigate(app, "Health"); navigate(app, "Growth"); capture(app, "Growth")
        app.buttons["Add measurement"].tap(); capture(app, "Measurement editor"); app.buttons["Cancel"].tap()
    }

    func testImportPreviewCommitAndSettingsScreenshots() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-http-test"]; app.launch()
        app.buttons["trySample"].tap(); XCTAssertTrue(app.buttons["quickBottle"].waitForExistence(timeout: 15))
        if app.buttons["nav-Settings"].exists {
            navigate(app, "Settings")
        } else {
            navigate(app, "More"); app.buttons["Settings"].tap()
        }
        capture(app, "Settings")
        app.buttons["Account & data"].tap(); capture(app, "Account")
        app.buttons["Import Nara Baby"].tap(); capture(app, "Import")
        app.buttons["chooseNaraCSV"].tap()
        XCTAssertTrue(app.buttons["commitNaraImport"].waitForExistence(timeout: 15)); capture(app, "Nara preview")
        app.buttons["commitNaraImport"].tap()
        XCTAssertTrue(app.staticTexts["importResult"].waitForExistence(timeout: 15)); capture(app, "Import complete")
        XCTAssertTrue(app.staticTexts["importResult"].label.contains("Imported 11 records"))
        navigate(app, "Today"); app.buttons["See all"].tap()
        let diaper = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Diaper, Both")).firstMatch
        for _ in 0 ..< 5 where !diaper.isHittable {
            app.collectionViews.firstMatch.swipeUp()
        }
        XCTAssertTrue(diaper.waitForExistence(timeout: 5)); diaper.tap(); capture(app, "Imported record details")
        XCTAssertTrue(app.staticTexts["Nara Baby"].exists)
        app.buttons["Edit"].tap(); XCTAssertTrue(app.buttons["saveRecord"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["color"].value as? String, "Brown Yellow")
        XCTAssertEqual(app.buttons["consistency"].value as? String, "Mucous Mushy")
        capture(app, "Imported diaper editor"); app.buttons["Cancel"].tap()
    }

    func testAllPagesScreenshots() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-testing"]; app.launch()
        XCTAssertTrue(app.buttons["quickBottle"].waitForExistence(timeout: 15))
        navigate(app, "Library"); app.buttons.containing(.staticText, identifier: "Goodnight Moon").firstMatch.tap(); capture(app, "Book details"); app.buttons["Close"].tap()
        app.buttons["addItem"].tap(); capture(app, "Book editor"); app.buttons["Cancel"].tap()
        if app.buttons["nav-Family"].exists {
            navigate(app, "Family")
        } else {
            navigate(app, "More"); app.buttons["Family"].tap()
        }
        capture(app, "Family")
        if app.buttons["nav-Settings"].exists {
            navigate(app, "Settings")
        } else {
            app.navigationBars.buttons["BackButton"].tap(); app.buttons["Settings"].tap()
        }
        for page in ["Appearance & units", "Notifications & reminders", "Connection & sync", "Account & data"] {
            app.buttons[page].tap(); capture(app, page); app.navigationBars.buttons["BackButton"].tap()
        }
        if app.buttons["nav-Journal"].exists {
            navigate(app, "Journal")
        } else {
            app.navigationBars.buttons["BackButton"].tap(); app.buttons["Journal"].tap()
        }
        capture(app, "Journal")
    }

    func testRemainingEditors() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-testing", "-appearance", "dark"]; app.launch()
        XCTAssertTrue(app.buttons["addRecord"].waitForExistence(timeout: 15))
        for type in ["sleep", "reading", "medication", "temperature", "illness", "vaccine", "appointment", "milestone", "note", "reminder"] {
            app.buttons["addRecord"].tap()
            let action = app.buttons["add-\(type)"]
            for _ in 0 ..< 4 where !action.isHittable {
                app.collectionViews.firstMatch.swipeUp()
            }
            XCTAssertTrue(action.exists); action.tap()
            XCTAssertTrue(app.buttons["saveRecord"].waitForExistence(timeout: 5)); capture(app, "\(type) editor")
            app.buttons["Cancel"].tap()
        }
    }

    func testLargeTextScreenshots() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-testing", "-appearance", "dark", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]; app.launch()
        XCTAssertTrue(app.buttons["quickBottle"].waitForExistence(timeout: 15)); capture(app, "Large text Today")
        app.buttons["quickBottle"].tap(); XCTAssertTrue(app.buttons["saveRecord"].waitForExistence(timeout: 5)); capture(app, "Large text bottle")
        app.buttons["Cancel"].tap(); navigate(app, "Health"); capture(app, "Large text health")
    }

    private func navigate(_ app: XCUIApplication, _ name: String) {
        let sidebar = app.buttons["nav-\(name)"]
        if sidebar.exists {
            sidebar.tap()
        } else {
            app.buttons[name].tap()
        }
    }

    private func capture(_ app: XCUIApplication, _ name: String) {
        // Let native sheet/navigation transitions finish before recording evidence.
        let settled = expectation(description: "Native transition settled")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { settled.fulfill() }
        wait(for: [settled], timeout: 2)
        let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = name; attachment
            .lifetime = .keepAlways; add(attachment)
    }
}
