import XCTest

@MainActor
final class HeimdallUITests: XCTestCase {
    private func launch() -> XCUIApplication {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--isolated-ui-tests", "--reset-ui-tests"]
        app.launch()
        XCTAssertTrue(app.buttons["Map mode"].waitForExistence(timeout: 20))
        return app
    }

    private func navigate(_ section: String, in app: XCUIApplication) {
        app.buttons["navigation-menu"].tap()
        app.buttons[section].tap()
    }

    private func mode(_ name: String, in app: XCUIApplication) {
        app.buttons["Map mode"].tap()
        app.buttons[name].tap()
    }

    private func capture(_ name: String) {
        Thread.sleep(forTimeInterval: 0.7)
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testPortraitAndLandscapeLayouts() {
        let app = launch()
        defer { XCUIDevice.shared.orientation = .portrait }
        app.buttons["Zoom in"].tap()
        app.buttons["Zoom in"].tap()
        capture("Detailed Gotland portrait")
        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(app.buttons["Zoom in"].waitForExistence(timeout: 5))
        XCTAssertGreaterThan(app.frame.width, app.frame.height)
        for name in ["Map mode", "Layers", "My position", "Zoom in", "Zoom out", "annotate", "navigation-menu"] {
            XCTAssertTrue(app.buttons[name].isHittable, "\(name) must be reachable in landscape")
        }
        app.buttons["RED, Enemy forces"].tap()
        capture("Detailed Gotland landscape")
        mode("Photo", in: app)
        capture("Photo landscape")
        mode("3D", in: app)
        capture("Terrain landscape")
        mode("Vector", in: app)
        app.buttons["annotate"].tap()
        app.buttons["Line"].tap()
        XCTAssertTrue(app.buttons["Use map center"].isHittable)
        XCTAssertTrue(app.buttons["Cancel"].isHittable)
        capture("Drawing landscape")
        XCUIDevice.shared.orientation = .portrait
        app.buttons["Cancel"].tap()
        navigate("7S reports", in: app)
        app.buttons["new-report"].tap()
        XCTAssertTrue(app.textFields["report-stund"].waitForExistence(timeout: 5))
        XCUIDevice.shared.orientation = .landscapeRight
        XCTAssertTrue(app.buttons["save-report"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Cancel"].isHittable)
        capture("Report landscape")
        app.buttons["Cancel"].tap()
        navigate("Media", in: app)
        XCTAssertTrue(app.buttons["Take photo"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Record video"].isHittable)
        capture("Media landscape")
    }

    func testBackgroundRequiresUnlock() {
        let app = launch()
        XCUIDevice.shared.press(.home)
        app.activate()
        XCTAssertTrue(app.buttons["Unlock Heimdall"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["annotate"].exists)
        app.buttons["Unlock Heimdall"].tap()
        XCTAssertTrue(app.buttons["Map mode"].waitForExistence(timeout: 5))
    }

    func testReportCreateReadMarkSentAndDelete() {
        let app = launch()
        navigate("7S reports", in: app)
        app.buttons["new-report"].tap()
        let place = app.textFields["report-stalle"]
        XCTAssertTrue(place.waitForExistence(timeout: 5))
        place.tap()
        place.typeText("UI test observation")
        app.buttons["save-report"].tap()
        app.staticTexts["UI test observation"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["radio-text"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["radio-text"].label.contains("STÄLLE: UI test observation"))
        app.swipeUp()
        app.buttons["mark-sent"].tap()
        XCTAssertTrue(app.staticTexts["Marked sent"].exists)
        app.swipeUp()
        app.buttons["Delete report"].tap()
        app.buttons.matching(identifier: "Delete report").allElementsBoundByIndex.last?.tap()
        XCTAssertTrue(app.staticTexts["Your field notebook"].waitForExistence(timeout: 5))
    }

    func testPointPersistence() {
        let app = launch()
        app.buttons["annotate"].tap()
        app.buttons["Point"].tap()
        app.buttons["Use map center"].tap()
        let name = app.textFields["annotation-name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        name.typeText("UI test point")
        app.buttons["Save"].tap()
        app.terminate()
        app.launchArguments.removeAll { $0 == "--reset-ui-tests" }
        app.launch()
        XCTAssertTrue(app.buttons["Layers"].waitForExistence(timeout: 15))
        capture("Saved point after relaunch")
        app.buttons["Layers"].tap()
        app.staticTexts["UI test point"].firstMatch.tap()
        XCTAssertEqual(app.textFields["annotation-name"].value as? String, "UI test point")
        app.buttons["Delete annotation"].tap()
        app.buttons["Delete"].tap()
    }

    func testTwoRegionsAndCoverageToggle() {
        let app = launch()
        navigate("Device", in: app)
        XCTAssertTrue(app.buttons["archive-gotland"].waitForExistence(timeout: 5))
        app.swipeUp()
        app.buttons["load-stockholm"].tap()
        XCTAssertTrue(app.buttons["Map mode"].waitForExistence(timeout: 20))
        mode("Show Sweden", in: app)
        capture("Two loaded regions")
        app.buttons["Layers"].tap()
        let toggle = app.switches["region-borders"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        let initialValue = toggle.value as? String
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
        let changed = NSPredicate(format: "value != %@", initialValue ?? "1")
        expectation(for: changed, evaluatedWith: toggle)
        waitForExpectations(timeout: 3)
        app.buttons["Done"].tap()
        capture("Region borders hidden")
        app.buttons["Layers"].tap()
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
        app.buttons["Done"].tap()
        navigate("Device", in: app)
        app.swipeUp()
        XCTAssertFalse(app.buttons["load-uppland"].isEnabled)
        XCTAssertTrue(app.buttons["archive-stockholm"].exists)
        capture("Stored regions")
    }

    func testManualPositionAndVoiceDraft() {
        let app = launch()
        navigate("Device", in: app)
        app.buttons["operator-callsign"].tap()
        let callsign = app.textFields["callsign-input"]
        XCTAssertTrue(callsign.waitForExistence(timeout: 5))
        callsign.tap()
        callsign.typeText("TEST 21")
        app.buttons["save-callsign"].tap()
        XCTAssertTrue(app.buttons["operator-callsign"].waitForExistence(timeout: 5))
        capture("Operator callsign settings")
        app.buttons["operator-callsign"].tap()
        XCTAssertTrue(callsign.waitForExistence(timeout: 5))
        XCTAssertEqual(callsign.value as? String, "TEST 21")
        app.buttons["save-callsign"].tap()
        navigate("Map", in: app)
        app.buttons["My position"].tap()
        app.buttons["Set my position on map"].tap()
        app.buttons["set-own-position"].tap()
        app.buttons["My position"].tap()
        XCTAssertTrue(app.buttons["Center on my position"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Enable GPS"].exists)
        app.buttons["Center on my position"].tap()
        capture("Own position portrait")
        XCUIDevice.shared.orientation = .landscapeLeft
        capture("Own position landscape")
        XCUIDevice.shared.orientation = .portrait
        navigate("7S reports", in: app)
        app.buttons["Record voice report"].firstMatch.tap()
        XCTAssertTrue(app.buttons["Start recording"].waitForExistence(timeout: 5))
        let monitor = addUIInterruptionMonitor(withDescription: "Microphone permission") { alert in
            if alert.buttons["Allow"].exists {
                alert.buttons["Allow"].tap()
                return true
            }
            return false
        }
        defer { removeUIInterruptionMonitor(monitor) }
        app.buttons["Start recording"].tap()
        if !app.buttons["Stop & save"].waitForExistence(timeout: 3) {
            app.tap()
            if app.buttons["Start recording"].exists { app.buttons["Start recording"].tap() }
        }
        XCTAssertTrue(app.buttons["Stop & save"].waitForExistence(timeout: 5))
        Thread.sleep(forTimeInterval: 2)
        app.buttons["Stop & save"].tap()
        XCTAssertTrue(app.staticTexts["7S-rapport"].waitForExistence(timeout: 10))
        app.staticTexts["7S-rapport"].firstMatch.tap()
        XCTAssertTrue(app.buttons["Play / pause"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'MANUAL'")).firstMatch.exists)
        capture("Voice report with position")
        app.buttons["Play / pause"].tap()
        app.buttons["Transcribe offline"].tap()
        // Models may be unavailable on the simulator; never fall back to cloud recognition.
        XCTAssertTrue(app.buttons["Edit"].exists)
    }
}
