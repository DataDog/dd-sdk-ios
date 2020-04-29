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
                .builderUsing(clientToken: "abc")
                .build()
        )

        XCTAssertNotNil(TracingFeature.instance)

        try Datadog.deinitializeOrThrow()
    }

    // MARK: - HTTP Headers

    func testItUsesExpectedHTTPHeadersForMobileDevice() throws {
        let server = ServerMock(delivery: .success(response: .mockResponseWith(statusCode: 200)))
        TracingFeature.instance = .mockWorkingFeatureWith(
            server: server,
            directory: temporaryDirectory,
            appContext: .mockWith(
                bundleVersion: "2.1.0",
                executableName: "FoobarApp",
                mobileDevice: .mockWith(model: "iPhone", osName: "iOS", osVersion: "13.3.1")
            )
        )
        defer { TracingFeature.instance = nil }

        let tracer = DDTracer(tracingFeature: TracingFeature.instance!)

        let span = tracer.startSpan(operationName: "operation 1")
        span.finish()

        let httpHeaders = server.waitAndReturnRequests(count: 1)[0].allHTTPHeaderFields
        XCTAssertEqual(httpHeaders?["User-Agent"], "FoobarApp/2.1.0 CFNetwork (iPhone; iOS/13.3.1)")
        XCTAssertEqual(httpHeaders?["Content-Type"], "text/plain;charset=UTF-8")
    }

    func testItUsesExpectedHTTPHeadersForOtherDevices() throws {
        let server = ServerMock(delivery: .success(response: .mockResponseWith(statusCode: 200)))
        TracingFeature.instance = .mockWorkingFeatureWith(
            server: server,
            directory: temporaryDirectory,
            appContext: .mockWith(
                bundleVersion: "2.1.0",
                executableName: "FoobarApp",
                mobileDevice: nil
            )
        )
        defer { TracingFeature.instance = nil }

        let tracer = DDTracer(tracingFeature: TracingFeature.instance!)

        let span = tracer.startSpan(operationName: "operation 1")
        span.finish()

        let httpHeaders = server.waitAndReturnRequests(count: 1)[0].allHTTPHeaderFields
        XCTAssertNil(httpHeaders!["User-Agent"]) // UA header is set to system default later by the OS
        XCTAssertEqual(httpHeaders?["Content-Type"], "text/plain;charset=UTF-8")
    }

    // MARK: - Payload Format

    func testItUsesExpectedPayloadFormatForUploads() throws {
        let server = ServerMock(delivery: .success(response: .mockResponseWith(statusCode: 200)))
        TracingFeature.instance = .mockWorkingFeatureWith(
            server: server,
            directory: temporaryDirectory,
            performance: .mockUnitTestsPerformancePresetByOverwritting(
                maxFileAgeForWrite: .distantFuture, // write all spans to single file
                maxLogsPerBatch: 3, // write 3 spans to payload
                initialLogsUploadDelay: 0.5 // wait enough until spans are written
            )
        )
        defer { TracingFeature.instance = nil }

        let tracer = DDTracer(tracingFeature: TracingFeature.instance!)

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
