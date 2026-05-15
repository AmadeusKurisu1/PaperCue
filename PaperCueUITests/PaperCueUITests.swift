//
//  PaperCueUITests.swift
//  PaperCueUITests
//
//  Created by 孙昊 on 2026/5/11.
//

import XCTest

final class PaperCueUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testLaunchShowsEmptyLibraryAndImportControls() throws {
        let app = makeApp()
        app.launch()

        XCTAssertTrue(app.navigationBars["PaperCue"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["importPDFButton"].exists)
        XCTAssertTrue(app.buttons["importURLButton"].exists)
        XCTAssertTrue(app.buttons["importTextButton"].exists)
        XCTAssertTrue(app.buttons["settingsButton"].exists)
        XCTAssertTrue(app.staticTexts["导入 PDF、网页或文本开始"].exists)
    }

    @MainActor
    func testURLImportSheetValidatesURL() throws {
        let app = makeApp()
        app.launch()

        app.buttons["importURLButton"].tap()

        let textField = app.textFields["urlImportTextField"]
        XCTAssertTrue(textField.waitForExistence(timeout: 5))
        textField.tap()
        textField.typeText("not a url")

        app.buttons["confirmURLImportButton"].tap()

        XCTAssertTrue(app.staticTexts["请输入有效的网页地址。"].waitForExistence(timeout: 2))
    }

    @MainActor
    func testTextImportSheetValidatesEmptyBody() throws {
        let app = makeApp()
        app.launch()

        app.buttons["importTextButton"].tap()

        XCTAssertTrue(app.textFields["textImportTitleField"].waitForExistence(timeout: 5))
        app.buttons["confirmTextImportButton"].tap()

        XCTAssertTrue(app.staticTexts["没有提取到可复制文本。v1 暂不支持扫描件或 OCR。"].waitForExistence(timeout: 2))
    }

    @MainActor
    func testSettingsExposeModelConfiguration() throws {
        let app = makeApp()
        app.launch()

        app.buttons["settingsButton"].tap()

        let providerPickerExists = (
            app.buttons["providerPicker"].waitForExistence(timeout: 5)
            || app.otherElements["providerPicker"].waitForExistence(timeout: 5)
        )
        XCTAssertTrue(providerPickerExists)
        XCTAssertTrue(app.textFields["baseURLTextField"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.secureTextFields["apiKeySecureField"].exists)
        XCTAssertTrue(app.buttons["pasteAPIKeyButton"].exists)
        XCTAssertTrue(app.buttons["modelPicker"].exists || app.otherElements["modelPicker"].exists)
        XCTAssertTrue(app.textFields["modelTextField"].exists)
        XCTAssertTrue(app.buttons["testConnectionButton"].exists)
    }

    @MainActor
    func testSeededDocumentGenerationFailureShowsUserVisibleState() throws {
        let app = makeApp(seedDocument: true)
        app.launch()

        XCTAssertTrue(app.staticTexts["Seeded Paper"].waitForExistence(timeout: 5))

        let generateButton = app.buttons["generateStudyPackButton"]
        XCTAssertTrue(generateButton.waitForExistence(timeout: 5))
        XCTAssertTrue(generateButton.isEnabled)
        XCTAssertTrue(app.segmentedControls["generationProfilePicker"].exists || app.otherElements["generationProfilePicker"].exists)
        generateButton.tap()

        XCTAssertTrue(app.alerts["操作失败"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["请先在设置里填写 API key。"].exists)
        app.alerts["操作失败"].buttons["好"].tap()

        XCTAssertTrue(app.staticTexts["请先在设置里填写 API key。"].waitForExistence(timeout: 3))
    }

    @MainActor
    func testLaunchPerformance() throws {
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            makeApp().launch()
        }
    }

    private func makeApp(seedDocument: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["PAPERCUE_UI_TESTING"] = "1"
        if seedDocument {
            app.launchEnvironment["PAPERCUE_UI_TESTING_SEED_DOCUMENT"] = "1"
        }
        return app
    }
}
