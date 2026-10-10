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
        let expected = (baseline + 4).formatted(.number.precision(.fractionLength(0 ... 1))) + " oz"
        expectation(for: NSPredicate(format: "label BEGINSWITH %@", expected), evaluatedWith: total)
        waitForExpectations(timeout: 15)
    }

    func testCustomFormulaAndEditorScreenshots() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-testing"]; app.launch()
        XCTAssertTrue(app.buttons["quickBottle"].waitForExistence(timeout: 15))
        openLog(app, "quickBottle"); capture(app, "Bottle editor")
        app.buttons["formulaPicker"].tap(); app.buttons["customFormula"].tap()
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
        let diaper = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Diaper, Wet, Dirty")).firstMatch
        for _ in 0 ..< 5 where !diaper.isHittable {
            sheetOrList(app).swipeUp()
        }
        XCTAssertTrue(diaper.waitForExistence(timeout: 5)); diaper.tap(); capture(app, "Imported record details")
        for _ in 0 ..< 4 where !app.staticTexts["Nara Baby"].exists { sheetOrList(app).swipeUp() }
        XCTAssertTrue(app.staticTexts["Nara Baby"].exists)
        app.buttons["Edit"].tap(); XCTAssertTrue(app.buttons["saveRecord"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["diaper-color-Brown"].isSelected)
        XCTAssertTrue(app.buttons["diaper-color-Yellow"].isSelected)
        XCTAssertTrue(app.buttons["diaper-consistency-Mucous"].isSelected)
        XCTAssertTrue(app.buttons["diaper-consistency-Mushy"].isSelected)
        capture(app, "Imported diaper editor"); app.buttons["Cancel"].tap()
    }

    func testDirectDiaperControls() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-http-test"]; app.launch()
        app.buttons["trySample"].tap(); XCTAssertTrue(app.buttons["quickDiaper"].waitForExistence(timeout: 15))
        openLog(app, "quickDiaper")
        XCTAssertTrue(app.buttons["diaper-Wet"].isSelected)
        app.buttons["diaper-Dirty"].tap()
        XCTAssertTrue(app.buttons["diaper-Wet"].isSelected)
        XCTAssertTrue(app.buttons["diaper-Dirty"].isSelected)
        XCTAssertTrue(app.buttons["diaper-consistency-Mushy"].waitForExistence(timeout: 5))
        app.buttons["diaper-consistency-Mushy"].tap(); app.buttons["diaper-consistency-Mucous"].tap()
        app.buttons["diaper-color-Brown"].tap(); app.buttons["diaper-color-Yellow"].tap()
        app.switches["diaperBlowout"].tap(); app.switches["diaperRash"].tap()
        capture(app, "Direct diaper choices")
        app.buttons["saveRecord"].tap()
        let saved = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Blowout")).firstMatch
        XCTAssertTrue(saved.waitForExistence(timeout: 15)); saved.tap()
        app.buttons["Edit"].tap()
        XCTAssertTrue(app.buttons["diaper-color-Brown"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["diaper-color-Brown"].isSelected)
        XCTAssertTrue(app.buttons["diaper-color-Yellow"].isSelected)
        XCTAssertTrue(app.buttons["diaper-consistency-Mucous"].isSelected)
        XCTAssertEqual(app.switches["diaperBlowout"].value as? String, "1")
        app.buttons["diaper-Dry"].tap()
        XCTAssertTrue(app.buttons["diaper-Dry"].isSelected)
        XCTAssertFalse(app.buttons["diaper-Wet"].isSelected)
        XCTAssertFalse(app.buttons["diaper-Dirty"].isSelected)
        XCTAssertFalse(app.buttons["diaperDetails"].exists)
        capture(app, "Dry diaper sheet"); app.buttons["Cancel"].tap()
    }

    func testEditedDiaperUpdatesLocalPreview() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-testing"]; app.launch()
        XCTAssertTrue(app.buttons["quickDiaper"].waitForExistence(timeout: 15))
        let old = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Diaper, Wet")).firstMatch
        XCTAssertTrue(old.waitForExistence(timeout: 5)); old.tap(); app.buttons["Edit"].tap()
        XCTAssertTrue(app.buttons["diaper-Dirty"].waitForExistence(timeout: 5)); app.buttons["diaper-Dirty"].tap()
        app.switches["diaperBlowout"].tap(); app.buttons["saveRecord"].tap()
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Wet, Dirty · Blowout")).firstMatch.waitForExistence(timeout: 5))
    }

    func testBottleAmountShortcutAndReplacement() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-testing"]; app.launch()
        XCTAssertTrue(app.buttons["quickBottle"].waitForExistence(timeout: 15)); openLog(app, "quickBottle")
        XCTAssertFalse(app.buttons["unit-oz"].exists); XCTAssertFalse(app.buttons["unit-mL"].exists)
        XCTAssertTrue(app.staticTexts["bottleUnit"].exists)
        let amount = app.textFields["amount"]
        amount.tap(); XCTAssertFalse(app.buttons["saveRecord"].isEnabled)
        amount.typeText("6.5"); app.buttons["saveRecord"].tap()
        openLog(app, "quickBottle")
        XCTAssertTrue(app.buttons["reuseBottleAmount"].label.contains("6.5 oz"))
        app.buttons["reuseBottleAmount"].tap(); XCTAssertEqual(amount.value as? String, "6.5")
        capture(app, "Bottle last amount shortcut")
        amount.tap(); XCTAssertFalse(app.buttons["saveRecord"].isEnabled)
        amount.typeText("3.5"); app.buttons["saveRecord"].tap()
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "3.5 oz")).firstMatch.waitForExistence(timeout: 5))
    }

    func testCenteredDiaperBubblesAndAnchoredDelete() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-testing"]; app.launch()
        XCTAssertTrue(app.buttons["quickDiaper"].waitForExistence(timeout: 15)); openLog(app, "quickDiaper")
        let wet = app.buttons["diaper-Wet"].frame, dry = app.buttons["diaper-Dry"].frame
        XCTAssertEqual((wet.minX + dry.maxX) / 2, app.frame.midX, accuracy: 3)
        capture(app, "Centered diaper bubbles"); app.buttons["Cancel"].tap()
        let old = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Diaper, Wet")).firstMatch
        old.tap()
        let button = app.buttons["deleteRecord"]
        for _ in 0 ..< 6 where !button.isHittable { sheetOrList(app).swipeUp() }
        button.tap(); XCTAssertTrue(app.staticTexts["deleteConfirmation"].waitForExistence(timeout: 5))
        capture(app, "Delete button confirmation")
        XCTAssertLessThan(app.buttons["confirmDestructiveAction"].frame.width, app.frame.width * 0.8)
        app.buttons["cancelDestructiveAction"].tap(); XCTAssertTrue(button.exists)
        button.tap(); app.buttons["confirmDestructiveAction"].tap()
        XCTAssertTrue(app.buttons["quickDiaper"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Diaper, Wet")).firstMatch.exists)
    }

    func testTodayCountersAfterSavingCare() throws {
        let app = XCUIApplication(); app.launchArguments = ["--ui-testing"]; app.launch()
        XCTAssertTrue(app.buttons["quickBottle"].waitForExistence(timeout: 15))
        let oldFeed = try XCTUnwrap(Double(app.staticTexts["total-feeding"].label.split(separator: " ").first.map(String.init) ?? ""))
        openLog(app, "quickBottle"); app.buttons["saveRecord"].tap()
        XCTAssertEqual(try XCTUnwrap(Double(app.staticTexts["total-feeding"].label.split(separator: " ").first.map(String.init) ?? "")), oldFeed + 4, accuracy: 0.1)
        let oldDiapers = try XCTUnwrap(Int(app.staticTexts["total-diaper"].label.split(separator: " ").first.map(String.init) ?? ""))
        openLog(app, "quickDiaper"); app.buttons["saveRecord"].tap()
        XCTAssertTrue(app.staticTexts["total-diaper"].label.hasPrefix("\(oldDiapers + 1) "))
        openLog(app, "sleepTimeline"); app.buttons["saveRecord"].tap()
        XCTAssertFalse(app.staticTexts["total-sleep"].label.hasPrefix("0m"))
        XCTAssertTrue(app.buttons["timeline-sleep"].firstMatch.label.contains("60 min"))
        capture(app, "Today counters after care saves")
    }

    func testEditingActiveSleepKeepsTimerRunning() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-testing"]; app.launch()
        XCTAssertTrue(app.buttons["toggleSleep"].waitForExistence(timeout: 15)); app.buttons["toggleSleep"].tap()
        XCTAssertTrue(app.staticTexts["sleepTimer"].waitForExistence(timeout: 5))
        let active = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Sleep, Nap")).firstMatch
        XCTAssertTrue(active.waitForExistence(timeout: 5)); active.tap(); app.buttons["Edit"].tap()
        XCTAssertTrue(app.buttons["saveRecord"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["endTime"].exists)
        app.buttons["category-Night"].tap(); app.buttons["saveRecord"].tap()
        XCTAssertTrue(app.staticTexts["sleepTimer"].waitForExistence(timeout: 5))
        capture(app, "Edited running sleep remains active")
    }

    func testBottleMilkChoicesHideFormulaForBreastMilk() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-testing"]; app.launch()
        XCTAssertTrue(app.buttons["quickBottle"].waitForExistence(timeout: 15)); openLog(app, "quickBottle")
        app.buttons["milkType-Breast milk"].tap(); XCTAssertFalse(app.buttons["formulaPicker"].exists)
        capture(app, "Breast milk bottle")
        app.buttons["saveRecord"].tap()
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Breast milk")).firstMatch.waitForExistence(timeout: 5))
    }

    func testMedicationLogAgainPreservesFieldsAndShowsLastRecord() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-testing"]; app.launch()
        XCTAssertTrue(app.buttons["addRecord"].waitForExistence(timeout: 15)); openRecordMenu(app, "medication")
        app.textFields["recordTitle"].tap(); app.textFields["recordTitle"].typeText("Example medicine")
        app.textFields["dose"].tap(); app.textFields["dose"].typeText("2.5")
        app.textFields["unit"].tap(); app.textFields["unit"].typeText("mL")
        app.buttons["saveRecord"].tap(); navigate(app, "Health"); app.buttons["Medication"].tap()
        let record = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Example medicine")).firstMatch
        XCTAssertTrue(record.waitForExistence(timeout: 5)); record.tap(); app.buttons["logMedicationAgain"].tap()
        XCTAssertTrue(app.buttons["saveRecord"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.textFields["dose"].value as? String, "2.5"); XCTAssertEqual(app.textFields["unit"].value as? String, "mL")
        XCTAssertTrue(app.staticTexts["lastMedication"].exists); capture(app, "Medication log again")
        app.buttons["saveRecord"].tap()
    }

    func testJournalReportAndCaregiverHandoffScreens() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-testing"]; app.launch()
        XCTAssertTrue(app.buttons["quickBottle"].waitForExistence(timeout: 15))
        if app.buttons["nav-Journal"].exists { navigate(app, "Journal") } else { navigate(app, "More"); app.buttons["Journal"].tap() }
        XCTAssertTrue(app.staticTexts["journalDayTotals"].firstMatch.exists); app.buttons["openCareReport"].tap()
        XCTAssertTrue(app.buttons["shareCareReport"].waitForExistence(timeout: 5)); XCTAssertTrue(app.buttons["shareCareReport"].isEnabled)
        capture(app, "Date-range care report"); app.buttons["shareCareReport"].tap()
        let closeShare = app.buttons["Close"].firstMatch
        XCTAssertTrue(closeShare.waitForExistence(timeout: 5)); capture(app, "Native PDF share"); closeShare.tap()
        app.buttons["Cancel"].tap()
        if app.buttons["nav-Family"].exists { navigate(app, "Family") } else { app.navigationBars.buttons["BackButton"].tap(); app.buttons["Family"].tap() }
        app.buttons["openHandoff"].tap(); XCTAssertTrue(app.buttons["markHandoffSeen"].waitForExistence(timeout: 5))
        capture(app, "Caregiver handoff"); app.buttons["markHandoffSeen"].tap()
    }

    func testReminderSnoozeAndDoneFlows() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-testing"]; app.launch()
        XCTAssertTrue(app.buttons["addRecord"].waitForExistence(timeout: 15)); openRecordMenu(app, "reminder")
        app.textFields["recordTitle"].tap(); app.textFields["recordTitle"].typeText("Example reminder"); app.buttons["saveRecord"].tap()
        if app.buttons["nav-Settings"].exists { navigate(app, "Settings") } else { navigate(app, "More"); app.buttons["Settings"].tap() }
        app.buttons["Notifications & reminders"].tap()
        let reminder = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Example reminder")).firstMatch
        XCTAssertTrue(reminder.waitForExistence(timeout: 5)); reminder.tap()
        let snooze = app.buttons["snoozeReminder"]
        for _ in 0 ..< 8 where !snooze.isHittable { sheetOrList(app).swipeUp() }
        snooze.tap(); XCTAssertTrue(reminder.waitForExistence(timeout: 5)); reminder.tap()
        capture(app, "Reminder actions after snooze")
        let done = app.buttons["completeReminder"]
        for _ in 0 ..< 8 where !done.isHittable { sheetOrList(app).swipeUp() }
        done.tap(); XCTAssertTrue(app.staticTexts["reminderDoneStatus"].waitForExistence(timeout: 5))
    }

    func testCompactHealthUnitChoices() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-testing"]; app.launch()
        XCTAssertTrue(app.buttons["quickBottle"].waitForExistence(timeout: 15))
        navigate(app, "Health"); navigate(app, "Growth"); app.buttons["Add measurement"].tap()
        XCTAssertTrue(app.buttons["unit-lb"].waitForExistence(timeout: 5))
        let pounds = app.buttons["unit-lb"].frame, ounces = app.buttons["unit-oz"].frame, kilograms = app.buttons["unit-kg"].frame
        XCTAssertEqual(pounds.midY, ounces.midY, accuracy: 1); XCTAssertEqual(pounds.midY, kilograms.midY, accuracy: 1)
        XCTAssertGreaterThanOrEqual(pounds.width, 44)
        capture(app, "Compact measurement units"); app.buttons["Cancel"].tap()
        navigate(app, "Today"); openRecordMenu(app, "temperature")
        XCTAssertTrue(app.buttons["unit-°F"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["unit-°F"].frame.midY, app.buttons["unit-°C"].frame.midY, accuracy: 1)
        capture(app, "Compact temperature units")
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
            openRecordMenu(app, type)
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

    func testDiaperLargeTextScreenshots() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-testing", "-appearance", "dark", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]; app.launch()
        XCTAssertTrue(app.buttons["quickDiaper"].waitForExistence(timeout: 15))
        openLog(app, "quickDiaper")
        let dirty = app.buttons["diaper-Dirty"]
        for _ in 0 ..< 5 where !dirty.isHittable { app.scrollViews.firstMatch.swipeUp() }
        dirty.tap(); XCTAssertTrue(dirty.isSelected)
        capture(app, "Large text diaper selection")
        let mushy = app.buttons["diaper-consistency-Mushy"]
        for _ in 0 ..< 6 where !mushy.isHittable { app.scrollViews.firstMatch.swipeUp() }
        mushy.tap(); XCTAssertTrue(mushy.isSelected)
        capture(app, "Large text diaper textures")
        app.buttons["Cancel"].tap()
    }

    func testLargeTextAuxiliarySheets() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-testing", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]; app.launch()
        XCTAssertTrue(app.buttons["quickBottle"].waitForExistence(timeout: 15))
        openLog(app, "quickBottle")
        let formula = app.buttons["formulaPicker"]
        for _ in 0 ..< 5 where !formula.isHittable { app.scrollViews.firstMatch.swipeUp() }
        formula.tap(); app.buttons["customFormula"].tap()
        XCTAssertTrue(app.textFields["customFormulaName"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.textFields["customFormulaName"].isHittable)
        capture(app, "Large text custom formula"); app.buttons["closeSheet-Custom formula"].tap(); app.buttons["closeSheet-Formula"].tap(); app.buttons["closeSheet-Bottle"].tap()
        if app.buttons["nav-Family"].exists { navigate(app, "Family") } else { navigate(app, "More"); app.buttons["Family"].tap() }
        let profile = app.buttons["Edit caregiver profile"]
        for _ in 0 ..< 6 where !profile.isHittable { sheetOrList(app).swipeUp() }
        profile.tap(); XCTAssertTrue(app.buttons["saveRecord"].waitForExistence(timeout: 5))
        capture(app, "Large text caregiver profile"); app.buttons["Cancel"].tap()
    }

    func testCompactSheetAndCombinedTimeWheel() throws {
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
            if current == 0 { throw XCTSkip("The minute wheel is at an hourly boundary; deterministic date boundaries are covered by Core tests.") }
            minute.adjust(toPickerWheelValue: String(format: "%02d", current - 1))
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
        let button = app.buttons[option]
        XCTAssertTrue(button.waitForExistence(timeout: 5))
        // AX can report a partly visible control as hittable at the tab bar edge.
        for _ in 0 ..< 8 {
            let y = button.frame.midY
            if y > 140 && y < app.frame.height * 0.65 { break }
            let scroll = app.scrollViews.firstMatch
            let start = scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.55))
            let end = scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: y > app.frame.height * 0.65 ? 0.35 : 0.75))
            start.press(forDuration: 0.05, thenDragTo: end)
        }
        button.tap()
        if option == "sleepTimeline" {
            openRecordMenu(app, "sleep")
        }
        XCTAssertTrue(app.buttons["saveRecord"].waitForExistence(timeout: 5))
    }

    private func openRecordMenu(_ app: XCUIApplication, _ type: String) {
        app.buttons["addRecord"].tap()
        XCTAssertTrue(app.buttons["closeSheet-Add record"].waitForExistence(timeout: 5))
        let action = app.buttons["add-\(type)"]
        let list = sheetOrList(app)
        for _ in 0 ..< 14 {
            // Keep the whole row visible rather than overshooting short menu rows.
            if action.exists, action.isHittable, action.frame.maxY <= list.frame.maxY - 8 { break }
            list.swipeUp(velocity: .slow)
        }
        XCTAssertTrue(action.exists); action.tap()
        XCTAssertTrue(app.buttons["saveRecord"].waitForExistence(timeout: 5))
    }

    private func sheetOrList(_ app: XCUIApplication) -> XCUIElement {
        let sheet = app.scrollViews["careSheetScroll"].firstMatch
        return sheet.exists ? sheet : app.collectionViews.firstMatch
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
