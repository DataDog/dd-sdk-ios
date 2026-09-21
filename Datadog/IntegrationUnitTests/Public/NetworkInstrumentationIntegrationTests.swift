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

    func testAutomaticTraceRequestTimeRUMOwnershipWithReverseCompletion() throws {
        RUM.enable(
            with: .init(applicationID: "rum-app", urlSessionTracking: nil),
            in: core
        )
        core.setUserInfo(id: "user-a")
        core.setAccountInfo(id: "account-a")

        let monitor = RUMMonitor.shared(in: core)
        monitor.startView(key: "view-a", name: "View A")
        monitor.startAction(type: .swipe, name: "Action A")
        core.flush()
        let contextA = try currentRUMContext()
        try assertUsableRUMContext(contextA)

        let coordinator = HeldURLProtocolCoordinator()
        let session = coordinator.makeSession()
        defer {
            coordinator.deactivate()
            session.invalidateAndCancel()
        }
        let requestA = makeHeldRequest(path: "a", marker: "A", callerHeader: "caller-a")
        let requestB = makeHeldRequest(path: "b", marker: "B", callerHeader: "caller-b", baggage: "custom=keep-b")
        let startedA = expectation(description: "request A reached URLProtocol start")
        let startedB = expectation(description: "request B reached URLProtocol start")
        coordinator.setOnStart { marker in
            if marker == "A" { startedA.fulfill() }
            if marker == "B" { startedB.fulfill() }
        }

        let completedA = expectation(description: "request A completed")
        let completedB = expectation(description: "request B completed")
        let taskA = session.dataTask(with: requestA) { data, response, error in
            coordinator.recordURLSessionCompletion(marker: "A", response: response, data: data, error: error)
            completedA.fulfill()
        }
        taskA.resume()
        wait(for: [startedA], timeout: 5)
        XCTAssertEqual(coordinator.request(for: "A")?.value(forHTTPHeaderField: "x-caller-header"), "caller-a")

        monitor.stopAction(type: .swipe, name: "Action A")
        monitor.startView(key: "view-b", name: "View B")
        monitor.startAction(type: .swipe, name: "Action B")
        core.setUserInfo(id: "user-b")
        core.setAccountInfo(id: "account-b")
        core.flush()
        let contextB = try currentRUMContext()
        try assertUsableRUMContext(contextB)
        XCTAssertNotEqual(contextA.viewID, contextB.viewID)
        XCTAssertNotEqual(contextA.userActionID, contextB.userActionID)

        let taskB = session.dataTask(with: requestB) { data, response, error in
            coordinator.recordURLSessionCompletion(marker: "B", response: response, data: data, error: error)
            completedB.fulfill()
        }
        taskB.resume()
        wait(for: [startedB], timeout: 5)
        XCTAssertEqual(coordinator.request(for: "B")?.value(forHTTPHeaderField: "x-caller-header"), "caller-b")

        coordinator.release(marker: "B")
        wait(for: [completedB], timeout: 5)
        coordinator.release(marker: "A")
        wait(for: [completedA], timeout: 5)
        core.flush()

        XCTAssertEqual(coordinator.startedMarkers.sorted(), ["A", "B"])
        XCTAssertEqual(coordinator.releasedMarkers, ["B", "A"])
        XCTAssertEqual(coordinator.completedMarkers, ["B", "A"])
        try assertURLSessionCompletion(for: coordinator, marker: "A")
        try assertURLSessionCompletion(for: coordinator, marker: "B")

        let spans = try core.waitAndReturnSpanMatchers()
        XCTAssertEqual(spans.count, 2)
        XCTAssertTrue(try spans.allSatisfy { try $0.operationName() == "urlsession.request" })
        let spanA = try XCTUnwrap(spans.first(where: { (try? $0.resource()) == "https://www.example.com/request-ownership/a" }))
        let spanB = try XCTUnwrap(spans.first(where: { (try? $0.resource()) == "https://www.example.com/request-ownership/b" }))
        try assertRUMTags(spanA, equalTo: contextA)
        try assertRUMTags(spanB, equalTo: contextB)
        try assertSpanTraceIdentity(spanA, request: coordinator.request(for: "A"))
        try assertSpanTraceIdentity(spanB, request: coordinator.request(for: "B"))
        try assertCompletionUserAndAccount(spanA, userID: "user-b", accountID: "account-b")
        try assertCompletionUserAndAccount(spanB, userID: "user-b", accountID: "account-b")
        try assertTraceHeaders(
            for: coordinator.request(for: "A"),
            expectedBaggage: "session.id=\(contextA.sessionID),user.id=user-a,account.id=account-a",
            callerHeader: "caller-a"
        )
        try assertTraceHeaders(
            for: coordinator.request(for: "B"),
            expectedBaggage: "custom=keep-b",
            callerHeader: "caller-b"
        )
    }

    func testAutomaticTraceRequestBeforeRUMDoesNotAdoptLaterOwnership() throws {
        core.setUserInfo(id: "user-before")
        core.setAccountInfo(id: "account-before")
        core.flush()

        let coordinator = HeldURLProtocolCoordinator()
        let session = coordinator.makeSession()
        defer {
            coordinator.deactivate()
            session.invalidateAndCancel()
        }
        let started = expectation(description: "request reached URLProtocol start")
        coordinator.setOnStart { marker in
            if marker == "before-rum" { started.fulfill() }
        }
        let completed = expectation(description: "request completed")
        let request = makeHeldRequest(path: "before-rum", marker: "before-rum", callerHeader: "caller-before")
        let task = session.dataTask(with: request) { data, response, error in
            coordinator.recordURLSessionCompletion(marker: "before-rum", response: response, data: data, error: error)
            completed.fulfill()
        }
        task.resume()
        wait(for: [started], timeout: 5)
        let requestAtStart = try XCTUnwrap(coordinator.request(for: "before-rum"))

        RUM.enable(
            with: .init(applicationID: "late-rum-app", urlSessionTracking: nil),
            in: core
        )
        let monitor = RUMMonitor.shared(in: core)
        monitor.startView(key: "late-view", name: "Late View")
        monitor.startAction(type: .swipe, name: "Late Action")
        core.setUserInfo(id: "user-after")
        core.setAccountInfo(id: "account-after")
        core.flush()
        let lateContext = try currentDatadogContext()
        let lateRUMContext = try XCTUnwrap(lateContext.additionalContext(ofType: RUMCoreContext.self))
        XCTAssertFalse(lateRUMContext.applicationID.isEmpty)
        XCTAssertFalse(lateRUMContext.sessionID.isEmpty)
        XCTAssertFalse(try XCTUnwrap(lateRUMContext.viewID).isEmpty)
        XCTAssertFalse(try XCTUnwrap(lateRUMContext.userActionID).isEmpty)
        XCTAssertEqual(lateContext.userInfo?.id, "user-after")
        XCTAssertEqual(lateContext.accountInfo?.id, "account-after")

        coordinator.release(marker: "before-rum")
        wait(for: [completed], timeout: 5)
        core.flush()

        XCTAssertEqual(coordinator.startedMarkers, ["before-rum"])
        XCTAssertEqual(coordinator.releasedMarkers, ["before-rum"])
        XCTAssertEqual(coordinator.completedMarkers, ["before-rum"])
        try assertURLSessionCompletion(for: coordinator, marker: "before-rum")

        let spans = try core.waitAndReturnSpanMatchers()
        XCTAssertEqual(spans.count, 1)
        XCTAssertTrue(try spans.allSatisfy { try $0.operationName() == "urlsession.request" })
        let span = try XCTUnwrap(spans.first)
        XCTAssertNil(try? span.meta.custom(keyPath: "meta._dd.application.id"), "no-RUM application tag")
        XCTAssertNil(try? span.meta.custom(keyPath: "meta._dd.session.id"), "no-RUM session tag")
        XCTAssertNil(try? span.meta.custom(keyPath: "meta._dd.view.id"), "no-RUM view tag")
        XCTAssertNil(try? span.meta.custom(keyPath: "meta._dd.action.id"), "no-RUM action tag")
        try assertCompletionUserAndAccount(span, userID: "user-after", accountID: "account-after")
        try assertSpanTraceIdentity(span, request: requestAtStart)
        try assertTraceHeaders(
            for: requestAtStart,
            expectedBaggage: "user.id=user-before,account.id=account-before",
            callerHeader: "caller-before"
        )
    }

    func testRegisteredTraceRequestTimeRUMOwnershipWithReverseCompletion() throws {
        RUM.enable(
            with: .init(applicationID: "rum-app", urlSessionTracking: nil),
            in: core
        )
        core.setUserInfo(id: "user-a")
        core.setAccountInfo(id: "account-a")

        let monitor = RUMMonitor.shared(in: core)
        monitor.startView(key: "view-a", name: "View A")
        monitor.startAction(type: .swipe, name: "Action A")
        core.flush()
        let contextA = try currentRUMContext()
        try assertUsableRUMContext(contextA)

        let coordinator = HeldURLProtocolCoordinator()
        let completedA = expectation(description: "delegate A completed")
        let completedB = expectation(description: "delegate B completed")
        let metricsA = expectation(description: "delegate A collected metrics")
        let metricsB = expectation(description: "delegate B collected metrics")
        URLSessionInstrumentation.enableDurationBreakdown(
            with: .init(delegateClass: RegisteredURLSessionDelegate.self),
            in: core
        )
        let delegate = RegisteredURLSessionDelegate(
            onMetrics: { marker in
                if marker == "A" { metricsA.fulfill() }
                if marker == "B" { metricsB.fulfill() }
            },
            onCompletion: { marker in
                if marker == "A" { completedA.fulfill() }
                if marker == "B" { completedB.fulfill() }
            }
        )
        let session = coordinator.makeRegisteredSession(delegate: delegate)
        XCTAssertTrue(session.delegate === delegate)
        defer {
            coordinator.deactivate()
            session.invalidateAndCancel()
        }
        let requestA = makeHeldRequest(path: "a", marker: "A", callerHeader: "caller-a")
        let requestB = makeHeldRequest(path: "b", marker: "B", callerHeader: "caller-b", baggage: "custom=keep-b")
        let startedA = expectation(description: "request A reached URLProtocol start")
        let startedB = expectation(description: "request B reached URLProtocol start")
        coordinator.setOnStart { marker in
            if marker == "A" { startedA.fulfill() }
            if marker == "B" { startedB.fulfill() }
        }

        let taskA = session.dataTask(with: requestA)
        taskA.resume()
        wait(for: [startedA], timeout: 5)
        XCTAssertEqual(coordinator.request(for: "A")?.value(forHTTPHeaderField: "x-caller-header"), "caller-a")

        monitor.stopAction(type: .swipe, name: "Action A")
        monitor.startView(key: "view-b", name: "View B")
        monitor.startAction(type: .swipe, name: "Action B")
        core.setUserInfo(id: "user-b")
        core.setAccountInfo(id: "account-b")
        core.flush()
        let contextB = try currentRUMContext()
        try assertUsableRUMContext(contextB)
        XCTAssertNotEqual(contextA.viewID, contextB.viewID)
        XCTAssertNotEqual(contextA.userActionID, contextB.userActionID)

        let taskB = session.dataTask(with: requestB)
        taskB.resume()
        wait(for: [startedB], timeout: 5)
        XCTAssertEqual(coordinator.request(for: "B")?.value(forHTTPHeaderField: "x-caller-header"), "caller-b")

        XCTAssertTrue(delegate.metricsMarkers.isEmpty)
        XCTAssertTrue(delegate.completedMarkers.isEmpty)
        coordinator.release(marker: "B")
        wait(for: [completedB, metricsB], timeout: 5)
        coordinator.release(marker: "A")
        wait(for: [completedA, metricsA], timeout: 5)
        core.flush()

        XCTAssertEqual(coordinator.startedMarkers.sorted(), ["A", "B"])
        XCTAssertEqual(coordinator.releasedMarkers, ["B", "A"])
        XCTAssertEqual(delegate.completedMarkers, ["B", "A"])
        XCTAssertEqual(delegate.metricsMarkers.sorted(), ["A", "B"])
        try assertRegisteredCallbacks(for: delegate, marker: "A", task: taskA)
        try assertRegisteredCallbacks(for: delegate, marker: "B", task: taskB)

        let spans = try core.waitAndReturnSpanMatchers()
        XCTAssertEqual(spans.count, 2)
        XCTAssertTrue(try spans.allSatisfy { try $0.operationName() == "urlsession.request" })
        let spanA = try XCTUnwrap(spans.first(where: { (try? $0.resource()) == "https://www.example.com/request-ownership/a" }))
        let spanB = try XCTUnwrap(spans.first(where: { (try? $0.resource()) == "https://www.example.com/request-ownership/b" }))
        try assertRUMTags(spanA, equalTo: contextA)
        try assertRUMTags(spanB, equalTo: contextB)
        try assertSpanTraceIdentity(spanA, request: coordinator.request(for: "A"))
        try assertSpanTraceIdentity(spanB, request: coordinator.request(for: "B"))
        try assertCompletionUserAndAccount(spanA, userID: "user-b", accountID: "account-b")
        try assertCompletionUserAndAccount(spanB, userID: "user-b", accountID: "account-b")
        try assertTraceHeaders(
            for: coordinator.request(for: "A"),
            expectedBaggage: "session.id=\(contextA.sessionID),user.id=user-a,account.id=account-a",
            callerHeader: "caller-a"
        )
        try assertTraceHeaders(
            for: coordinator.request(for: "B"),
            expectedBaggage: "custom=keep-b",
            callerHeader: "caller-b"
        )
    }

    func testRegisteredTraceRequestBeforeRUMDoesNotAdoptLaterOwnership() throws {
        core.setUserInfo(id: "user-before")
        core.setAccountInfo(id: "account-before")
        core.flush()

        let coordinator = HeldURLProtocolCoordinator()
        let completed = expectation(description: "delegate completed")
        let metrics = expectation(description: "delegate collected metrics")
        URLSessionInstrumentation.enableDurationBreakdown(
            with: .init(delegateClass: RegisteredURLSessionDelegate.self),
            in: core
        )
        let delegate = RegisteredURLSessionDelegate(
            onMetrics: { marker in
                if marker == "before-rum" { metrics.fulfill() }
            },
            onCompletion: { marker in
                if marker == "before-rum" { completed.fulfill() }
            }
        )
        let session = coordinator.makeRegisteredSession(delegate: delegate)
        XCTAssertTrue(session.delegate === delegate)
        defer {
            coordinator.deactivate()
            session.invalidateAndCancel()
        }
        let started = expectation(description: "request reached URLProtocol start")
        coordinator.setOnStart { marker in
            if marker == "before-rum" { started.fulfill() }
        }
        let request = makeHeldRequest(path: "before-rum", marker: "before-rum", callerHeader: "caller-before")
        let task = session.dataTask(with: request)
        task.resume()
        wait(for: [started], timeout: 5)
        let requestAtStart = try XCTUnwrap(coordinator.request(for: "before-rum"))

        RUM.enable(
            with: .init(applicationID: "late-rum-app", urlSessionTracking: nil),
            in: core
        )
        let monitor = RUMMonitor.shared(in: core)
        monitor.startView(key: "late-view", name: "Late View")
        monitor.startAction(type: .swipe, name: "Late Action")
        core.setUserInfo(id: "user-after")
        core.setAccountInfo(id: "account-after")
        core.flush()
        let lateContext = try currentDatadogContext()
        let lateRUMContext = try XCTUnwrap(lateContext.additionalContext(ofType: RUMCoreContext.self))
        XCTAssertFalse(lateRUMContext.applicationID.isEmpty)
        XCTAssertFalse(lateRUMContext.sessionID.isEmpty)
        XCTAssertFalse(try XCTUnwrap(lateRUMContext.viewID).isEmpty)
        XCTAssertFalse(try XCTUnwrap(lateRUMContext.userActionID).isEmpty)
        XCTAssertEqual(lateContext.userInfo?.id, "user-after")
        XCTAssertEqual(lateContext.accountInfo?.id, "account-after")

        XCTAssertTrue(delegate.metricsMarkers.isEmpty)
        XCTAssertTrue(delegate.completedMarkers.isEmpty)
        coordinator.release(marker: "before-rum")
        wait(for: [completed, metrics], timeout: 5)
        core.flush()

        XCTAssertEqual(coordinator.startedMarkers, ["before-rum"])
        XCTAssertEqual(coordinator.releasedMarkers, ["before-rum"])
        XCTAssertEqual(delegate.completedMarkers, ["before-rum"])
        XCTAssertEqual(delegate.metricsMarkers, ["before-rum"])
        try assertRegisteredCallbacks(for: delegate, marker: "before-rum", task: task)

        let spans = try core.waitAndReturnSpanMatchers()
        XCTAssertEqual(spans.count, 1)
        XCTAssertTrue(try spans.allSatisfy { try $0.operationName() == "urlsession.request" })
        let span = try XCTUnwrap(spans.first)
        XCTAssertNil(try? span.meta.custom(keyPath: "meta._dd.application.id"), "no-RUM application tag")
        XCTAssertNil(try? span.meta.custom(keyPath: "meta._dd.session.id"), "no-RUM session tag")
        XCTAssertNil(try? span.meta.custom(keyPath: "meta._dd.view.id"), "no-RUM view tag")
        XCTAssertNil(try? span.meta.custom(keyPath: "meta._dd.action.id"), "no-RUM action tag")
        try assertCompletionUserAndAccount(span, userID: "user-after", accountID: "account-after")
        try assertSpanTraceIdentity(span, request: requestAtStart)
        try assertTraceHeaders(
            for: requestAtStart,
            expectedBaggage: "user.id=user-before,account.id=account-before",
            callerHeader: "caller-before"
        )
    }

    private func assertRegisteredCallbacks(
        for delegate: RegisteredURLSessionDelegate,
        marker: String,
        task: URLSessionTask
    ) throws {
        let receipt = try XCTUnwrap(delegate.receipt(for: marker))
        XCTAssertEqual(receipt.taskIdentifiers, Set([task.taskIdentifier]))
        XCTAssertEqual(receipt.dataCallbacks, 1)
        XCTAssertEqual(receipt.body, Data("ok".utf8))
        XCTAssertEqual(receipt.completionCount, 1)
        XCTAssertEqual(receipt.statusCode, 200)
        XCTAssertFalse(receipt.hasError)
        XCTAssertEqual(receipt.metrics.count, 1)
        let metrics = try XCTUnwrap(receipt.metrics.first)
        XCTAssertTrue(metrics.interval.start.timeIntervalSinceReferenceDate.isFinite)
        XCTAssertTrue(metrics.interval.end.timeIntervalSinceReferenceDate.isFinite)
        XCTAssertGreaterThan(metrics.interval.duration, 0)
        XCTAssertTrue(metrics.interval.duration.isFinite)
        let attachment = XCTAttachment(string: "marker=\(marker) task=\(task.taskIdentifier) data=\(receipt.dataCallbacks) metrics=\(receipt.metrics.count) completions=\(receipt.completionCount) duration=\(metrics.interval.duration) transactions=\(metrics.transactionCount)")
        attachment.name = "Registered URLSession callback receipts"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func currentRUMContext() throws -> RUMCoreContext {
        let context = try currentDatadogContext()
        return try XCTUnwrap(context.additionalContext(ofType: RUMCoreContext.self))
    }

    private func currentDatadogContext() throws -> DatadogContext {
        let expectation = expectation(description: "current RUM context")
        var result: DatadogContext?
        core.scope(for: RUMFeature.self).context { context in
            result = context
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 5)
        return try XCTUnwrap(result)
    }

    private func assertUsableRUMContext(_ context: RUMCoreContext) throws {
        XCTAssertFalse(context.applicationID.isEmpty)
        XCTAssertFalse(context.sessionID.isEmpty)
        XCTAssertFalse(try XCTUnwrap(context.viewID).isEmpty)
        XCTAssertFalse(try XCTUnwrap(context.userActionID).isEmpty)
    }

    private func assertURLSessionCompletion(
        for coordinator: HeldURLProtocolCoordinator,
        marker: String
    ) throws {
        let receipt = try XCTUnwrap(coordinator.completionReceipt(for: marker))
        XCTAssertEqual(receipt.count, 1)
        XCTAssertEqual(receipt.statusCode, 200)
        XCTAssertEqual(receipt.body, Data("ok".utf8))
        XCTAssertFalse(receipt.hasError)
    }

    private func makeHeldRequest(path: String, marker: String, callerHeader: String, baggage: String? = nil) -> URLRequest {
        var request = URLRequest(url: URL(string: "https://www.example.com/request-ownership/\(path)")!)
        request.setValue(marker, forHTTPHeaderField: "x-request-marker")
        request.setValue(callerHeader, forHTTPHeaderField: "x-caller-header")
        if let baggage {
            request.setValue(baggage, forHTTPHeaderField: "baggage")
        }
        return request
    }

    private func assertRUMTags(_ span: SpanMatcher, equalTo context: RUMCoreContext) throws {
        try XCTAssertEqual(span.meta.custom(keyPath: "meta._dd.application.id"), context.applicationID)
        try XCTAssertEqual(span.meta.custom(keyPath: "meta._dd.session.id"), context.sessionID)
        XCTAssertEqual(
            try? span.meta.custom(keyPath: "meta._dd.view.id"),
            context.viewID,
            "request-time view owner"
        )
        XCTAssertEqual(
            try? span.meta.custom(keyPath: "meta._dd.action.id"),
            context.userActionID,
            "request-time action owner"
        )
    }

    private func assertCompletionUserAndAccount(_ span: SpanMatcher, userID: String, accountID: String) throws {
        try XCTAssertEqual(span.meta.userID(), userID)
        try XCTAssertEqual(span.meta.accountID(), accountID)
    }

    private func assertSpanTraceIdentity(_ span: SpanMatcher, request: URLRequest?) throws {
        let request = try XCTUnwrap(request)
        let spanTraceID = try XCTUnwrap(try span.traceID())
        let requestTraceIDString = try XCTUnwrap(request.value(forHTTPHeaderField: "x-datadog-trace-id"))
        let requestTraceID = try XCTUnwrap(UInt64(requestTraceIDString))
        XCTAssertEqual(spanTraceID.idLo, requestTraceID)
        let tags = try XCTUnwrap(request.value(forHTTPHeaderField: "x-datadog-tags"))
        let traceIDHighHex = try XCTUnwrap(
            tags.split(separator: ",")
                .first(where: { $0.hasPrefix("_dd.p.tid=") })?
                .split(separator: "=", maxSplits: 1)
                .last
        )
        XCTAssertEqual(spanTraceID.idHi, try XCTUnwrap(UInt64(traceIDHighHex, radix: 16)))
        let spanID = try XCTUnwrap(try span.spanID())
        let requestSpanIDString = try XCTUnwrap(request.value(forHTTPHeaderField: "x-datadog-parent-id"))
        let requestSpanID = try XCTUnwrap(UInt64(requestSpanIDString))
        XCTAssertEqual(spanID.rawValue, requestSpanID)
    }

    private func assertTraceHeaders(
        for request: URLRequest?,
        expectedBaggage: String,
        callerHeader: String
    ) throws {
        let request = try XCTUnwrap(request)
        XCTAssertEqual(request.value(forHTTPHeaderField: "x-caller-header"), callerHeader)
        XCTAssertEqual(request.value(forHTTPHeaderField: "baggage"), expectedBaggage)
        XCTAssertNotNil(request.value(forHTTPHeaderField: "x-datadog-trace-id"))
        XCTAssertNotNil(request.value(forHTTPHeaderField: "x-datadog-parent-id"))
        XCTAssertEqual(request.value(forHTTPHeaderField: "x-datadog-sampling-priority"), "1")
        XCTAssertNotNil(request.value(forHTTPHeaderField: "x-datadog-tags"))
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

private final class HeldURLProtocolCoordinator {
    struct CompletionReceipt: Equatable {
        var count: Int
        var statusCode: Int?
        var body: Data?
        var hasError: Bool
    }

    private let lock = NSLock()
    private var protocols: [String: HeldURLProtocol] = [:]
    private var requests: [String: URLRequest] = [:]
    private var started: [String] = []
    private var released: [String] = []
    private var completed: [String] = []
    private var completionReceipts: [String: CompletionReceipt] = [:]
    private var active = true
    private var onStart: ((String) -> Void)?

    var startedMarkers: [String] { snapshot { started } }
    var releasedMarkers: [String] { snapshot { released } }
    var completedMarkers: [String] { snapshot { completed } }

    func makeSession() -> URLSession {
        HeldURLProtocol.setActiveCoordinator(self)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [HeldURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    func makeRegisteredSession(delegate: RegisteredURLSessionDelegate) -> URLSession {
        HeldURLProtocol.setActiveCoordinator(self)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [HeldURLProtocol.self]
        return URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
    }

    func deactivate() {
        lock.lock()
        active = false
        protocols.removeAll()
        onStart = nil
        lock.unlock()
        HeldURLProtocol.clearActiveCoordinator(self)
    }

    func setOnStart(_ callback: @escaping (String) -> Void) {
        lock.lock()
        onStart = callback
        lock.unlock()
    }

    func recordStart(protocolInstance: HeldURLProtocol, request: URLRequest) {
        guard let marker = request.value(forHTTPHeaderField: "x-request-marker") else {
            return
        }
        lock.lock()
        guard active else {
            lock.unlock()
            protocolInstance.terminate()
            return
        }
        protocols[marker] = protocolInstance
        requests[marker] = request
        started.append(marker)
        let callback = onStart
        lock.unlock()
        callback?(marker)
    }

    func recordURLSessionCompletion(marker: String, response: URLResponse?, data: Data?, error: Error?) {
        lock.lock()
        var receipt = completionReceipts[marker] ?? CompletionReceipt(count: 0, statusCode: nil, body: nil, hasError: false)
        receipt.count += 1
        receipt.statusCode = (response as? HTTPURLResponse)?.statusCode
        receipt.body = data
        receipt.hasError = error != nil
        completionReceipts[marker] = receipt
        completed.append(marker)
        lock.unlock()
    }

    func request(for marker: String) -> URLRequest? {
        lock.lock()
        defer { lock.unlock() }
        return requests[marker]
    }

    func release(marker: String) {
        lock.lock()
        let protocolInstance = protocols.removeValue(forKey: marker)
        released.append(marker)
        lock.unlock()
        protocolInstance?.finishLoading()
    }

    func remove(protocolInstance: HeldURLProtocol) {
        lock.lock()
        protocols = protocols.filter { $0.value !== protocolInstance }
        lock.unlock()
    }

    func completionReceipt(for marker: String) -> CompletionReceipt? {
        lock.lock()
        defer { lock.unlock() }
        return completionReceipts[marker]
    }

    private func snapshot<T>(_ read: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return read()
    }
}

private final class RegisteredURLSessionDelegate: NSObject, URLSessionDataDelegate {
    struct MetricsReceipt {
        var interval: DateInterval
        var transactionCount: Int
    }

    struct CallbackReceipt {
        var taskIdentifiers: Set<Int> = []
        var dataCallbacks = 0
        var body = Data()
        var metrics: [MetricsReceipt] = []
        var completionCount = 0
        var statusCode: Int?
        var hasError = false
    }

    private let lock = NSLock()
    private let onMetrics: (String) -> Void
    private let onCompletion: (String) -> Void
    private var receipts: [String: CallbackReceipt] = [:]
    private var metricsOrder: [String] = []
    private var completionOrder: [String] = []

    init(onMetrics: @escaping (String) -> Void, onCompletion: @escaping (String) -> Void) {
        self.onMetrics = onMetrics
        self.onCompletion = onCompletion
    }

    var metricsMarkers: [String] {
        lock.lock()
        defer { lock.unlock() }
        return metricsOrder
    }

    var completedMarkers: [String] {
        lock.lock()
        defer { lock.unlock() }
        return completionOrder
    }

    func receipt(for marker: String) -> CallbackReceipt? {
        lock.lock()
        defer { lock.unlock() }
        return receipts[marker]
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        let marker = dataTask.originalRequest?.value(forHTTPHeaderField: "x-request-marker") ?? "missing-marker"
        lock.lock()
        var receipt = receipts[marker] ?? CallbackReceipt()
        receipt.taskIdentifiers.insert(dataTask.taskIdentifier)
        receipt.dataCallbacks += 1
        receipt.body.append(data)
        receipts[marker] = receipt
        lock.unlock()
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didFinishCollecting metrics: URLSessionTaskMetrics) {
        let marker = task.originalRequest?.value(forHTTPHeaderField: "x-request-marker") ?? "missing-marker"
        lock.lock()
        var receipt = receipts[marker] ?? CallbackReceipt()
        receipt.taskIdentifiers.insert(task.taskIdentifier)
        receipt.metrics.append(MetricsReceipt(interval: metrics.taskInterval, transactionCount: metrics.transactionMetrics.count))
        receipts[marker] = receipt
        metricsOrder.append(marker)
        lock.unlock()
        onMetrics(marker)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        let marker = task.originalRequest?.value(forHTTPHeaderField: "x-request-marker") ?? "missing-marker"
        lock.lock()
        var receipt = receipts[marker] ?? CallbackReceipt()
        receipt.taskIdentifiers.insert(task.taskIdentifier)
        receipt.completionCount += 1
        receipt.statusCode = (task.response as? HTTPURLResponse)?.statusCode
        receipt.hasError = error != nil
        receipts[marker] = receipt
        completionOrder.append(marker)
        lock.unlock()
        onCompletion(marker)
    }
}

private final class HeldURLProtocol: URLProtocol {
    private static let coordinatorLock = NSLock()
    private static var activeCoordinator: HeldURLProtocolCoordinator?
    private weak var coordinator: HeldURLProtocolCoordinator?

    static func setActiveCoordinator(_ coordinator: HeldURLProtocolCoordinator) {
        coordinatorLock.lock()
        activeCoordinator = coordinator
        coordinatorLock.unlock()
    }

    static func clearActiveCoordinator(_ coordinator: HeldURLProtocolCoordinator) {
        coordinatorLock.lock()
        if activeCoordinator === coordinator {
            activeCoordinator = nil
        }
        coordinatorLock.unlock()
    }

    private static func currentCoordinator() -> HeldURLProtocolCoordinator? {
        coordinatorLock.lock()
        let coordinator = activeCoordinator
        coordinatorLock.unlock()
        return coordinator
    }

    override class func canInit(with request: URLRequest) -> Bool {
        request.value(forHTTPHeaderField: "x-request-marker") != nil
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override init(request: URLRequest, cachedResponse: CachedURLResponse?, client: URLProtocolClient?) {
        coordinator = Self.currentCoordinator()
        super.init(request: request, cachedResponse: cachedResponse, client: client)
    }

    override func startLoading() {
        guard let coordinator else {
            terminate()
            return
        }
        coordinator.recordStart(protocolInstance: self, request: request)
    }

    override func stopLoading() {
        coordinator?.remove(protocolInstance: self)
    }

    func terminate() {
        client?.urlProtocol(self, didFailWithError: URLError(.cancelled))
    }

    func finishLoading() {
        guard let url = request.url,
              let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: ["Content-Length": "2"]) else {
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data("ok".utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
}

#if os(iOS)
import Network

final class E03NativeResourceCompletionTests: XCTestCase {
    @MainActor
    func testNativeMissingBodyFailureReportsNetworkError() throws { try runTransfer(.missingBody) }
    @MainActor
    func testNativePartialBodyFailureReportsNetworkError() throws { try runTransfer(.partialBody) }
    @MainActor
    func testNativeCompleteBodyReportsResource() throws { try runTransfer(.complete) }
    @MainActor
    func testNativeSuccessfulHEADReportsEmptyResource() throws { try runTransfer(.head) }
    @MainActor
    func testNativeSuccessful204ReportsEmptyResource() throws { try runTransfer(.noContent) }
    @MainActor
    func testNativeNoResponseFailureReportsNetworkError() throws { try runTransfer(.noResponse) }
    @MainActor
    func testNativeFailedBodyAfterNavigationRetainsOwner() throws { try runTransfer(.partialBody, transition: .view) }
    @MainActor
    func testNativeFailedBodyAfterSessionStopRetainsOwner() throws { try runTransfer(.partialBody, transition: .session) }
    @MainActor
    func testNativeCompleteHTTPErrorPreservesResourcePolicy() throws { try runTransfer(.httpError) }

    private enum Transition { case none, view, session }

    @MainActor
    private func runTransfer(_ mode: E03TransferServer.Mode, transition: Transition = .none) throws {
        XCTAssertTrue(Thread.isMainThread)
        let ready = expectation(description: "local listener ready")
        let requestReceived = expectation(description: "native request received")
        let headersWritten = mode == .noResponse ? nil : expectation(description: "HTTP headers written")
        let server = try E03TransferServer(mode: mode, ready: ready, requestReceived: requestReceived, headersWritten: headersWritten)
        server.start()
        wait(for: [ready], timeout: 5)
        let port = try XCTUnwrap(server.port)
        let url = try XCTUnwrap(URL(string: "http://127.0.0.1:\(port)/transfer/\(UUID().uuidString)"))
        let core = DatadogCoreProxy(context: .mockWith(env: "test", version: "1.1.1", serverTimeOffset: 0))
        defer {
            let stopped = expectation(description: "listener and connections cancelled")
            server.stop(completion: { stopped.fulfill() })
            wait(for: [stopped], timeout: 5)
            XCTAssertEqual(server.activeConnections, 0)
            XCTAssertTrue(server.listenerCancelled)
            XCTAssertNoThrow(try core.flushAndTearDown())
        }
        RUM.enable(with: .init(applicationID: "e03-transfer", urlSessionTracking: .init(), trackFrustrations: true), in: core)
        URLSessionInstrumentation.enableDurationBreakdown(with: .init(delegateClass: E03TransferDelegate.self), in: core)
        let monitor = RUMMonitor.shared(in: core)
        monitor.startView(key: "transfer-owner", name: "Transfer Owner")
        monitor.startAction(type: .tap, name: "Transfer Action")
        core.flush()
        let owner = try rumContext(core)
        let completed = expectation(description: "URLSession native completion")
        let invalidated = expectation(description: "URLSession invalidation")
        let headers = mode == .noResponse ? nil : expectation(description: "URLSession received HTTP headers")
        let firstData = mode.body.isEmpty ? nil : expectation(description: "URLSession received initial body byte")
        let delegate = E03TransferDelegate(headers: headers, firstData: firstData, completed: completed, invalidated: invalidated)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = []
        configuration.timeoutIntervalForRequest = 5
        configuration.timeoutIntervalForResource = 8
        let session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: .main)
        defer {
            session.invalidateAndCancel()
            wait(for: [invalidated], timeout: 5)
        }
        var request = URLRequest(url: url)
        request.httpMethod = mode == .head ? "HEAD" : mode == .noResponse ? "POST" : "GET"
        let task = session.dataTask(with: request)
        task.resume()
        wait(for: [requestReceived], timeout: 5)
        if let headersWritten { wait(for: [headersWritten], timeout: 5) }
        if mode != .missingBody, let headers { wait(for: [headers], timeout: 5) }
        if let firstData { wait(for: [firstData], timeout: 5) }
        if !mode.body.isEmpty {
            guard delegate.completionCount == 0, delegate.response?.statusCode == mode.status,
                  delegate.data == Data(mode.body.prefix(1)), server.sentBodyBytes == 1 else {
                XCTFail("Body transfer must expose headers and its first byte while still pending")
                return
            }
        }
        core.flush()
        var current = owner
        if transition != .none {
            if transition == .session { monitor.stopSession() }
            monitor.startView(key: "transfer-peer", name: "Transfer Peer")
            monitor.startAction(type: .tap, name: "Peer Action")
            core.flush()
            current = try rumContext(core)
            XCTAssertNotEqual(current.viewID, owner.viewID)
            if transition == .session { XCTAssertNotEqual(current.sessionID, owner.sessionID) }
        }
        let completionsBeforeRelease = delegate.completionCount
        let serverBodyBytesBeforeRelease = server.sentBodyBytes
        let receivedBytesBeforeRelease = delegate.data.count
        let headersBeforeRelease = delegate.responseCount
        if mode == .missingBody || mode == .partialBody {
            XCTAssertEqual(completionsBeforeRelease, 0, "Transfer must still be pending before body release")
            XCTAssertNil(delegate.error)
            XCTAssertEqual(server.sentBodyBytes, mode == .partialBody ? 1 : 0)
            if mode == .partialBody { XCTAssertEqual(delegate.response?.statusCode, 200) }
        }
        server.finishBody()
        if mode == .missingBody, let headers { wait(for: [headers], timeout: 5) }
        wait(for: [completed], timeout: 8)
        core.flush()
        monitor.stopAction(type: .tap, name: transition == .none ? "Transfer Action" : "Peer Action")
        monitor.stopView(key: transition == .none ? "transfer-owner" : "transfer-peer")
        core.flush()
        let events = try core.waitAndReturnRUMEventMatchers()
        let resources: [RUMResourceEvent] = try events.filter { try $0.eventType() == "resource" }.map { try $0.model() }
        let errors: [RUMErrorEvent] = try events.filter { try $0.eventType() == "error" }.map { try $0.model() }
        let actions: [RUMActionEvent] = try events.filter { try $0.eventType() == "action" }.map { try $0.model() }
        let receipt: [String: Any] = [
            "mode": String(describing: mode), "requestCount": server.requestCount,
            "serverBodyBytes": server.sentBodyBytes, "responseCallbacks": delegate.responseCount,
            "serverBodyBytesBeforeRelease": serverBodyBytesBeforeRelease, "receivedBytesBeforeRelease": receivedBytesBeforeRelease,
            "headersBeforeRelease": headersBeforeRelease,
            "completionCallbacks": delegate.completionCount, "completionsBeforeRelease": completionsBeforeRelease, "receivedBytes": delegate.data.count,
            "receivedStatus": delegate.response?.statusCode ?? 0, "completionStatus": delegate.completionResponse?.statusCode ?? 0,
            "errorDomain": delegate.error?.domain ?? "", "errorCode": delegate.error?.code ?? 0,
            "ownerView": owner.viewID ?? "", "ownerSession": owner.sessionID,
            "currentView": current.viewID ?? "", "currentSession": current.sessionID,
            "resources": resources.count, "errors": errors.count
        ]
        let attachment = XCTAttachment(data: try JSONSerialization.data(withJSONObject: receipt, options: [.sortedKeys]), uniformTypeIdentifier: "public.json")
        attachment.name = "native-transfer-receipt"; attachment.lifetime = .keepAlways; add(attachment)
        let serialized = events.map { String(decoding: $0.jsonData, as: UTF8.self) }.joined(separator: "\n")
        let telemetry = XCTAttachment(string: serialized)
        telemetry.name = "serialized-rum-events"; telemetry.lifetime = .keepAlways; add(telemetry)
        XCTAssertEqual(server.requestCount, 1)
        XCTAssertEqual(server.sentBodyBytes, mode.body.count)
        XCTAssertEqual(delegate.completionCount, 1)
        XCTAssertEqual(delegate.responseCount, mode == .noResponse ? 0 : 1)
        XCTAssertEqual(delegate.response?.statusCode, mode.status)
        XCTAssertEqual(delegate.completionResponse?.statusCode, mode.status)
        XCTAssertEqual(delegate.data, mode.body)
        XCTAssertEqual(delegate.error != nil, mode.isFailure)
        if mode.isFailure {
            XCTAssertEqual(delegate.error?.domain, NSURLErrorDomain)
            XCTAssertEqual(resources.count, 0)
            XCTAssertEqual(errors.count, 1)
            let error = try XCTUnwrap(errors.first)
            XCTAssertEqual(error.error.source, .network)
            XCTAssertEqual(error.error.category, .network)
            XCTAssertEqual(error.error.resource?.url, url.absoluteString)
            XCTAssertEqual(error.error.resource?.statusCode, Int64(mode.status ?? 0))
            XCTAssertEqual(error.view.id, owner.viewID)
            XCTAssertEqual(error.session.id, owner.sessionID)
        } else {
            XCTAssertEqual(errors.count, 0)
            XCTAssertEqual(resources.count, 1)
            let resource = try XCTUnwrap(resources.first)
            XCTAssertEqual(resource.resource.url, url.absoluteString)
            XCTAssertEqual(resource.resource.statusCode, Int64(mode.status!))
            XCTAssertEqual(resource.view.id, owner.viewID)
            XCTAssertEqual(resource.session.id, owner.sessionID)
        }
        let currentActions = actions.filter { $0.action.target?.name == (transition == .none ? "Transfer Action" : "Peer Action") }
        XCTAssertEqual(currentActions.count, 1)
        let currentAction = try XCTUnwrap(currentActions.first)
        XCTAssertEqual(currentAction.view.id, current.viewID)
        XCTAssertEqual(currentAction.session.id, current.sessionID)
        XCTAssertEqual(actions.filter { $0.action.target?.name == "Transfer Action" }.count, 1)
        XCTAssertEqual(currentAction.action.resource?.count, transition == .none && !mode.isFailure ? 1 : 0)
        XCTAssertEqual(currentAction.action.error?.count, transition == .none && mode.isFailure ? 1 : 0)
        if transition == .none && mode.isFailure {
            XCTAssertEqual(currentAction.action.frustration?.type, [.errorTap])
        } else {
            XCTAssertNil(currentAction.action.frustration)
        }
    }

    private func rumContext(_ core: DatadogCoreProxy) throws -> RUMCoreContext {
        let ready = expectation(description: "RUM context available")
        var value: RUMCoreContext?
        core.scope(for: RUMFeature.self).context { context in
            value = context.additionalContext(ofType: RUMCoreContext.self)
            ready.fulfill()
        }
        wait(for: [ready], timeout: 5)
        return try XCTUnwrap(value)
    }
}

private final class E03TransferDelegate: NSObject, URLSessionDataDelegate {
    let headers: XCTestExpectation?
    let firstData: XCTestExpectation?
    let completed: XCTestExpectation
    let invalidated: XCTestExpectation
    var response: HTTPURLResponse?
    var completionResponse: HTTPURLResponse?
    var data = Data()
    var error: NSError?
    var responseCount = 0
    var completionCount = 0

    init(headers: XCTestExpectation?, firstData: XCTestExpectation?, completed: XCTestExpectation, invalidated: XCTestExpectation) {
        self.headers = headers; self.firstData = firstData; self.completed = completed; self.invalidated = invalidated
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        XCTAssertTrue(Thread.isMainThread)
        self.response = response as? HTTPURLResponse
        responseCount += 1
        headers?.fulfill()
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        XCTAssertTrue(Thread.isMainThread)
        let isFirstData = self.data.isEmpty
        self.data.append(data)
        if isFirstData { firstData?.fulfill() }
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, didFinishCollecting metrics: URLSessionTaskMetrics) {}
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        XCTAssertTrue(Thread.isMainThread)
        completionResponse = task.response as? HTTPURLResponse
        self.error = error as NSError?
        completionCount += 1
        completed.fulfill()
    }
    func urlSession(_ session: URLSession, didBecomeInvalidWithError error: Error?) { invalidated.fulfill() }
}

private final class E03TransferServer {
    enum Mode {
        case missingBody, partialBody, complete, head, noContent, noResponse, httpError
        var status: Int? { self == .noResponse ? nil : self == .noContent ? 204 : self == .httpError ? 404 : 200 }
        var isFailure: Bool { self == .missingBody || self == .partialBody || self == .noResponse }
        var body: Data { self == .partialBody ? Data("part".utf8) : self == .complete || self == .httpError ? Data("body".utf8) : Data() }
    }
    private let listener: NWListener
    private let mode: Mode
    private let ready: XCTestExpectation
    private let requestReceived: XCTestExpectation
    private let headersWritten: XCTestExpectation?
    private var connections: [NWConnection] = []
    private var requestConnection: NWConnection?
    private var onStopped: (() -> Void)?
    private(set) var requestCount = 0
    private(set) var sentBodyBytes = 0
    private(set) var activeConnections = 0
    private(set) var listenerCancelled = false
    var port: UInt16? { listener.port?.rawValue }

    init(mode: Mode, ready: XCTestExpectation, requestReceived: XCTestExpectation, headersWritten: XCTestExpectation?) throws {
        self.mode = mode; self.ready = ready; self.requestReceived = requestReceived; self.headersWritten = headersWritten
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: .any)
        listener = try NWListener(using: parameters)
    }

    func start() {
        listener.stateUpdateHandler = { [weak self] state in
            guard let self else {
                return
            }
            switch state {
            case .ready: ready.fulfill()
            case .failed: XCTFail("Local transfer listener failed")
            case .cancelled: listenerCancelled = true; finishStopIfReady()
            default: break
            }
        }
        listener.newConnectionHandler = { [weak self] connection in
            guard let self else {
                connection.cancel()
                return
            }
            connections.append(connection); activeConnections += 1
            connection.stateUpdateHandler = { [weak self] state in
                if case .cancelled = state { self?.activeConnections -= 1; self?.finishStopIfReady() }
            }
            connection.start(queue: .main)
            receiveRequest(connection, buffered: Data())
        }
        listener.start(queue: .main)
    }

    private func receiveRequest(_ connection: NWConnection, buffered: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { [weak self, weak connection] data, _, complete, error in
            guard let self, let connection else {
                return
            }
            let bytes = buffered + (data ?? Data())
            guard String(decoding: bytes, as: UTF8.self).contains("\r\n\r\n") else {
                if error == nil && !complete && bytes.count < 16_384 {
                    receiveRequest(connection, buffered: bytes)
                } else {
                    XCTFail("Incomplete native HTTP request")
                    connection.cancel()
                }
                return
            }
            XCTAssertTrue(Thread.isMainThread)
            requestCount += 1
            guard requestCount == 1 else {
                XCTFail("Unexpected repeated native request")
                connection.cancel()
                return
            }
            requestConnection = connection
            if let status = mode.status {
                let length = mode.isFailure ? 128 : mode == .head ? 128 : mode.body.count
                let noSniff = mode == .missingBody || !mode.body.isEmpty ? "X-Content-Type-Options: nosniff\r\n" : ""
                let header = "HTTP/1.1 \(status) Response\r\nContent-Length: \(length)\r\nContent-Type: text/plain\r\n" + noSniff + "Connection: close\r\n\r\n"
                let initialBody = mode.body.prefix(1)
                sentBodyBytes = initialBody.count
                connection.send(content: Data(header.utf8) + initialBody, completion: .contentProcessed { [weak self] error in
                    XCTAssertTrue(Thread.isMainThread)
                    XCTAssertNil(error)
                    self?.headersWritten?.fulfill()
                })
            }
            requestReceived.fulfill()
        }
    }

    func finishBody() {
        guard let connection = requestConnection else {
            XCTFail("No native connection to complete")
            return
        }
        let remainingBody = mode.body.dropFirst(sentBodyBytes)
        XCTAssertTrue(Thread.isMainThread)
        sentBodyBytes += remainingBody.count
        if remainingBody.isEmpty {
            connection.cancel()
        } else {
            connection.send(content: remainingBody, completion: .contentProcessed { [weak connection] error in
                XCTAssertNil(error)
                connection?.cancel()
            })
        }
    }

    func stop(completion: @escaping () -> Void) {
        onStopped = completion
        connections.forEach { $0.cancel() }
        listener.cancel()
        finishStopIfReady()
    }

    private func finishStopIfReady() {
        if listenerCancelled && activeConnections == 0 {
            let completion = onStopped; onStopped = nil
            requestConnection = nil; connections.removeAll()
            completion?()
        }
    }
}
#endif
