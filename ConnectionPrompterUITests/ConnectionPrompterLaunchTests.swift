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
        editor.click()
        editor.typeText("第一段内容")
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
        replaceText(in: app.textViews["文稿正文"], with: "第一份正文")

        app.buttons["新建文稿"].firstMatch.click()
        replaceText(in: app.textFields["文稿标题"], with: "Second Script")
        replaceText(in: app.textViews["文稿正文"], with: "第二份正文")

        let firstDocument = app.staticTexts["First Script"].firstMatch
        XCTAssertTrue(firstDocument.waitForExistence(timeout: 3))
        firstDocument.click()

        XCTAssertEqual(app.textFields["文稿标题"].value as? String, "First Script")
        XCTAssertTrue(
            (app.textViews["文稿正文"].value as? String)?.contains("第一份正文") == true
        )
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
