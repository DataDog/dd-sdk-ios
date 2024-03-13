/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import HTTPServerMock
import XCTest

class LoggingScenarioTests: IntegrationTests, LoggingCommonAsserts {
    func testLoggingScenario() throws {
        let loggingServerSession = server.obtainUniqueRecordingSession()

        let app = ExampleApplication()
        app.launchWith(
            testScenarioClassName: "LoggingManualInstrumentationScenario",
            serverConfiguration: HTTPServerMockConfiguration(
                logsEndpoint: loggingServerSession.recordingURL
            )
        )

        // Get expected number of `LogMatchers`
        let recordedRequests = try loggingServerSession.pullRecordedRequests(timeout: dataDeliveryTimeout) { requests in
            try LogMatcher.from(requests: requests).count >= 8
        }
        let logMatchers = try LogMatcher.from(requests: recordedRequests)

        // Assert common things
        assertLogging(requests: recordedRequests)

        logMatchers[0].assertStatus(equals: "debug")
        logMatchers[0].assertMessage(equals: "debug message")

        logMatchers[1].assertStatus(equals: "info")
        logMatchers[1].assertMessage(equals: "info message")

        logMatchers[2].assertStatus(equals: "notice")
        logMatchers[2].assertMessage(equals: "notice message")

        logMatchers[3].assertStatus(equals: "warn")
        logMatchers[3].assertMessage(equals: "warn message")

        logMatchers[4].assertStatus(equals: "error")
        logMatchers[4].assertMessage(equals: "error message")

        logMatchers[5].assertStatus(equals: "critical")
        logMatchers[5].assertMessage(equals: "critical message")

        logMatchers[6].assertStatus(equals: "notice")
        logMatchers[6].assertMessage(equals: "notice message with global")
        logMatchers[6].assertAttributes(equal: [
            "global-attribute-1": "global value",
            "global-attribute-2": 1540
            // Don't check "attribute" because local attributes should override
        ])

        logMatchers[7].assertStatus(equals: "error")
        logMatchers[7].assertMessage(equals: "error with fingerprint")
        logMatchers[7].assertAttributes(equal: [
            "error.message": "Runner.SendLogsFixtureViewController.MockError",
            "error.fingerprint": "custom_fingerprint",
        ])


        logMatchers.forEach { matcher in
            matcher.assertDate(matches: { Date().timeIntervalSince($0) < dataDeliveryTimeout * 2 })
            matcher.assertService(equals: "ui-tests-service-name")
            matcher.assertLoggerName(equals: "logger-name")
            matcher.assertLoggerVersion(matches: { $0.matches(regex: semverRegex)})
            matcher.assertApplicationVersion(equals: "1.0")
            matcher.assertThreadName(equals: "main")
            matcher.assertAttributes(
                equal: [
                    "logger-attribute1": "string value",
                    "logger-attribute2": 1_000,
                    "attribute": "value",
                    "some-url": "redacted",
                ]
            )
            matcher.assertHasArchitecture()

            #if DEBUG
            matcher.assertTags(equal: ["env:integration", "build_configuration:debug", "tag1:tag-value", "tag2", "tag3:added", "version:1.0"])
            #else
            matcher.assertTags(equal: ["env:integration", "build_configuration:release", "tag1:tag-value", "tag2", "tag3:added", "version:1.0"])
            #endif

            matcher.assertValue(
                forKeyPath: LogMatcher.JSONKey.networkReachability,
                matches: { LogMatcher.allowedNetworkReachabilityValues.contains($0) }
            )

            if #available(iOS 12.0, *) {
                matcher.assertValue(
                    forKeyPath: LogMatcher.JSONKey.networkAvailableInterfaces,
                    matches: { (values: [String]) -> Bool in
                        LogMatcher.allowedNetworkAvailableInterfacesValues.isSuperset(of: Set(values))
                    }
                )

                matcher.assertValue(forKeyPath: LogMatcher.JSONKey.networkConnectionSupportsIPv4, isTypeOf: Bool.self)
                matcher.assertValue(forKeyPath: LogMatcher.JSONKey.networkConnectionSupportsIPv6, isTypeOf: Bool.self)
                matcher.assertValue(forKeyPath: LogMatcher.JSONKey.networkConnectionIsExpensive, isTypeOf: Bool.self)

                matcher.assertValue(
                    forKeyPath: LogMatcher.JSONKey.networkConnectionIsConstrained,
                    isTypeOf: Optional<Bool>.self
                )
            }

            #if targetEnvironment(simulator)
                // When running on iOS Simulator
                matcher.assertNoValue(forKey: LogMatcher.JSONKey.mobileNetworkCarrierName)
                matcher.assertNoValue(forKey: LogMatcher.JSONKey.mobileNetworkCarrierISOCountryCode)
                matcher.assertNoValue(forKey: LogMatcher.JSONKey.mobileNetworkCarrierRadioTechnology)
                matcher.assertNoValue(forKey: LogMatcher.JSONKey.mobileNetworkCarrierAllowsVoIP)
            #else
                // When running on physical device with SIM card registered
                matcher.assertValue(forKeyPath: LogMatcher.JSONKey.mobileNetworkCarrierName, isTypeOf: String.self)
                matcher.assertValue(forKeyPath: LogMatcher.JSONKey.mobileNetworkCarrierISOCountryCode, isTypeOf: String.self)
                matcher.assertValue(forKeyPath: LogMatcher.JSONKey.mobileNetworkCarrierRadioTechnology, isTypeOf: String.self)
                matcher.assertValue(forKeyPath: LogMatcher.JSONKey.mobileNetworkCarrierAllowsVoIP, isTypeOf: Bool.self)
            #endif
        }
    }
}
