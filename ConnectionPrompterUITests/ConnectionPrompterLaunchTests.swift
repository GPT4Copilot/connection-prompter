import XCTest

@MainActor
final class ConnectionPrompterLaunchTests: XCTestCase {
    func testLaunchesIntoDocumentLibraryEditor() {
        let app = makeApp()
        app.launch()
        app.activate()

        XCTAssertTrue(app.descendants(matching: .any)["文稿列表"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["新建文稿"].exists)
        XCTAssertTrue(app.textFields["文稿标题"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["进入主持"].exists)
        XCTAssertTrue(app.textViews["文稿正文"].exists)
        attachScreenshot(of: app.windows.firstMatch, named: "editor")
    }

    func testCueMenuInsertsReadableCueIntoEditor() {
        let app = makeApp()
        app.launch()
        app.activate()

        app.menuButtons["插入提示"].click()
        app.menuItems["看镜头"].click()

        let editor = app.textViews["文稿正文"]
        XCTAssertTrue(editor.waitForExistence(timeout: 2))
        XCTAssertTrue((editor.value as? String)?.contains("👁 看镜头") == true)
    }

    func testPresenterOpensAndShowsCurrentScript() {
        let app = makeApp()
        app.launch()
        app.activate()
        let editor = app.textViews["文稿正文"]
        editor.click()
        editor.typeText("我们为什么来到这里？")

        app.buttons["进入主持"].click()

        let presenter = app.dialogs["主持浮窗"]
        XCTAssertTrue(presenter.waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["我们为什么来到这里？"].exists)
        XCTAssertLessThan(presenter.frame.minY, 120)
        attachScreenshot(of: presenter, named: "presenter")
    }

    func testEmptyPresenterAndDisplaySettings() {
        let app = makeApp()
        app.launch()
        app.activate()

        app.buttons["显示设置"].click()
        XCTAssertTrue(app.staticTexts["主持显示"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.sliders["字号"].exists)
        XCTAssertTrue(app.sliders["每页行数"].exists)
        XCTAssertTrue(app.sliders["背景透明度"].exists)
        XCTAssertTrue(app.sliders["自动滚动速度"].exists)
        app.typeKey(.escape, modifierFlags: [])

        app.buttons["进入主持"].click()
        XCTAssertTrue(app.dialogs["主持浮窗"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["文稿还是空的"].exists)
    }

    func testRestoresLastSavedSession() {
        let app = makeApp()
        app.launch()
        app.activate()

        let title = app.textFields["文稿标题"]
        title.click()
        title.typeKey("a", modifierFlags: .command)
        title.typeText("季度分享")

        let editor = app.textViews["文稿正文"]
        replaceText(in: editor, with: "第一段内容")
        Thread.sleep(forTimeInterval: 0.6)
        app.terminate()

        app.launch()
        XCTAssertEqual(app.textFields["文稿标题"].value as? String, "季度分享")
        XCTAssertTrue((app.textViews["文稿正文"].value as? String)?.contains("第一段内容") == true)
    }

    func testCreatesAndSwitchesBetweenSavedDocuments() {
        let app = makeApp()
        app.launch()
        app.activate()

        replaceText(in: app.textFields["文稿标题"], with: "First Script")

        app.buttons["新建文稿"].firstMatch.click()
        replaceText(in: app.textFields["文稿标题"], with: "Second Script")

        let firstDocument = app.staticTexts["First Script"].firstMatch
        XCTAssertTrue(firstDocument.waitForExistence(timeout: 3))
        firstDocument.click()

        XCTAssertEqual(app.textFields["文稿标题"].value as? String, "First Script")
    }

    func testPresenterSupportsFullTransparency() {
        let app = makeApp()
        app.launch()
        app.activate()

        replaceText(in: app.textViews["文稿正文"], with: "完全透明时文字仍然清楚")
        app.buttons["显示设置"].click()

        let transparency = app.sliders["背景透明度"]
        XCTAssertTrue(transparency.waitForExistence(timeout: 2))
        transparency.adjust(toNormalizedSliderPosition: 1)
        app.typeKey(.escape, modifierFlags: [])

        app.buttons["进入主持"].click()
        XCTAssertTrue(app.dialogs["主持浮窗"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["完全透明时文字仍然清楚"].exists)
        attachScreenScreenshot(named: "fully-transparent-presenter")
    }

    func testPresenterCanStartAndPauseAutomaticScrolling() {
        let app = makeApp()
        app.launch()
        app.activate()

        replaceText(
            in: app.textViews["文稿正文"],
            with: (1...12).map { "自动滚动第\($0)行" }.joined(separator: "\n")
        )
        app.buttons["进入主持"].click()

        let presenter = app.dialogs["主持浮窗"]
        XCTAssertTrue(presenter.waitForExistence(timeout: 3))
        presenter.hover()

        let start = app.buttons["开始自动滚动"]
        XCTAssertTrue(start.waitForExistence(timeout: 2))
        start.click()

        let pause = app.buttons["暂停自动滚动"]
        XCTAssertTrue(pause.waitForExistence(timeout: 2))
        pause.click()
        XCTAssertTrue(app.buttons["开始自动滚动"].waitForExistence(timeout: 2))
    }

    func testPresenterProvidesDraggableAutoScrollSpeedControl() {
        let app = makeApp()
        app.launch()
        app.activate()

        replaceText(in: app.textViews["文稿正文"], with: "速度拖拽测试")
        app.buttons["进入主持"].click()

        let presenter = app.dialogs["主持浮窗"]
        XCTAssertTrue(presenter.waitForExistence(timeout: 3))
        presenter.hover()

        let speedSlider = presenter.sliders["主持滚动速度"]
        let speedValue = presenter.staticTexts["主持滚动速度数值"]
        XCTAssertTrue(speedSlider.waitForExistence(timeout: 2))
        XCTAssertEqual(speedValue.value as? String, "0.5")

        let originalFrame = presenter.frame
        let dragStart = speedSlider.coordinate(
            withNormalizedOffset: CGVector(dx: 0.25, dy: 0.5)
        )
        let dragEnd = speedSlider.coordinate(
            withNormalizedOffset: CGVector(dx: 0.75, dy: 0.5)
        )

        dragStart.press(forDuration: 0.1, thenDragTo: dragEnd)

        let updatedValue = NSPredicate(format: "value != %@", "0.5")
        expectation(for: updatedValue, evaluatedWith: speedValue)
        waitForExpectations(timeout: 2)
        XCTAssertGreaterThan(Double(speedValue.value as? String ?? "") ?? 0, 0.5)
        XCTAssertEqual(presenter.frame.minX, originalFrame.minX, accuracy: 1)
        XCTAssertEqual(presenter.frame.minY, originalFrame.minY, accuracy: 1)
        attachScreenshot(of: presenter, named: "presenter-speed-control")

        let peopleViewButton = presenter.buttons["People View"]
        XCTAssertTrue(peopleViewButton.waitForExistence(timeout: 2))
        peopleViewButton.click()
        XCTAssertEqual(presenter.frame.width, 520, accuracy: 2)
        presenter.hover()
        XCTAssertTrue(presenter.sliders["主持滚动速度"].waitForExistence(timeout: 2))
        attachScreenshot(of: presenter, named: "presenter-speed-control-people-view")

        let frameBeforeBackgroundDrag = presenter.frame
        let backgroundStart = presenter.coordinate(
            withNormalizedOffset: CGVector(dx: 0.90, dy: 0.82)
        )
        let backgroundEnd = presenter.coordinate(
            withNormalizedOffset: CGVector(dx: 0.80, dy: 0.82)
        )

        backgroundStart.press(forDuration: 0.1, thenDragTo: backgroundEnd)

        XCTAssertGreaterThan(
            abs(presenter.frame.minX - frameBeforeBackgroundDrag.minX),
            5
        )
    }

    func testPresenterArrowKeysAdjustSpeedAndNavigateText() {
        let app = makeApp()
        app.launch()
        app.activate()

        replaceText(
            in: app.textViews["文稿正文"],
            with: (1...6).map { "方向\($0)" }.joined(separator: "\n")
        )
        app.buttons["进入主持"].click()

        let presenter = app.dialogs["主持浮窗"]
        XCTAssertTrue(presenter.waitForExistence(timeout: 3))
        presenter.hover()

        let speedValue = presenter.staticTexts["主持滚动速度数值"]
        XCTAssertEqual(speedValue.value as? String, "0.5")

        app.typeKey(.rightArrow, modifierFlags: [])
        let increased = NSPredicate(format: "value == %@", "0.6")
        expectation(for: increased, evaluatedWith: speedValue)
        waitForExpectations(timeout: 2)

        app.typeKey(.leftArrow, modifierFlags: [])
        let restoredSpeed = NSPredicate(format: "value == %@", "0.5")
        expectation(for: restoredSpeed, evaluatedWith: speedValue)
        waitForExpectations(timeout: 2)

        let firstLine = presenter.staticTexts["方向1"]
        XCTAssertTrue(firstLine.waitForExistence(timeout: 2))
        let originalY = firstLine.frame.minY

        app.typeKey(.downArrow, modifierFlags: [])
        let movedUp = NSPredicate { _, _ in firstLine.frame.minY < originalY - 1 }
        expectation(for: movedUp, evaluatedWith: firstLine)
        waitForExpectations(timeout: 2)

        app.typeKey(.upArrow, modifierFlags: [])
        let returned = NSPredicate { _, _ in
            abs(firstLine.frame.minY - originalY) <= 2
        }
        expectation(for: returned, evaluatedWith: firstLine)
        waitForExpectations(timeout: 2)
    }

    private func makeApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing"]
        app.launchEnvironment["CONNECTION_PROMPTER_UI_TESTING"] = "1"
        app.launchEnvironment["CONNECTION_PROMPTER_UI_TEST_SESSION"] = UUID().uuidString
        return app
    }

    private func attachScreenshot(of element: XCUIElement, named name: String) {
        let attachment = XCTAttachment(screenshot: element.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func attachScreenScreenshot(named name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func replaceText(in element: XCUIElement, with text: String) {
        XCTAssertTrue(element.waitForExistence(timeout: 3))
        if element.elementType == .textView {
            element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.2)).click()
        } else {
            element.click()
        }
        element.typeKey("a", modifierFlags: .command)
        element.typeText(text)
    }
}
