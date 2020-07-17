/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import HTTPServerMock
import XCTest

// swiftlint:disable trailing_closure
class LoggingIntegrationTests: IntegrationTests {
    private struct Constants {
        /// Time needed for logs to be uploaded to mock server.
        static let logsDeliveryTime: TimeInterval = 30
    }

    func testLaunchTheAppAndSendLogs() throws {
        let serverSession = server.obtainUniqueRecordingSession()

        let app = ExampleApplication()
        app.launchWith(mockServerURL: serverSession.recordingURL)
        app.tapSendLogsForUITests()

        // Return desired count or timeout
        let recordedRequests = try serverSession.pullRecordedPOSTRequests(count: 1, timeout: Constants.logsDeliveryTime)

        recordedRequests.forEach { request in
            // Example path here: `/36882784-420B-494F-910D-CBAC5897A309/ui-tests-client-token?ddsource=ios&batch_time=1589969230153`
            let pathRegexp = #"^(.*)(/ui-tests-client-token\?ddsource=ios&batch_time=)([0-9]+)$"#
            XCTAssertNotNil(request.path.range(of: pathRegexp, options: .regularExpression, range: nil, locale: nil))
            XCTAssertTrue(request.httpHeaders.contains("Content-Type: application/json"))
        }

        // Assert logs
        let logMatchers = try recordedRequests
            .flatMap { request in try LogMatcher.fromArrayOfJSONObjectsData(request.httpBody) }

        XCTAssertEqual(logMatchers.count, 6)

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

        logMatchers.forEach { matcher in
            matcher.assertDate(matches: { Date().timeIntervalSince($0) < Constants.logsDeliveryTime * 2 })
            matcher.assertServiceName(equals: "ui-tests-service-name")
            matcher.assertLoggerName(equals: "logger-name")
            matcher.assertLoggerVersion(matches: { version in version.split(separator: ".").count == 3 })
            matcher.assertApplicationVersion(equals: "1.0")
            matcher.assertThreadName(equals: "main")
            matcher.assertAttributes(
                equal: [
                    "logger-attribute1": "string value",
                    "logger-attribute2": 1_000,
                    "attribute": "value",
                    "some-url": "https://example.com/image.png"
                ]
            )

            #if DEBUG
            matcher.assertTags(equal: ["env:integration", "build_configuration:debug", "tag1:tag-value", "tag2"])
            #else
            matcher.assertTags(equal: ["env:integration", "build_configuration:release", "tag1:tag-value", "tag2"])
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
// swiftlint:enable trailing_closure
