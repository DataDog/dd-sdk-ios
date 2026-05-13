/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import TestUtilities
@_spi(Internal)
import DatadogInternal

@testable import DatadogRUM
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
        config.traceIDGenerator = RelativeTracingUUIDGenerator(startingFrom: .init(idHi: 10, idLo: 100))
        config.spanIDGenerator = RelativeSpanIDGenerator(startingFrom: 100, advancingByCount: 1)

        Trace.enable(
            with: config,
            in: core
        )
    }

    override func tearDownWithError() throws {
        try core.flushAndTearDown()
        core = nil
    }

    func testParentSpanPropagation() throws {
        let expectation = expectation(description: "request completes")
        // Given
        URLSessionInstrumentation.enableDurationBreakdown(
            with: URLSessionInstrumentation.Configuration(delegateClass: SessionDataDelegateMock.self),
            in: core
        )
        let request: URLRequest = .mockWith(url: .mockAny())
        let span = Tracer.shared(in: core).startRootSpan(operationName: "root")
        let server = ServerMock(delivery: .success(response: .mockResponseWith(statusCode: 200), data: .mock(ofSize: 10)))
        let session = server.getInterceptedURLSession(delegate: SessionDataDelegateMock())

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
        XCTAssertEqual(matchers.count, 2)

        let matcher1 = try XCTUnwrap(matchers.first)
        try XCTAssertEqual(matcher1.operationName(), "root")
        try XCTAssertEqual(matcher1.traceID(), .init(idHi: 10, idLo: 100))
        try XCTAssertEqual(matcher1.spanID(), .init(rawValue: 100))
        try XCTAssertEqual(matcher1.metrics.isRootSpan(), 1)

        let matcher2 = try XCTUnwrap(matchers.last)
        try XCTAssertEqual(matcher2.operationName(), "urlsession.request")
        try XCTAssertEqual(matcher2.traceID(), .init(idHi: 10, idLo: 100))
        try XCTAssertEqual(matcher2.parentSpanID(), .init(rawValue: 100))
        try XCTAssertEqual(matcher2.spanID(), .init(rawValue: 101))
    }

    func testResourceAttributesProvider_givenURLSessionDataTaskRequestWithCompletionHandler() throws {
        core = DatadogCoreProxy(
            context: .mockWith(
                env: "test",
                version: "1.1.1",
                serverTimeOffset: 123
            )
        )

        let providerExpectation = expectation(description: "provider called")
        var providerInfo: (resp: URLResponse?, data: Data?, err: Error?)?

        RUM.enable(
            with: .init(
                applicationID: .mockAny(),
                urlSessionTracking: .init(
                    resourceAttributesProvider: { _, resp, data, err in
                        providerInfo = (resp, data, err)
                        providerExpectation.fulfill()
                        return [:]
                    }
                )
            ),
            in: core
        )

        URLSessionInstrumentation.enableDurationBreakdown(
            with: .init(
                delegateClass: InstrumentedSessionDelegate.self
            ),
            in: core
        )

        let session = URLSession(
            configuration: .ephemeral,
            delegate: InstrumentedSessionDelegate(),
            delegateQueue: nil
        )
        let request = URLRequest(url: .mockAny())

        let taskExpectation = self.expectation(description: "task completed")
        var taskInfo: (resp: URLResponse?, data: Data?, err: Error?)?

        let task = session.dataTask(with: request) { data, resp, err in
            taskInfo = (resp, data, err)
            taskExpectation.fulfill()
        }
        task.resume()

        wait(for: [providerExpectation, taskExpectation], timeout: 10)
        XCTAssertEqual(providerInfo?.resp, taskInfo?.resp)
        let providerData = try XCTUnwrap(providerInfo?.data)
        XCTAssertTrue(providerData.count > 0, "Data should be available with registered delegate")
        XCTAssertEqual(providerData, taskInfo?.data)
        XCTAssertEqual(providerInfo?.err as? NSError, taskInfo?.err as? NSError)
    }

    // MARK: - Automatic mode

    func testAutomaticMode_resourceAttributesProvider_withCompletionHandler() {
        // Verifies that automatic mode passes response data to the provider for completion-handler tasks.
        core = DatadogCoreProxy(context: .mockWith(env: "test", version: "1.1.1", serverTimeOffset: 123))

        let providerExpectation = expectation(description: "provider called")
        var providerData: Data?

        RUM.enable(
            with: .init(
                applicationID: .mockAny(),
                urlSessionTracking: .init(
                    resourceAttributesProvider: { _, _, data, _ in
                        providerData = data
                        providerExpectation.fulfill()
                        return [:]
                    }
                )
            ),
            in: core
        )
        // No URLSessionInstrumentation.enableDurationBreakdown — automatic mode only

        let server = ServerMock(delivery: .success(response: .mockResponseWith(statusCode: 200), data: .mock(ofSize: 10)))
        let session = server.getInterceptedURLSession() // no registered delegate
        let taskExpectation = expectation(description: "task completed")

        let task = session.dataTask(with: URLRequest.mockAny()) { _, _, _ in
            taskExpectation.fulfill()
        }
        task.resume()

        wait(for: [providerExpectation, taskExpectation], timeout: 5)
        _ = server.waitAndReturnRequests(count: 1)

        XCTAssertEqual(providerData?.count, 10, "Automatic mode must pass response data to provider for completion-handler tasks")
    }

    @available(iOS 16, tvOS 16, watchOS 8, *)
    func testAutomaticMode_resourceAttributesProvider_asyncAwait_dataIsNil() async {
        // Documents the known limitation: async/await tasks return data directly to the caller,
        // bypassing all swizzled hooks, so data is always nil in the provider.
        core = DatadogCoreProxy(context: .mockWith(env: "test", version: "1.1.1", serverTimeOffset: 123))

        let providerExpectation = expectation(description: "provider called")
        var providerData: Data? = .mockAny() // initialize non-nil to confirm it is overwritten with nil

        RUM.enable(
            with: .init(
                applicationID: .mockAny(),
                urlSessionTracking: .init(
                    resourceAttributesProvider: { _, _, data, _ in
                        providerData = data
                        providerExpectation.fulfill()
                        return [:]
                    }
                )
            ),
            in: core
        )

        let server = ServerMock(
            delivery: .success(response: .mockResponseWith(statusCode: 200), data: .mock(ofSize: 10)),
            skipIsMainThreadCheck: true
        )
        let session = server.getInterceptedURLSession()

        _ = try? await session.data(from: URL.mockAny())

        await dd_fulfillment(for: [providerExpectation], timeout: 5)
        _ = server.waitAndReturnRequests(count: 1)

        XCTAssertNil(providerData, "Async/await tasks return data directly to the caller — the provider cannot capture it")
    }

    func testAutomaticMode_traceEmitsSpan() throws {
        // Verifies that Trace creates a span for URLSession requests in automatic mode,
        // without requiring `URLSessionInstrumentation.enableDurationBreakdown`.
        // setUp already called Trace.enable with urlSessionTracking for www.example.com.

        let server = ServerMock(delivery: .success(response: .mockResponseWith(statusCode: 200), data: .mock(ofSize: 10)))
        let session = server.getInterceptedURLSession() // no registered delegate — automatic mode only
        let taskExpectation = expectation(description: "task completed")

        let task = session.dataTask(with: URLRequest.mockAny()) { _, _, _ in
            taskExpectation.fulfill()
        }
        task.resume()

        wait(for: [taskExpectation], timeout: 5)
        _ = server.waitAndReturnRequests(count: 1)

        let matchers = try core.waitAndReturnSpanMatchers()
        let networkSpan = try XCTUnwrap(
            matchers.first(where: { (try? $0.operationName()) == "urlsession.request" }),
            "Trace must emit a urlsession.request span in automatic mode"
        )
        try XCTAssertEqual(networkSpan.operationName(), "urlsession.request")
    }

    // MARK: - Dual mode

    func testDualMode_doesNotDoubleTrackRequest_withRegisteredDelegate() throws {
        // Verifies that enabling both automatic mode (via RUM) and metrics mode (via enableDurationBreakdown)
        // does not cause a single request with a registered delegate to be tracked twice.
        core = DatadogCoreProxy(context: .mockWith(env: "test", version: "1.1.1", serverTimeOffset: 123))

        let providerExpectation = expectation(description: "provider called once")
        providerExpectation.assertForOverFulfill = true

        RUM.enable(
            with: .init(
                applicationID: .mockAny(),
                urlSessionTracking: .init(
                    resourceAttributesProvider: { _, _, _, _ in
                        providerExpectation.fulfill()
                        return [:]
                    }
                )
            ),
            in: core
        )
        URLSessionInstrumentation.enableDurationBreakdown(
            with: .init(delegateClass: SessionDataDelegateMock.self),
            in: core
        )

        let server = ServerMock(delivery: .success(response: .mockResponseWith(statusCode: 200), data: .mock(ofSize: 10)))
        let session = server.getInterceptedURLSession(delegate: SessionDataDelegateMock())
        let taskExpectation = expectation(description: "task completed")

        let task = session.dataTask(with: URLRequest.mockAny()) { _, _, _ in
            taskExpectation.fulfill()
        }
        task.resume()

        wait(for: [providerExpectation, taskExpectation], timeout: 5)
        _ = server.waitAndReturnRequests(count: 1)

        let resourceMatchers = try core.waitAndReturnRUMEventMatchers().filter { (try? $0.eventType()) == "resource" }
        XCTAssertEqual(resourceMatchers.count, 1, "Request must be tracked exactly once — both modes must not double-report the same task")
    }

    func testDualMode_resourceAttributesProvider_registeredDelegateWithoutCompletionHandler() {
        // Verifies that metrics mode captures response data via the delegate's didReceive callback
        // even when the task has no completion handler.
        core = DatadogCoreProxy(context: .mockWith(env: "test", version: "1.1.1", serverTimeOffset: 123))

        let providerExpectation = expectation(description: "provider called")
        var providerData: Data?

        RUM.enable(
            with: .init(
                applicationID: .mockAny(),
                urlSessionTracking: .init(
                    resourceAttributesProvider: { _, _, data, _ in
                        providerData = data
                        providerExpectation.fulfill()
                        return [:]
                    }
                )
            ),
            in: core
        )
        URLSessionInstrumentation.enableDurationBreakdown(
            with: .init(delegateClass: SessionDataDelegateMock.self),
            in: core
        )

        let server = ServerMock(delivery: .success(response: .mockResponseWith(statusCode: 200), data: .mock(ofSize: 10)))
        let session = server.getInterceptedURLSession(delegate: SessionDataDelegateMock())

        // No completion handler — data is captured via the delegate's didReceive callback
        session.dataTask(with: URLRequest.mockAny()).resume()

        wait(for: [providerExpectation], timeout: 5)
        _ = server.waitAndReturnRequests(count: 1)

        XCTAssertEqual(providerData?.count, 10, "Metrics mode must capture response data via delegate didReceive for tasks without completion handlers")
    }

    private class InstrumentedSessionDelegate: NSObject, URLSessionDataDelegate {}
}
