/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import TestUtilities
import DatadogInternal

@testable import DatadogLogs
@testable import Datadog

class DatadogLogsFeatureTests: XCTestCase {
    override func setUp() {
        super.setUp()
        temporaryCoreDirectory.create()
    }

    override func tearDown() {
        temporaryCoreDirectory.delete()
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
        let randomDeviceName: String = .mockRandom()
        let randomDeviceOSName: String = .mockRandom()
        let randomDeviceOSVersion: String = .mockRandom()
        let randomEncryption: DataEncryption? = Bool.random() ? DataEncryptionMock() : nil

        let server = ServerMock(delivery: .success(response: .mockResponseWith(statusCode: 200)))
        let httpClient = HTTPClient(session: server.getInterceptedURLSession())

        let core = DatadogCore(
            directory: temporaryCoreDirectory,
            dateProvider: SystemDateProvider(),
            initialConsent: .granted,
            performance: .combining(
                storagePerformance: .writeEachObjectToNewFileAndReadAllFiles,
                uploadPerformance: .veryQuick
            ),
            httpClient: httpClient,
            encryption: randomEncryption,
            contextProvider: .mockWith(
                context: .mockWith(
                    clientToken: randomClientToken,
                    version: randomApplicationVersion,
                    source: randomSource,
                    sdkVersion: randomSDKVersion,
                    ciAppOrigin: randomOrigin,
                    applicationName: randomApplicationName,
                    device: .mockWith(
                        name: randomDeviceName,
                        osName: randomDeviceOSName,
                        osVersion: randomDeviceOSVersion
                    )
                )
            ),
            applicationVersion: randomApplicationVersion
        )
        defer { core.flushAndTearDown() }

        // Given
        let feature = LogsFeature(
            logEventMapper: nil,
            dateProvider: SystemDateProvider(),
            applicationBundleIdentifier: randomApplicationName,
            remoteLoggingSampler: .mockKeepAll(),
            customIntakeURL: randomUploadURL
        )
        try core.register(feature: feature)

        // When
        let logger = DatadogLogger.builder.build(in: core)
        logger.debug(.mockAny())

        // Then
        let request = server.waitAndReturnRequests(count: 1)[0]
        let requestURL = try XCTUnwrap(request.url)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertTrue(requestURL.absoluteString.starts(with: randomUploadURL.absoluteString + "?"))
        XCTAssertEqual(requestURL.query, "ddsource=\(randomSource)")
        XCTAssertEqual(
            request.allHTTPHeaderFields?["User-Agent"],
            """
            \(randomApplicationName)/\(randomApplicationVersion) CFNetwork (\(randomDeviceName); \(randomDeviceOSName)/\(randomDeviceOSVersion))
            """
        )
        XCTAssertEqual(request.allHTTPHeaderFields?["Content-Type"], "application/json")
        XCTAssertEqual(request.allHTTPHeaderFields?["Content-Encoding"], "deflate")
        XCTAssertEqual(request.allHTTPHeaderFields?["DD-API-KEY"], randomClientToken)
        XCTAssertEqual(request.allHTTPHeaderFields?["DD-EVP-ORIGIN"], randomOrigin)
        XCTAssertEqual(request.allHTTPHeaderFields?["DD-EVP-ORIGIN-VERSION"], randomSDKVersion)
        XCTAssertEqual(request.allHTTPHeaderFields?["DD-REQUEST-ID"]?.matches(regex: .uuidRegex), true)
    }

    // MARK: - HTTP Payload

    func testItUsesExpectedPayloadFormatForUploads() throws {
        let server = ServerMock(delivery: .success(response: .mockResponseWith(statusCode: 200)))
        let httpClient = HTTPClient(session: server.getInterceptedURLSession())

        let core = DatadogCore(
            directory: temporaryCoreDirectory,
            dateProvider: SystemDateProvider(),
            initialConsent: .granted,
            performance: .combining(
                storagePerformance: StoragePerformanceMock(
                    maxFileSize: .max,
                    maxDirectorySize: .max,
                    maxFileAgeForWrite: .distantFuture, // write all events to single file,
                    minFileAgeForRead: StoragePerformanceMock.readAllFiles.minFileAgeForRead,
                    maxFileAgeForRead: StoragePerformanceMock.readAllFiles.maxFileAgeForRead,
                    maxObjectsInFile: 3, // write 3 spans to payload,
                    maxObjectSize: .max
                ),
                uploadPerformance: UploadPerformanceMock(
                    initialUploadDelay: 0.5, // wait enough until events are written,
                    minUploadDelay: 1,
                    maxUploadDelay: 1,
                    uploadDelayChangeRate: 0
                )
            ),
            httpClient: httpClient,
            encryption: nil,
            contextProvider: .mockAny(),
            applicationVersion: .mockAny()
        )
        defer { core.flushAndTearDown() }

        // Given
        let feature = LogsFeature(
            logEventMapper: nil,
            dateProvider: SystemDateProvider(),
            applicationBundleIdentifier: .mockAny(),
            remoteLoggingSampler: .mockKeepAll(),
            customIntakeURL: .mockAny()
        )
        try core.register(feature: feature)

        let logger = DatadogLogger.builder.build(in: core)
        logger.debug("log 1")
        logger.debug("log 2")
        logger.debug("log 3")

        let payload = try XCTUnwrap(server.waitAndReturnRequests(count: 1)[0].httpBody)

        // Expected payload format:
        // `[log1JSON,log2JSON,log3JSON]`

        XCTAssertEqual(payload.prefix(1).utf8String, "[", "payload should start with JSON array trait: `[`")
        XCTAssertEqual(payload.suffix(1).utf8String, "]", "payload should end with JSON array trait: `]`")

        // Expect payload to be an array of log JSON objects
        let logMatchers = try LogMatcher.fromArrayOfJSONObjectsData(payload)
        logMatchers[0].assertMessage(equals: "log 1")
        logMatchers[1].assertMessage(equals: "log 2")
        logMatchers[2].assertMessage(equals: "log 3")
    }
}
