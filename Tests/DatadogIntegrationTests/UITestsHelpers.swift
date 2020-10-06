/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import XCTest

/// Convenient interface to navigate through Example app's main screen.
class ExampleApplication: XCUIApplication {
    /// Launches the app by providing mock server configuration.
    func launchWith(
        testScenario: TestScenario.Type,
        serverConfiguration: HTTPServerMockConfiguration
    ) {
        launchArguments = [Environment.Argument.isRunningUITests]

        var variables: [String: String] = [:]
        variables[Environment.Variable.testScenarioIdentifier] = testScenario.envIdentifier()
        variables[Environment.Variable.serverMockConfiguration] = serverConfiguration.toEnvironmentValue

        launchEnvironment = variables

        super.launch()
    }
}

extension Array where Element == RUMEventMatcher {
    /// Prints a list of generic `RUMEventMatchers` that should be used to assert elements from this array.
    /// Handy for debugging `[RUMEventMatcher]` with `po rumEventsMatchers`.
    ///
    /// Example output:
    ///
    ///     [0] - RUMEventMatcher<RUMAction>
    ///     [1] - RUMEventMatcher<RUMView>
    ///     [2] - RUMEventMatcher<RUMResource>
    ///     [3] - RUMEventMatcher<RUMView>
    ///     [4] - RUMEventMatcher<RUMAction>
    ///
    func inspect() {
        enumerated().forEach { index, matcher in
            print("[\(index)] - \(getTypeOf(matcher: matcher))")
        }
    }

    private func getTypeOf(matcher: RUMEventMatcher) -> String {
        let allPossibleMatchers: [String: (RUMEventMatcher) -> Bool] = [
            "RUMEventMatcher<RUMView>": { matcher in matcher.model(isTypeOf: RUMView.self) },
            "RUMEventMatcher<RUMAction>": { matcher in matcher.model(isTypeOf: RUMAction.self) },
            "RUMEventMatcher<RUMResource>": { matcher in matcher.model(isTypeOf: RUMResource.self) },
            "RUMEventMatcher<RUMError>": { matcher in matcher.model(isTypeOf: RUMError.self) }
        ]

        let bestMatcherEntry = allPossibleMatchers
            .first { _, matcherPredicate in matcherPredicate(matcher) }

        return bestMatcherEntry?.key ?? "unkonwn / unimplemented"
    }
}

extension String {
    func matches(regex: String) -> Bool {
        range(of: regex, options: .regularExpression, range: nil, locale: nil) != nil
    }
}
