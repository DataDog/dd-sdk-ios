/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest

// https://semver.org/#is-there-a-suggested-regular-expression-regex-to-check-a-semver-string
let semverPattern = #"(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)(?:-((?:0|[1-9]\d*|\d*[a-zA-Z-][0-9a-zA-Z-]*)(?:\.(?:0|[1-9]\d*|\d*[a-zA-Z-][0-9a-zA-Z-]*))*))?(?:\+([0-9a-zA-Z-]+(?:\.[0-9a-zA-Z-]+)*))?"#
let semverRegex = "^\(semverPattern)$"

/// Regex for matching the value of UA header, e.g.: "User-Agent: Example/1.0 CFNetwork (iPhone; iOS/14.5)"
let userAgentRegex = #"^.*/\d+[.\d]* CFNetwork \([a-zA-Z ]+; iOS/[0-9.]+\)$"#
/// Regex for matching the value of `DD-REQUEST-ID` header, e.g. "DD-REQUEST-ID: 524A2616-D2AA-4FE5-BBD9-898D173BE658"
let ddRequestIDRegex = #"^[0-9A-F]{8}(-[0-9A-F]{4}){3}-[0-9A-F]{12}$"#

/// Convenient interface to navigate through Example app's main screen.
class ExampleApplication: XCUIApplication {
    /// Launches the app by providing mock server configuration.
    /// If `clearPersistentData` is set `true`, the app will clear all SDK data persisted in previous session(s).
    func launchWith(
        testScenarioClassName: String,
        serverConfiguration: HTTPServerMockConfiguration,
        urlSessionSetup: URLSessionSetup? = nil,
        clearPersistentData: Bool = true
    ) {
        if clearPersistentData {
            launchArguments = [
                Environment.Argument.isRunningUITests
            ]
        } else {
            launchArguments = [
                Environment.Argument.isRunningUITests,
                Environment.Argument.doNotClearPersistentData
            ]
        }

        var variables: [String: String] = [:]
        variables[Environment.Variable.testScenarioClassName] = testScenarioClassName
        variables[Environment.Variable.serverMockConfiguration] = serverConfiguration.toEnvironmentValue
        if let urlSessionSetup = urlSessionSetup {
            variables[Environment.Variable.urlSessionSetup] = urlSessionSetup.toEnvironmentValue
        }

        launchEnvironment = variables

        super.launch()
    }

    /// Sends a message to `Example` app under test to start and stop the "end view" in current RUM session.
    /// Presence of this view can be used to await end of transmitting RUM session to the mock server.
    func endRUMSession() throws {
        Thread.sleep(forTimeInterval: 2) // wait a bit so the app under test can complete its animations and transitions
        try MessagePortChannel.createSender().send(message: .endRUMSession)
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
            "RUMEventMatcher<RUMErrorEvent>": { matcher in matcher.model(isTypeOf: RUMErrorEvent.self) }
        ]

        let bestMatcherEntry = allPossibleMatchers
            .first { _, matcherPredicate in matcherPredicate(matcher) }

        return bestMatcherEntry?.key ?? "unknown / unimplemented"
    }
}

extension String {
    func matches(regex: String) -> Bool {
        let match = range(of: regex, options: .regularExpression, range: nil, locale: nil) != nil

        if !match {
            print("'\(self)' does not match '\(regex)'")
        }

        return match
    }
}

struct Exception: Error, CustomStringConvertible {
    let description: String
}

extension XCUIElement {
    func safeTap(within timeout: TimeInterval = 0) {
        if waitForExistence(timeout: timeout) && isHittable {
            tap()
        }
    }
}

/// Prints given value to `STDOUT`, which is captured by CI App instrumentation.
/// This is an oportunity to associate additional logs to UI test execution.
func sendCIAppLog(_ value: CustomStringConvertible) {
    print(value)
}
