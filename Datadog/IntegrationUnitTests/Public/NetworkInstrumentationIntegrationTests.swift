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

#if os(iOS)
import Network

final class URLSessionResourceCompletionTests: XCTestCase {
    @MainActor
    func testWhenResponseBodyIsMissing_itReportsNetworkError() throws {
        try runTransfer(.missingBody)
    }

    @MainActor
    func testWhenResponseBodyIsIncomplete_itReportsNetworkError() throws {
        try runTransfer(.partialBody)
    }

    @MainActor
    func testWhenResponseBodyCompletes_itReportsResource() throws {
        try runTransfer(.complete)
    }

    @MainActor
    func testWhenHEADResponseSucceeds_itReportsEmptyResource() throws {
        try runTransfer(.head)
    }

    @MainActor
    func testWhenResponseHasNoContent_itReportsEmptyResource() throws {
        try runTransfer(.noContent)
    }

    @MainActor
    func testWhenConnectionClosesBeforeResponse_itReportsNetworkError() throws {
        try runTransfer(.noResponse)
    }

    @MainActor
    func testWhenResponseBodyFailsAfterNavigation_itKeepsStartingView() throws {
        try runTransfer(.partialBody, transition: .view)
    }

    @MainActor
    func testWhenResponseBodyFailsAfterSessionStop_itKeepsStartingSessionAndView() throws {
        try runTransfer(.partialBody, transition: .session)
    }

    @MainActor
    func testWhenHTTPErrorResponseCompletes_itReportsResource() throws {
        try runTransfer(.httpError)
    }

    private enum Transition { case none, view, session }

    @MainActor
    private func runTransfer(_ mode: ControlledHTTPResponseServer.Mode, transition: Transition = .none) throws {
        XCTAssertTrue(Thread.isMainThread)
        let ready = expectation(description: "local listener ready")
        let requestReceived = expectation(description: "native request received")
        let headersWritten = mode == .noResponse ? nil : expectation(description: "HTTP headers written")
        let server = try ControlledHTTPResponseServer(mode: mode, ready: ready, requestReceived: requestReceived, headersWritten: headersWritten)
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
        RUM.enable(with: .init(applicationID: "resource-transfer", urlSessionTracking: .init(), trackFrustrations: true), in: core)
        URLSessionInstrumentation.enableDurationBreakdown(with: .init(delegateClass: ResourceTransferDelegateSpy.self), in: core)
        let monitor = RUMMonitor.shared(in: core)
        monitor.startView(key: "transfer-owner", name: "Transfer Owner")
        monitor.startAction(type: .tap, name: "Transfer Action")
        core.flush()
        let owner = try rumContext(core)
        let completed = expectation(description: "URLSession native completion")
        let invalidated = expectation(description: "URLSession invalidation")
        let headers = mode == .noResponse ? nil : expectation(description: "URLSession received HTTP headers")
        let firstData = mode.body.isEmpty ? nil : expectation(description: "URLSession received initial body byte")
        let delegate = ResourceTransferDelegateSpy(headers: headers, firstData: firstData, completed: completed, invalidated: invalidated)
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

private final class ResourceTransferDelegateSpy: NSObject, URLSessionDataDelegate {
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

private final class ControlledHTTPResponseServer {
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
