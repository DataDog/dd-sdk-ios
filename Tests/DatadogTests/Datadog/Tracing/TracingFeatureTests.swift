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
        temporaryFeatureDirectories.create()
    }

    override func tearDown() {
        XCTAssertNil(Datadog.instance)
        XCTAssertNil(TracingFeature.instance)
        temporaryFeatureDirectories.delete()
        super.tearDown()
    }

    // MARK: - HTTP Message

    func testItUsesExpectedHTTPMessage() throws {
        let server = ServerMock(delivery: .success(response: .mockResponseWith(statusCode: 200)))
        TracingFeature.instance = .mockWith(
            directories: temporaryFeatureDirectories,
            configuration: .mockWith(
                common: .mockWith(
                    applicationName: "FoobarApp",
                    applicationVersion: "2.1.0"
                )
            ),
            dependencies: .mockWith(
                mobileDevice: .mockWith(model: "iPhone", osName: "iOS", osVersion: "13.3.1")
            )
        )
        defer { TracingFeature.instance?.deinitialize() }

        let tracer = Tracer.initialize(configuration: .init()).dd

        let span = tracer.startSpan(operationName: "operation 1")
        span.finish()

        let request = server.waitAndReturnRequests(count: 1)[0]
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertNil(request.url?.query)
        XCTAssertEqual(request.allHTTPHeaderFields?["User-Agent"], "FoobarApp/2.1.0 CFNetwork (iPhone; iOS/13.3.1)")
        XCTAssertEqual(request.allHTTPHeaderFields?["Content-Type"], "text/plain;charset=UTF-8")
    }

    // MARK: - HTTP Payload

    func testItUsesExpectedPayloadFormatForUploads() throws {
        let server = ServerMock(delivery: .success(response: .mockResponseWith(statusCode: 200)))
        TracingFeature.instance = .mockWith(
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
        defer { TracingFeature.instance?.deinitialize() }

        let tracer = Tracer.initialize(configuration: .init()).dd

        tracer.startSpan(operationName: "operation 1").finish()
        tracer.startSpan(operationName: "operation 2").finish()
        tracer.startSpan(operationName: "operation 3").finish()

        let payload = server.waitAndReturnRequests(count: 1)[0].httpBody!

        // Expected payload format:
        // ```
        // span1JSON
        // span2JSON
        // span3JSON
        // ```

        let spanMatchers = try SpanMatcher.fromNewlineSeparatedJSONObjectsData(payload)
        XCTAssertEqual(try spanMatchers[0].operationName(), "operation 1")
        XCTAssertEqual(try spanMatchers[1].operationName(), "operation 2")
        XCTAssertEqual(try spanMatchers[2].operationName(), "operation 3")
    }
}
