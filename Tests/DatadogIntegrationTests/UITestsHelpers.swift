/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import XCTest

/// Convenient interface to navigate through Example app's main screen.
class ExampleApplication: XCUIApplication {
    /// Launches the app by mocking feature endpoints.
    func launchWith(
        mockLogsEndpointURL: URL,
        mockTracesEndpointURL: URL,
        mockRUMEndpointURL: URL,
        mockSourceEndpointURL: URL
    ) {
        launchArguments = ["IS_RUNNING_UI_TESTS"]
        launchEnvironment = [
            "DD_MOCK_LOGS_ENDPOINT_URL": mockLogsEndpointURL.absoluteString,
            "DD_MOCK_TRACES_ENDPOINT_URL": mockTracesEndpointURL.absoluteString,
            "DD_MOCK_RUM_ENDPOINT_URL": mockRUMEndpointURL.absoluteString,
            "DD_MOCK_SOURCE_ENDPOINT_URL": mockSourceEndpointURL.absoluteString
        ]
        super.launch()
    }

    func tapSendLogsForUITests() {
        tables.staticTexts["Send logs for UI Tests"].tap()
    }

    func tapSendTracesForUITests() {
        tables.staticTexts["Send traces for UI Tests"].tap()
    }

    func tapSendRUMEventsForUITests() -> RUMFixture1Screen {
        tables.staticTexts["Send RUM events for UI Tests"].tap()
        return RUMFixture1Screen()
    }
}

class RUMFixture1Screen: XCUIApplication {
    func tapDownloadResourceButton() {
        buttons["Download Resource"].tap()
    }

    func tapPushNextScreen() -> RUMFixture2Screen {
        _ = buttons["Push Next Screen"].waitForExistence(timeout: 2)
        buttons["Push Next Screen"].tap()
        return RUMFixture2Screen()
    }
}

class RUMFixture2Screen: XCUIApplication {
    func tapPushNextScreen() {
        buttons["Push Next Screen"].tap()
    }
}

extension Array where Element == RUMEventMatcher {
    /// Prints a list of generic `RUMEventMatchers` that should be used to assert elements from this array.
    /// Handy for debugging `[RUMEventMatcher]` with `po rumEventsMatchers`.
    ///
    /// Example output:
    ///
    ///     [0] - RUMEventMatcher<RUMActionEvent>
    ///     [1] - RUMEventMatcher<RUMViewEvent>
    ///     [2] - RUMEventMatcher<RUMResourceEvent>
    ///     [3] - RUMEventMatcher<RUMViewEvent>
    ///     [4] - RUMEventMatcher<RUMActionEvent>
    ///
    func inspect() {
        enumerated().forEach { index, matcher in
            print("[\(index)] - \(getTypeOf(matcher: matcher))")
        }
    }

    private func getTypeOf(matcher: RUMEventMatcher) -> String {
        let allPossibleMatchers: [String: (RUMEventMatcher) -> Bool] = [
            "RUMEventMatcher<RUMViewEvent>": { matcher in matcher.model(isTypeOf: RUMViewEvent.self) },
            "RUMEventMatcher<RUMActionEvent>": { matcher in matcher.model(isTypeOf: RUMActionEvent.self) },
            "RUMEventMatcher<RUMResourceEvent>": { matcher in matcher.model(isTypeOf: RUMResourceEvent.self) },
            "RUMEventMatcher<RUMError>": { matcher in matcher.model(isTypeOf: RUMError.self) }
        ]

        let bestMatcherEntry = allPossibleMatchers
            .first { _, matcherPredicate in matcherPredicate(matcher) }

        return bestMatcherEntry?.key ?? "unkonwn / unimplemented"
    }
}
