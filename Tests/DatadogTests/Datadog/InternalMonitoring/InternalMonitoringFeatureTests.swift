/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import XCTest
@testable import Datadog

class InternalMonitoringFeatureTests: XCTestCase {
    override func setUp() {
        super.setUp()
        XCTAssertNil(Datadog.instance)
        XCTAssertNil(InternalMonitoringFeature.instance)
        temporaryFeatureDirectories.create()
    }

    override func tearDown() {
        XCTAssertNil(Datadog.instance)
        XCTAssertNil(InternalMonitoringFeature.instance)
        temporaryFeatureDirectories.delete()
        super.tearDown()
    }

    // MARK: - HTTP Message

    func testItUsesExpectedHTTPMessage() throws {
        let server = ServerMock(delivery: .success(response: .mockResponseWith(statusCode: 200)))
        InternalMonitoringFeature.instance = .mockWith(
            logDirectories: temporaryFeatureDirectories,
            configuration: .mockWith(
                common: .mockWith(
                    applicationName: "FoobarApp",
                    applicationVersion: "2.1.0",
                    source: "abc"
                )
            ),
            dependencies: .mockWith(
                mobileDevice: .mockWith(model: "iPhone", osName: "iOS", osVersion: "13.3.1")
            )
        )
        defer { InternalMonitoringFeature.instance?.deinitialize() }

        let sdkLogger = try XCTUnwrap(InternalMonitoringFeature.instance?.monitor.sdkLogger)
        sdkLogger.debug("message")

        let request = server.waitAndReturnRequests(count: 1)[0]
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.query, "ddsource=abc")
        XCTAssertEqual(request.allHTTPHeaderFields?["User-Agent"], "FoobarApp/2.1.0 CFNetwork (iPhone; iOS/13.3.1)")
        XCTAssertEqual(request.allHTTPHeaderFields?["Content-Type"], "application/json")
    }

    // MARK: - Sending SDK Logs

    func testItSendsApplicationAndSDKInfoWithLogs() throws {
        InternalMonitoringFeature.instance = .mockByRecordingLogMatchers(
            directories: temporaryFeatureDirectories,
            configuration: .mockWith(
                common: .mockWith(
                    applicationName: "ApplicationName",
                    applicationVersion: "2.0.0",
                    applicationBundleIdentifier: "com.application.bundle.id",
                    serviceName: .mockRandom(),
                    environment: .mockRandom()
                ),
                sdkServiceName: "sdk-service-name",
                sdkEnvironment: "sdk-environment"
            ),
            dependencies: .mockWith(
                dateProvider: RelativeDateProvider(using: .mockDecember15th2019At10AMUTC())
            )
        )
        defer { InternalMonitoringFeature.instance?.deinitialize() }

        let sdkLogger = try XCTUnwrap(InternalMonitoringFeature.instance?.monitor.sdkLogger)
        sdkLogger.error("internal error message")

        let logMatcher = try InternalMonitoringFeature.waitAndReturnLogMatchers(count: 1)[0]

        typealias Attribute = LogMatcher.JSONKey
        logMatcher.assertValue(forKeyPath: Attribute.date, equals: "2019-12-15T10:00:00.000Z")
        logMatcher.assertValue(forKeyPath: Attribute.message, equals: "internal error message")
        logMatcher.assertValue(forKeyPath: Attribute.serviceName, equals: "sdk-service-name")
        logMatcher.assertValue(forKeyPath: Attribute.loggerName, equals: "im-logger")
        logMatcher.assertValue(forKeyPath: Attribute.loggerVersion, equals: sdkVersion)
        logMatcher.assertTags(equal: ["env:sdk-environment"])
        logMatcher.assertValue(forKeyPath: Attribute.applicationVersion, equals: "2.0.0")
        logMatcher.assertValue(forKeyPath: "application.name", equals: "ApplicationName")
        logMatcher.assertValue(forKeyPath: "application.bundle-id", equals: "com.application.bundle.id")
    }
}
