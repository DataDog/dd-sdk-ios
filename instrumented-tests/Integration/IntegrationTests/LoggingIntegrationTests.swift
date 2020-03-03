/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Datadog
import DatadogTestHelpers
import HTTPServerMock
import XCTest

class LoggingIntegrationTests: IntegrationTests {
    // swiftlint:disable trailing_closure
    func testLogsAreUploadedToServer() throws {
        let serverSession = server.obtainUniqueRecordingSession()

        // Initialize SDK
        Datadog.initialize(
            appContext: .init(mainBundle: .main),
            configuration: Datadog.Configuration.builderUsing(clientToken: "client-token")
                .set(logsEndpoint: .custom(url: serverSession.recordingURL.absoluteString))
                .build()
        )

        // Create logger
        let logger = Logger.builder
            .set(serviceName: "service-name")
            .set(loggerName: "logger-name")
            .build()

        // Send logs
        logger.addTag(withKey: "tag1", value: "tag-value")
        logger.add(tag: "tag2")

        logger.addAttribute(forKey: "logger-attribute1", value: "string value")
        logger.addAttribute(forKey: "logger-attribute2", value: 1_000)

        logger.debug("debug message", attributes: ["attribute": "value"])
        logger.info("info message", attributes: ["attribute": "value"])
        logger.notice("notice message", attributes: ["attribute": "value"])
        logger.warn("warn message", attributes: ["attribute": "value"])
        logger.error("error message", attributes: ["attribute": "value"])
        logger.critical("critical message", attributes: ["attribute": "value"])

        // Wait for delivery
        Thread.sleep(forTimeInterval: 30)

        // Assert
        let recordedRequests = try serverSession.getRecordedPOSTRequests()
        recordedRequests.forEach { request in
            XCTAssertTrue(request.path.contains("/client-token?ddsource=mobile"))
        }

        let logMatchers = try recordedRequests
            .flatMap { request in try request.httpBody.toArrayOfJSONObjects() }
            .map { jsonObject in LogMatcher(from: jsonObject) }

        logMatchers[0].assertStatus(equals: "DEBUG")
        logMatchers[0].assertMessage(equals: "debug message")

        logMatchers[1].assertStatus(equals: "INFO")
        logMatchers[1].assertMessage(equals: "info message")

        logMatchers[2].assertStatus(equals: "NOTICE")
        logMatchers[2].assertMessage(equals: "notice message")

        logMatchers[3].assertStatus(equals: "WARN")
        logMatchers[3].assertMessage(equals: "warn message")

        logMatchers[4].assertStatus(equals: "ERROR")
        logMatchers[4].assertMessage(equals: "error message")

        logMatchers[5].assertStatus(equals: "CRITICAL")
        logMatchers[5].assertMessage(equals: "critical message")

        logMatchers.forEach { matcher in
            matcher.assertDate(matches: { $0.isNotOlderThan(seconds: 60) })
            matcher.assertServiceName(equals: "service-name")
            matcher.assertLoggerName(equals: "logger-name")
            matcher.assertLoggerVersion(matches: { version in version.split(separator: ".").count == 3 })
            matcher.assertApplicationVersion(equals: "1.0.0")
            matcher.assertThreadName(equals: "main")
            matcher.assertAttributes(
                equal: [
                    "logger-attribute1": "string value",
                    "logger-attribute2": 1_000,
                    "attribute": "value",
                ]
            )
            matcher.assertTags(equal: ["tag1:tag-value", "tag2"])

            matcher.assertValue(
                forKeyPath: LogMatcher.JSONKey.networkReachability,
                matches: { LogMatcher.allowedNetworkReachabilityValues.contains($0) }
            )
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

            // Carrier info is empty both on macOS and iOS Simulator
            matcher.assertNoValue(forKey: LogMatcher.JSONKey.mobileNetworkCarrierName)
            matcher.assertNoValue(forKey: LogMatcher.JSONKey.mobileNetworkCarrierISOCountryCode)
            matcher.assertNoValue(forKey: LogMatcher.JSONKey.mobileNetworkCarrierRadioTechnology)
            matcher.assertNoValue(forKey: LogMatcher.JSONKey.mobileNetworkCarrierAllowsVoIP)
        }
    }
    // swiftlint:enable trailing_closure
}
