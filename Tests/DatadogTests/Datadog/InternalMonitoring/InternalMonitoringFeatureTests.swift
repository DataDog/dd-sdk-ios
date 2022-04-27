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
        let randomApplicationName: String = .mockRandom(among: .alphanumerics)
        let randomApplicationVersion: String = .mockRandom()
        let randomSource: String = .mockRandom(among: .alphanumerics)
        let randomOrigin: String = .mockRandom(among: .alphanumerics)
        let randomSDKVersion: String = .mockRandom(among: .alphanumerics)
        let randomUploadURL: URL = .mockRandom()
        let randomClientToken: String = .mockRandom()
        let randomDeviceModel: String = .mockRandom()
        let randomDeviceOSName: String = .mockRandom()
        let randomDeviceOSVersion: String = .mockRandom()
        let randomEncryption: DataEncryption? = Bool.random() ? DataEncryptionMock() : nil

        let server = ServerMock(delivery: .success(response: .mockResponseWith(statusCode: 200)))

        // Given
        InternalMonitoringFeature.instance = .mockWith(
            logDirectories: temporaryFeatureDirectories,
            configuration: .mockWith(
                common: .mockWith(
                    applicationName: randomApplicationName,
                    applicationVersion: randomApplicationVersion,
                    source: randomSource,
                    origin: randomOrigin,
                    sdkVersion: randomSDKVersion,
                    encryption: randomEncryption
                ),
                logsUploadURL: randomUploadURL,
                clientToken: randomClientToken
            ),
            dependencies: .mockWith(
                mobileDevice: .mockWith(model: randomDeviceModel, osName: randomDeviceOSName, osVersion: randomDeviceOSVersion)
            )
        )
        defer { InternalMonitoringFeature.instance?.deinitialize() }

        // When
        let sdkLogger = try XCTUnwrap(InternalMonitoringFeature.instance?.monitor.sdkLogger)
        sdkLogger.debug(.mockAny())

        // Then
        let request = server.waitAndReturnRequests(count: 1)[0]
        let requestURL = try XCTUnwrap(request.url)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertTrue(requestURL.absoluteString.starts(with: randomUploadURL.absoluteString + "?"))
        XCTAssertEqual(requestURL.query, "ddsource=\(randomSource)")
        XCTAssertEqual(
            request.allHTTPHeaderFields?["User-Agent"],
            """
            \(randomApplicationName)/\(randomApplicationVersion) CFNetwork (\(randomDeviceModel); \(randomDeviceOSName)/\(randomDeviceOSVersion))
            """
        )
        XCTAssertEqual(request.allHTTPHeaderFields?["Content-Type"], "application/json")
        XCTAssertEqual(request.allHTTPHeaderFields?["Content-Encoding"], "deflate")
        XCTAssertEqual(request.allHTTPHeaderFields?["DD-API-KEY"], randomClientToken)
        XCTAssertEqual(request.allHTTPHeaderFields?["DD-EVP-ORIGIN"], randomOrigin)
        XCTAssertEqual(request.allHTTPHeaderFields?["DD-EVP-ORIGIN-VERSION"], randomSDKVersion)
        XCTAssertEqual(request.allHTTPHeaderFields?["DD-REQUEST-ID"]?.matches(regex: .uuidRegex), true)
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
                    environment: .mockRandom(),
                    sdkVersion: "1.2.3"
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
        logMatcher.assertValue(forKeyPath: Attribute.loggerVersion, equals: "1.2.3")
        logMatcher.assertTags(equal: ["env:sdk-environment"])
        logMatcher.assertValue(forKeyPath: Attribute.applicationVersion, equals: "2.0.0")
        logMatcher.assertValue(forKeyPath: "application.name", equals: "ApplicationName")
        logMatcher.assertValue(forKeyPath: "application.bundle-id", equals: "com.application.bundle.id")
    }
}
