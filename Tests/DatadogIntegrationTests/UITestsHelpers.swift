/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import XCTest

/// Convenient interface to navigate through Example app's main screen.
class ExampleApplication: XCUIApplication {
    /// Launches the app by mocking all feature endpoints with `mockServerURL`.
    func launchWith(mockServerURL: URL) {
        self.launchWith(mockLogsEndpointURL: mockServerURL, mockTracesEndpointURL: mockServerURL)
    }

    /// Launches the app by mocking feature endpoints separately.
    func launchWith(mockLogsEndpointURL: URL, mockTracesEndpointURL: URL) {
        launchArguments = ["IS_RUNNING_UI_TESTS"]
        launchEnvironment = [
            "DD_MOCK_LOGS_ENDPOINT_URL": mockLogsEndpointURL.absoluteString,
            "DD_MOCK_TRACES_ENDPOINT_URL": mockTracesEndpointURL.absoluteString
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
