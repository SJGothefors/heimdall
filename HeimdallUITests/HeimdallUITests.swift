import XCTest

final class HeimdallUITests: XCTestCase {
    @MainActor
    func testPortraitAndLandscapeLayouts() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        XCUIDevice.shared.orientation = .portrait
        defer { XCUIDevice.shared.orientation = .portrait }
        app.launch()
        XCTAssertTrue(app.buttons["Photo"].waitForExistence(timeout: 15))
        capture("Map portrait", app: app)
        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(app.buttons["Zoom in"].waitForExistence(timeout: 5))
        XCTAssertGreaterThan(app.frame.width, app.frame.height)
        for name in ["Vector", "Photo", "3D", "Layers", "Zoom in", "Zoom out", "Show Sweden", "annotate"] {
            XCTAssertTrue(app.buttons[name].isHittable, "\(name) must be reachable in landscape")
        }
        app.buttons["Show Sweden"].tap()
        capture("Map landscape", app: app)
        app.buttons["Photo"].tap()
        capture("Photo landscape", app: app)
        app.buttons["3D"].tap()
        capture("Terrain landscape", app: app)
        app.buttons["Vector"].tap()
        app.buttons["annotate"].tap()
        app.buttons["Line"].tap()
        XCTAssertTrue(app.buttons["Use map center"].isHittable)
        XCTAssertTrue(app.buttons["Cancel"].isHittable)
        capture("Drawing landscape", app: app)
        XCUIDevice.shared.orientation = .portrait
        XCTAssertTrue(app.buttons["Use map center"].waitForExistence(timeout: 5))
        app.buttons["Cancel"].tap()
        app.buttons["7S reports"].tap()
        app.buttons["new-report"].tap()
        XCTAssertTrue(app.textFields["report-stund"].waitForExistence(timeout: 5))
        XCUIDevice.shared.orientation = .landscapeRight
        XCTAssertTrue(app.buttons["save-report"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Cancel"].isHittable)
        capture("Report landscape", app: app)
        XCUIDevice.shared.orientation = .portrait
        XCTAssertTrue(app.buttons["Cancel"].waitForExistence(timeout: 5))
        app.buttons["Cancel"].tap()
        app.buttons["Media"].tap()
        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(app.buttons["Take photo"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Record video"].isHittable)
        capture("Media landscape", app: app)
    }

    @MainActor private func capture(_ name: String, app: XCUIApplication) {
        // Let native button highlights and rotation transitions finish before QA.
        Thread.sleep(forTimeInterval: 0.7)
        // Capture the screen, not an app-window crop: the latter can use stale
        // coordinates after rotation when the app owns a separate privacy window.
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    func testBackgroundRequiresUnlock() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launch()
        XCTAssertTrue(app.buttons["Photo"].waitForExistence(timeout: 15))
        XCUIDevice.shared.press(.home)
        app.activate()
        XCTAssertTrue(app.buttons["Unlock Heimdall"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["annotate"].exists)
        app.buttons["Unlock Heimdall"].tap()
        XCTAssertTrue(app.buttons["Photo"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testReportCreateReadMarkSentAndDelete() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launch()
        XCTAssertTrue(app.buttons["7S reports"].waitForExistence(timeout: 15))
        app.buttons["7S reports"].tap()
        app.buttons["new-report"].tap()
        let place = app.textFields["report-stalle"]
        let placeView = app.textViews["report-stalle"]
        let target = place.exists ? place : placeView
        XCTAssertTrue(target.waitForExistence(timeout: 5))
        target.tap()
        target.typeText("UI test observation")
        app.buttons["save-report"].tap()
        app.staticTexts["UI test observation"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["radio-text"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["radio-text"].label.contains("STÄLLE: UI test observation"))
        app.buttons["mark-sent"].tap()
        XCTAssertTrue(app.staticTexts["Marked sent"].exists)
        app.swipeUp()
        app.buttons["Delete report"].tap()
        app.buttons.matching(identifier: "Delete report").allElementsBoundByIndex.last?.tap()
        XCTAssertTrue(app.staticTexts["Your field notebook"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testMapModesAndPointPersistence() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launch()
        XCTAssertTrue(app.buttons["Photo"].waitForExistence(timeout: 15))
        app.buttons["Photo"].tap()
        app.buttons["3D"].tap()
        XCTAssertTrue(app.staticTexts["Drag to orbit · pinch to zoom · relief ×12"].exists)
        app.buttons["Vector"].tap()
        app.buttons["annotate"].tap()
        app.buttons["Point"].tap()
        app.buttons["Use map center"].tap()
        let name = app.textFields["annotation-name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap(); name.typeText("UI test point")
        app.buttons["Save"].tap()
        app.terminate(); app.launch()
        XCTAssertTrue(app.buttons["Layers"].waitForExistence(timeout: 10))
        app.buttons["Layers"].tap()
        app.staticTexts["UI test point"].firstMatch.tap()
        XCTAssertTrue(app.textFields["annotation-name"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.textFields["annotation-name"].value as? String, "UI test point")
        app.buttons["Delete annotation"].tap()
        app.buttons["Delete"].tap()
    }
}
