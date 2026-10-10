import XCTest

@MainActor final class BabytrackUITests: XCTestCase {
    func testBottleDiaperSleepAndLibrary() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-testing"]; app.launch()
        XCTAssertTrue(app.buttons["quickBottle"].waitForExistence(timeout: 15))
        openLog(app, "quickBottle")
        XCTAssertTrue(app.buttons["saveRecord"].waitForExistence(timeout: 5)); app.buttons["saveRecord"].tap()
        openLog(app, "quickDiaper")
        app.buttons["saveRecord"].tap()
        app.buttons["toggleSleep"].tap()
        XCTAssertTrue(app.staticTexts["sleepTimer"].waitForExistence(timeout: 5))
        app.buttons["toggleSleep"].tap()
        XCTAssertTrue(app.buttons["toggleSleep"].waitForExistence(timeout: 5))
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
        app.buttons["sleepTimeline"].tap()
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
        XCTAssertTrue(app.buttons["quickBottle"].waitForExistence(timeout: 15))
        let total = app.staticTexts["total-feeding"]
        XCTAssertTrue(total.waitForExistence(timeout: 5))
        let baseline = Double(total.label.split(separator: " ").first.map(String.init) ?? "") ?? 0
        openLog(app, "quickBottle"); app.buttons["saveRecord"].tap()
        let expected = String(format: "%.1f oz", baseline + 4)
        expectation(for: NSPredicate(format: "label BEGINSWITH %@", expected), evaluatedWith: total)
        waitForExpectations(timeout: 15)
    }

    func testCustomFormulaAndEditorScreenshots() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-testing"]; app.launch()
        XCTAssertTrue(app.buttons["quickBottle"].waitForExistence(timeout: 15))
        openLog(app, "quickBottle"); capture(app, "Bottle editor")
        app.buttons["formulaPicker"].tap(); app.buttons["Custom…"].tap()
        app.textFields["customFormulaName"].tap(); app.textFields["customFormulaName"].typeText("Example custom")
        app.buttons["addCustomFormula"].tap()
        XCTAssertTrue(app.buttons["formulaPicker"].waitForExistence(timeout: 5)); capture(app, "Custom formula selected")
        app.buttons["saveRecord"].tap(); openLog(app, "quickBottle")
        XCTAssertTrue(app.buttons["formulaPicker"].waitForExistence(timeout: 5)); XCTAssertEqual(app.buttons["formulaPicker"].value as? String, "Example custom"); capture(app, "Remembered formula")
        app.buttons["Cancel"].tap(); openLog(app, "quickDiaper"); capture(app, "Diaper editor"); app.buttons["Cancel"].tap()
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
        XCTAssertTrue(app.buttons["addRecord"].waitForExistence(timeout: 15)); capture(app, "Dark Today")
        for type in ["sleep", "reading", "medication", "temperature", "illness", "vaccine", "appointment", "milestone", "note", "reminder"] {
            app.buttons["addRecord"].tap()
            let action = app.buttons["add-\(type)"]
            let list = app.collectionViews.firstMatch
            for _ in 0 ..< 14 {
                // XCTest calls a partly clipped row hittable; its center may be outside the sheet.
                if action.exists, action.isHittable, action.frame.maxY <= list.frame.maxY - 8 {
                    break
                }
                list.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.75)).press(forDuration: 0.1, thenDragTo: list.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.55)))
            }
            XCTAssertTrue(action.exists); action.tap()
            XCTAssertTrue(app.buttons["saveRecord"].waitForExistence(timeout: 5)); capture(app, "\(type) editor")
            app.buttons["Cancel"].tap()
        }
    }

    func testLargeTextScreenshots() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-testing", "-appearance", "dark", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]; app.launch()
        XCTAssertTrue(app.buttons["quickBottle"].waitForExistence(timeout: 15)); capture(app, "Large text Today")
        openLog(app, "quickBottle"); XCTAssertTrue(app.buttons["saveRecord"].waitForExistence(timeout: 5)); capture(app, "Large text bottle")
        app.buttons["Cancel"].tap()
        for _ in 0 ..< 4 where !app.buttons["sleepTimeline"].isHittable {
            app.scrollViews.firstMatch.swipeUp()
        }
        app.buttons["sleepTimeline"].tap(); capture(app, "Large text sleep timeline")
        app.buttons["toggleSleep"].tap(); XCTAssertTrue(app.staticTexts["sleepTimer"].waitForExistence(timeout: 5))
        capture(app, "Large text active sleep")
        app.buttons["toggleSleep"].tap()
        navigate(app, "Health"); capture(app, "Large text health")
    }

    func testCompactSheetAndCombinedTimeWheel() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-testing"]; app.launch()
        XCTAssertTrue(app.buttons["quickBottle"].waitForExistence(timeout: 15))
        XCTAssertLessThan(app.buttons["quickBottle"].frame.minY, app.buttons["quickDiaper"].frame.minY)
        XCTAssertLessThan(app.buttons["quickDiaper"].frame.minY, app.buttons["sleepTimeline"].frame.minY)
        capture(app, "Compact care timelines")
        openLog(app, "quickBottle")
        XCTAssertTrue(app.buttons["saveRecord"].waitForExistence(timeout: 5))
        capture(app, "Compact bottle bottom sheet")
        if !app.buttons["nav-Today"].exists {
            XCTAssertGreaterThan(app.buttons["Cancel"].frame.minY, app.frame.height * 0.35)
        }
        XCTAssertLessThan(app.buttons["Cancel"].frame.midX, app.buttons["saveRecord"].frame.midX)
        let originalTime = app.buttons["startTime"].value as? String
        app.buttons["startTime"].tap()
        XCTAssertTrue(app.pickerWheels.firstMatch.waitForExistence(timeout: 5))
        XCTAssertEqual(app.pickerWheels.count, 4)
        capture(app, "Combined date and time wheel")
        let minute = app.pickerWheels.element(boundBy: 2)
        let digits = (minute.value as? String ?? "").components(separatedBy: CharacterSet.decimalDigits.inverted).joined()
        if let current = Int(digits) {
            minute.adjust(toPickerWheelValue: String(format: "%02d", (current + 5) % 60))
        } else {
            XCTFail("The combined picker did not expose its minute value")
        }
        app.buttons["startTime"].tap()
        XCTAssertNotEqual(app.buttons["startTime"].value as? String, originalTime)
        app.buttons["saveRecord"].tap()
        openLog(app, "quickDiaper"); capture(app, "Compact diaper bottom sheet"); app.buttons["Cancel"].tap()
        openLog(app, "sleepTimeline"); capture(app, "Compact sleep bottom sheet")
        app.buttons["endTime"].tap(); XCTAssertEqual(app.pickerWheels.count, 4)
        capture(app, "Combined sleep end wheel"); app.buttons["Cancel"].tap()
    }

    func testFilteredCareTimelines() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-testing"]; app.launch()
        XCTAssertTrue(app.buttons["quickBottle"].waitForExistence(timeout: 15))
        XCTAssertFalse(app.buttons["Add past sleep"].exists)
        XCTAssertLessThan(app.buttons["quickBottle"].frame.width, 100)
        XCTAssertLessThanOrEqual(app.buttons["quickBottle"].frame.maxY, app.buttons["feedingTimeline"].frame.minY)
        XCTAssertLessThanOrEqual(app.buttons["quickDiaper"].frame.maxY, app.buttons["diaperTimeline"].frame.minY)
        XCTAssertLessThanOrEqual(app.buttons["toggleSleep"].frame.maxY, app.buttons["sleepTimeline"].frame.minY)
        for (option, type) in [("feedingTimeline", "feeding"), ("diaperTimeline", "diaper"), ("sleepTimeline", "sleep")] {
            app.buttons[option].tap()
            XCTAssertEqual(app.buttons[option].value as? String, "Expanded")
            XCTAssertTrue(app.buttons.matching(identifier: "timeline-\(type)").firstMatch.exists)
            for other in ["feeding", "diaper", "sleep"] where other != type {
                XCTAssertFalse(app.buttons["timeline-\(other)"].exists)
            }
            capture(app, "\(type) inline history")
            app.buttons[option].tap()
            XCTAssertEqual(app.buttons[option].value as? String, "Collapsed")
        }
    }

    func testLargeHistoryDropdownPerformance() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-testing", "--history-stress-testing"]; app.launch()
        XCTAssertTrue(app.buttons["quickBottle"].waitForExistence(timeout: 15))
        let options = XCTMeasureOptions(); options.iterationCount = 3
        measure(metrics: [XCTClockMetric(), XCTCPUMetric(application: app)], options: options) {
            app.buttons["feedingTimeline"].tap()
            XCTAssertTrue(app.buttons.matching(identifier: "timeline-feeding").firstMatch.exists)
            app.buttons["feedingTimeline"].tap()
            XCTAssertEqual(app.buttons["feedingTimeline"].value as? String, "Collapsed")
        }
        capture(app, "Large history Today")
    }

    func testProfilePhotoEditors() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-testing"]; app.launch()
        XCTAssertTrue(app.buttons["quickBottle"].waitForExistence(timeout: 15))
        if app.buttons["nav-Family"].exists {
            navigate(app, "Family")
        } else {
            navigate(app, "More"); app.buttons["Family"].tap()
        }
        XCTAssertTrue(app.staticTexts["Caregivers"].exists)
        app.buttons["Edit caregiver profile"].tap()
        XCTAssertTrue(app.buttons["Add profile photo"].waitForExistence(timeout: 5))
        capture(app, "Caregiver photo editor"); app.buttons["Cancel"].tap()
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Sample child")).firstMatch.tap()
        app.buttons["Edit"].tap()
        let picker = app.buttons["Add profile photo"]
        for _ in 0 ..< 4 where !picker.isHittable {
            app.scrollViews.firstMatch.swipeUp()
        }
        XCTAssertTrue(picker.exists); capture(app, "Child profile photo editor")
        app.buttons["Cancel"].tap()
    }

    private func openLog(_ app: XCUIApplication, _ option: String) {
        if app.buttons["logRecord"].exists {
            app.navigationBars.buttons["BackButton"].tap()
        }
        XCTAssertTrue(app.buttons[option].waitForExistence(timeout: 5)); app.buttons[option].tap()
        if option == "sleepTimeline" {
            app.buttons["addRecord"].tap(); app.buttons["add-sleep"].tap()
        }
        XCTAssertTrue(app.buttons["saveRecord"].waitForExistence(timeout: 5))
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
