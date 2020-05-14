/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import XCTest
@testable import Datadog

class TracingFeatureTests: XCTestCase {
    override func setUp() {
        super.setUp()
        XCTAssertNil(Datadog.instance)
        XCTAssertNil(TracingFeature.instance)
        temporaryDirectory.create()
    }

    override func tearDown() {
        XCTAssertNil(Datadog.instance)
        XCTAssertNil(TracingFeature.instance)
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

        XCTAssertNotNil(TracingFeature.instance)

        try Datadog.deinitializeOrThrow()
    }

    // MARK: - HTTP Headers

    func testItUsesExpectedHTTPHeaders() throws {
        let server = ServerMock(delivery: .success(response: .mockResponseWith(statusCode: 200)))
        TracingFeature.instance = .mockWorkingFeatureWith(
            server: server,
            directory: temporaryDirectory,
            configuration: .mockWith(
                applicationName: "FoobarApp",
                applicationVersion: "2.1.0"
            ),
            mobileDevice: .mockWith(model: "iPhone", osName: "iOS", osVersion: "13.3.1")
        )
        defer { TracingFeature.instance = nil }

        let tracer = DDTracer.initialize(configuration: .init()).dd

        let span = tracer.startSpan(operationName: "operation 1")
        span.finish()

        let httpHeaders = server.waitAndReturnRequests(count: 1)[0].allHTTPHeaderFields
        XCTAssertEqual(httpHeaders?["User-Agent"], "FoobarApp/2.1.0 CFNetwork (iPhone; iOS/13.3.1)")
        XCTAssertEqual(httpHeaders?["Content-Type"], "text/plain;charset=UTF-8")
    }

    // MARK: - Payload Format

    func testItUsesExpectedPayloadFormatForUploads() throws {
        let server = ServerMock(delivery: .success(response: .mockResponseWith(statusCode: 200)))
        TracingFeature.instance = .mockWorkingFeatureWith(
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
        defer { TracingFeature.instance = nil }

        let tracer = DDTracer.initialize(configuration: .init()).dd

        tracer.startSpan(operationName: "operation 1").finish()
        tracer.startSpan(operationName: "operation 2").finish()
        tracer.startSpan(operationName: "operation 3").finish()

        let payload = server.waitAndReturnRequests(count: 1)[0].httpBody!

        let spanMatchers = try SpanMatcher.fromNewlineSeparatedJSONObjectsData(payload)
        XCTAssertEqual(try spanMatchers[0].operationName(), "operation 1")
        XCTAssertEqual(try spanMatchers[1].operationName(), "operation 2")
        XCTAssertEqual(try spanMatchers[2].operationName(), "operation 3")
    }
}
