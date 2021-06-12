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
        temporaryFeatureDirectories.create()
    }

    override func tearDown() {
        XCTAssertNil(Datadog.instance)
        XCTAssertNil(LoggingFeature.instance)
        temporaryFeatureDirectories.delete()
        super.tearDown()
    }

    // MARK: - HTTP Message

    func testItUsesExpectedHTTPMessage() throws {
        let server = ServerMock(delivery: .success(response: .mockResponseWith(statusCode: 200)))
        LoggingFeature.instance = .mockWith(
            directories: temporaryFeatureDirectories,
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
        defer { LoggingFeature.instance?.deinitialize() }

        let logger = Logger.builder.build()
        logger.debug("message")

        let request = server.waitAndReturnRequests(count: 1)[0]
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.query, "ddsource=abc")
        XCTAssertEqual(request.allHTTPHeaderFields?["User-Agent"], "FoobarApp/2.1.0 CFNetwork (iPhone; iOS/13.3.1)")
        XCTAssertEqual(request.allHTTPHeaderFields?["Content-Type"], "application/json")
    }

    // MARK: - HTTP Payload

    func testItUsesExpectedPayloadFormatForUploads() throws {
        let server = ServerMock(delivery: .success(response: .mockResponseWith(statusCode: 200)))
        LoggingFeature.instance = .mockWith(
            directories: temporaryFeatureDirectories,
            dependencies: .mockWith(
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
                        uploadDelayChangeRate: 0
                    )
                )
            )
        )
        defer { LoggingFeature.instance?.deinitialize() }

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
