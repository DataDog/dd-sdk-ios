/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import TestUtilities
import DatadogInternal

@testable import DatadogTrace
@testable import DatadogCore

class NetworkInstrumentationIntegrationTests: XCTestCase {
    // swiftlint:disable implicitly_unwrapped_optional
    private var core: DatadogCoreProxy!
    // swiftlint:enable implicitly_unwrapped_optional

    override func setUp() {
        core = DatadogCoreProxy(
            context: .mockWith(
                env: "test",
                version: "1.1.1",
                serverTimeOffset: 123
            )
        )

        var config = Trace.Configuration(
            urlSessionTracking: Trace.Configuration.URLSessionTracking(
                firstPartyHostsTracing: .traceWithHeaders(
                    hostsWithHeaders: ["www.example.com": [.datadog]],
                    sampleRate: 100
                )
            )
        )
        config.traceIDGenerator = RelativeTracingUUIDGenerator(startingFrom: 1, advancingByCount: 1)

        Trace.enable(
            with: config,
            in: core
        )

        URLSessionInstrumentation.enable(
            with: URLSessionInstrumentation.Configuration(delegateClass: MockDelegate.self),
            in: core
        )
    }

    override func tearDown() {
        core.flushAndTearDown()
        core = nil
    }
    
    func testParentSpanPropagation() throws {
        let expectation = expectation(description: "request completes")
        // Given
        let request: URLRequest = .mockWith(url: "https://www.example.com")
        let span = Tracer.shared(in: core).startRootSpan(operationName: "root")
        let server = ServerMock(delivery: .success(response: .mockResponseWith(statusCode: 200), data: .mock(ofSize: 10)))
        let session = server.getInterceptedURLSession(delegate: MockDelegate())

        // When
        span.setActive() // start root span

        session
            .dataTask(with: request) { _,_,_ in
                span.finish() // finish root span
                expectation.fulfill()
            }
            .resume()

        // Then
        waitForExpectations(timeout: 1)
        let matchers = try core.waitAndReturnSpanMatchers()

        let matcher1 = try XCTUnwrap(matchers.first)
        try XCTAssertEqual(matcher1.operationName(), "root")
        try XCTAssertEqual(matcher1.traceID(), "1")
        try XCTAssertEqual(matcher1.spanID(), "2")
        try XCTAssertEqual(matcher1.metrics.isRootSpan(), 1)

        let matcher2 = try XCTUnwrap(matchers.last)
        try XCTAssertEqual(matcher2.operationName(), "urlsession.request")
        try XCTAssertEqual(matcher2.traceID(), "1")
        try XCTAssertEqual(matcher2.parentSpanID(), "2")
        try XCTAssertEqual(matcher2.spanID(), "3")
    }

    class MockDelegate: NSObject, URLSessionDataDelegate {
    }
}
