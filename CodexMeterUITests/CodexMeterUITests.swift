//
//  CodexMeterUITests.swift
//  CodexMeterUITests
//
//  Created by Kristof Dewilde on 2026-05-05.
//

import XCTest

final class CodexMeterUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testAppLaunches() throws {
        let app = XCUIApplication()
        app.launchArguments.append("--disable-updater")
        app.launch()

        XCTAssertTrue(app.exists)
    }

    @MainActor
    func testLaunchPerformance() throws {
        let app = XCUIApplication()
        app.launchArguments.append("--disable-updater")
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            app.launch()
        }
    }
}
