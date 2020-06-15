/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import XCTest
@testable import Datadog

class LoggingFeatureTests: XCTestCase {
    override func setUp() {
        super.setUp()
        XCTAssertNil(Datadog.instance)
        XCTAssertNil(LoggingFeature.instance)
        temporaryDirectory.create()
    }

    override func tearDown() {
        XCTAssertNil(Datadog.instance)
        XCTAssertNil(LoggingFeature.instance)
        temporaryDirectory.delete()
        super.tearDown()
    }

    // MARK: - Initialization

    func testInitialization() throws {
        let appContext: AppContext = .mockAny()
        Datadog.initialize(
            appContext: appContext,
            configuration: Datadog.Configuration
                .builderUsing(clientToken: "abc", environment: "tests")
                .build()
        )

        XCTAssertNotNil(LoggingFeature.instance)

        try Datadog.deinitializeOrThrow()
    }

    // MARK: - HTTP Headers

    func testItUsesExpectedHTTPHeaders() throws {
        let server = ServerMock(delivery: .success(response: .mockResponseWith(statusCode: 200)))
        LoggingFeature.instance = .mockWorkingFeatureWith(
            server: server,
            directory: temporaryDirectory,
            configuration: .mockWith(
                applicationName: "FoobarApp",
                applicationVersion: "2.1.0"
            ),
            mobileDevice: .mockWith(model: "iPhone", osName: "iOS", osVersion: "13.3.1")
        )
        defer { LoggingFeature.instance = nil }

        let logger = Logger.builder.build()
        logger.debug("message")

        let httpHeaders = server.waitAndReturnRequests(count: 1)[0].allHTTPHeaderFields
        XCTAssertEqual(httpHeaders?["User-Agent"], "FoobarApp/2.1.0 CFNetwork (iPhone; iOS/13.3.1)")
        XCTAssertEqual(httpHeaders?["Content-Type"], "application/json")
    }

    // MARK: - Payload Format

    func testItUsesExpectedPayloadFormatForUploads() throws {
        let server = ServerMock(delivery: .success(response: .mockResponseWith(statusCode: 200)))
        LoggingFeature.instance = .mockWorkingFeatureWith(
            server: server,
            directory: temporaryDirectory,
            performance: .combining(
                storagePerformance: StoragePerformanceMock(
                    maxFileSize: .max,
                    maxDirectorySize: .max,
                    maxFileAgeForWrite: .distantFuture, // write all spans to single file,
                    minFileAgeForRead: StoragePerformanceMock.readAllFiles.minFileAgeForRead,
                    maxFileAgeForRead: StoragePerformanceMock.readAllFiles.maxFileAgeForRead,
                    maxObjectsInFile: 3, // write 3 spans to payload,
                    maxObjectSize: .max
                ),
                uploadPerformance: UploadPerformanceMock(
                    initialUploadDelay: 0.5, // wait enough until spans are written,
                    defaultUploadDelay: 1,
                    minUploadDelay: 1,
                    maxUploadDelay: 1,
                    uploadDelayDecreaseFactor: 1
                )
            )
        )
        defer { LoggingFeature.instance = nil }

        let logger = Logger.builder.build()
        logger.debug("log 1")
        logger.debug("log 2")
        logger.debug("log 3")

        let payload = server.waitAndReturnRequests(count: 1)[0].httpBody!

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
