/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import XCTest

/// Convenient interface to navigate through Example app's main screen.
class ExampleApplication: XCUIApplication {
    func launchWith(mockServerURL: URL) {
        launchArguments = ["IS_RUNNING_UI_TESTS"]
        launchEnvironment = [
            "DD_MOCK_SERVER_URL": mockServerURL.absoluteString
        ]
        super.launch()
    }

    func tapSendLogsForUITests() {
        tables.staticTexts["Send logs for UI Tests"].tap()
    }

    func tapSendTracesForUITests() {
        tables.staticTexts["Send traces for UI Tests"].tap()
    }
}
