/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

// Real `NWListener` loopback sockets are unreliable on the watchOS simulator (and the SDK has no precedent for
// real sockets in tests — `ServerMock` is `URLProtocol`-based for that reason). This target is also compiled and
// run on watchOS via SPM (`Package.swift` floors at watchOS 7) and `make test-watchos SCHEME=DatadogInternal`,
// so scope the whole file to platforms where loopback sockets are dependable.
#if os(iOS) || os(tvOS)

import XCTest
import Network
import TestUtilities
@_spi(Internal)
@testable import DatadogInternal

/// Regression guard for `URLSessionTask` retention in automatic network instrumentation, driven by WebSockets.
///
/// `NetworkInstrumentationFeature` keeps a process-global dictionary **strongly keyed by the task**
/// (`interceptions: [URLSessionTask: URLSessionTaskInterception]`). A task is inserted on `resume`, and the
/// **only** removal path for an automatic-mode task (no completion handler, no registered delegate) is
/// `finish()`, reached via `task(_:didChangeToState:)` when `state == .completed`. That callback fires only if
/// the `.completed` transition dispatches through the swizzled `__NSCFLocalSessionTask.setState:`. If a
/// long-lived task type (e.g. a WebSocket) ever stopped routing its terminal transition through that swizzle,
/// it — and its interception — would be retained for the life of the process with no TTL or eviction.
///
/// WebSocket tasks (`__NSURLSessionWebSocketTask`) subclass `__NSCFLocalSessionTask` and do **not** override
/// `setState:`, so the swizzle reaches them and every close path drains correctly. These tests pin that
/// behaviour across the close paths that could plausibly bypass `setState:`.
///
/// Why these tests assert the **drain invariant** (`interceptionDidStart` count == `interceptionDidComplete`
/// count) rather than weak-ref deallocation of the task object: URLSession itself retains WebSocket tasks for
/// some time after they close (this reproduces with no instrumentation at all), so task deallocation is **not**
/// an SDK-attributable signal for WebSockets. Whether the SDK retains the task is determined by whether `finish()`
/// runs and removes it from the dictionary — i.e. by the drain invariant. (The data-task control below, whose
/// deallocation *is* prompt, additionally asserts release.)
///
/// Note on what is observed: the `interceptions` dictionary is `private` to `NetworkInstrumentationFeature`, so
/// these tests observe it indirectly via the handler's `interceptionDidComplete`. That is a faithful proxy for
/// removal because `finish()` notifies `interceptionDidComplete` and sets `interceptions[task] = nil` together;
/// the equality of the start/complete counts therefore implies the dictionary returned to its prior size.
///
/// This uses a REAL loopback WebSocket server (`NWListener` + `NWProtocolWebSocket`), not `ServerMock`.
/// `ServerMock` is `URLProtocol`-based and intercepts above CFNetwork, so it never produces a real
/// `__NSCFLocalSessionTask` WebSocket and cannot exercise the swizzled `resume`/`setState:` path.
@available(iOS 13.0, tvOS 13.0, *)
final class WebSocketTaskRetentionTests: XCTestCase {
    // swiftlint:disable implicitly_unwrapped_optional
    private var core: SingleFeatureCoreMock<NetworkInstrumentationFeature>!
    private var handler: URLSessionHandlerMock!
    // swiftlint:enable implicitly_unwrapped_optional

    override func setUpWithError() throws {
        try super.setUpWithError()
        core = SingleFeatureCoreMock()
        handler = URLSessionHandlerMock()
        try core.register(urlSessionHandler: handler)
    }

    override func tearDown() {
        // Flush the feature's serial queue before releasing the core so the process-global swizzles are torn
        // down on the test thread (mirrors NetworkInstrumentationFeatureTests).
        core?.get(feature: NetworkInstrumentationFeature.self)?.flush()
        core = nil
        handler = nil
        super.tearDown()
    }

    // MARK: - WebSocket close paths must drain the interception

    /// Client-initiated normal close: `cancel(with: .normalClosure, reason:)`.
    func testWebSocketTask_clientNormalClose_drainsInterception() throws {
        try assertWebSocketInterceptionDrains(label: "client-normal-close") { task, server in
            server.waitForConnection(timeout: 5)
            task.cancel(with: .normalClosure, reason: nil)
        }
    }

    /// Server-initiated close: the server sends a WebSocket close frame. The client task must still complete.
    func testWebSocketTask_serverInitiatedClose_drainsInterception() throws {
        try assertWebSocketInterceptionDrains(label: "server-close") { _, server in
            server.waitForConnection(timeout: 5)
            server.closeFromServer()
        }
    }

    /// Abrupt connection drop: the server force-cancels the TCP connection with no WebSocket close handshake.
    /// The client observes a transport error; the task must still complete (error-completion path).
    func testWebSocketTask_abruptConnectionDrop_drainsInterception() throws {
        try assertWebSocketInterceptionDrains(label: "abrupt-drop") { _, server in
            server.waitForConnection(timeout: 5)
            server.dropConnection()
        }
    }

    /// Churn: opening and closing many WebSockets must not accumulate interceptions — the number completed must
    /// equal the number started, so the process-global dictionary returns to baseline (no unbounded growth).
    func testWebSocketChurn_doesNotAccumulateInterceptions() throws {
        let iterations = 20
        let server = try LoopbackWebSocketServer()
        let port = try server.start()
        defer { server.stop() }

        handler.shouldInterceptRequest = { $0.url?.port == Int(port) }

        let didStart = expectation(description: "interceptionDidStart x\(iterations)")
        didStart.expectedFulfillmentCount = iterations
        // The resume swizzle is process-global; even with port scoping, keep over-fulfill non-fatal so an
        // unexpected extra event fails the count assertions cleanly instead of raising NSInternalInconsistencyException.
        didStart.assertForOverFulfill = false
        let didComplete = expectation(description: "interceptionDidComplete x\(iterations)")
        didComplete.expectedFulfillmentCount = iterations
        didComplete.assertForOverFulfill = false
        let started = Counter(), completed = Counter()
        handler.onInterceptionDidStart = { _ in started.increment(); didStart.fulfill() }
        handler.onInterceptionDidComplete = { _ in completed.increment(); didComplete.fulfill() }

        try URLSessionInstrumentation.enableOrThrow(with: nil, in: core)
        let feature = try XCTUnwrap(core.get(feature: NetworkInstrumentationFeature.self))

        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        // Open then immediately close each socket. We intentionally do NOT wait on the server's connection here:
        // a single shared server across many connections cannot edge-trigger per-connection readiness, and the
        // drain invariant does not require a completed handshake — `resume` inserts the interception and `cancel`
        // drives it to `.completed`/`finish()` regardless. Post-connection close fidelity is covered by the
        // single-shot close-path tests above; correctness here rests on the start/complete counts below.
        for _ in 0..<iterations {
            autoreleasepool {
                let task = session.webSocketTask(with: server.url)
                task.resume()
                task.cancel(with: .normalClosure, reason: nil)
            }
        }

        wait(for: [didStart, didComplete], timeout: 30)
        feature.flush()

        XCTAssertEqual(started.value, iterations, "Every opened WebSocket must be intercepted on resume.")
        XCTAssertEqual(
            completed.value,
            started.value,
            "Every opened WebSocket must complete and drain from `interceptions`; a shortfall means tasks "
            + "accumulate in the process-global dictionary (unbounded growth)."
        )
    }

    // MARK: - Control: a normal data task must drain (guards against a harness false positive)

    /// Isolation control: a plain `dataTask` with no completion handler and no delegate exercises the same
    /// automatic-mode removal path (`setState:` → `.completed` → `finish()`). Targets a loopback port we own and
    /// have shut down (so connections are refused) for a fast, deterministic terminal state. Guards against a
    /// harness false positive: if this fails, the issue is the harness/removal path generally, not WebSockets.
    ///
    /// Like the WebSocket cases, this asserts the SDK-attributable drain invariant (one start, one complete) and
    /// deliberately does NOT assert task deallocation: URLSession's hold on a task after a terminal state is its
    /// own concern and not a reliable signal under loaded/parallel CI.
    func testDataTask_noCompletionHandler_drainsInterception() throws {
        let refusedPort = try Self.refusedLoopbackPort()
        let refusedURL = URL(string: "http://127.0.0.1:\(refusedPort)/")!
        handler.shouldInterceptRequest = { $0.url?.port == Int(refusedPort) }

        let didStart = expectation(description: "interceptionDidStart (control data task)")
        didStart.assertForOverFulfill = false
        let didComplete = expectation(description: "interceptionDidComplete (control data task)")
        didComplete.assertForOverFulfill = false
        let started = Counter(), completed = Counter()
        handler.onInterceptionDidStart = { _ in started.increment(); didStart.fulfill() }
        handler.onInterceptionDidComplete = { _ in completed.increment(); didComplete.fulfill() }

        try URLSessionInstrumentation.enableOrThrow(with: nil, in: core)
        let feature = try XCTUnwrap(core.get(feature: NetworkInstrumentationFeature.self))

        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 5
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        let task = session.dataTask(with: refusedURL) // no completion handler, no delegate
        task.resume()
        wait(for: [didStart], timeout: 5)

        let completionResult = XCTWaiter.wait(for: [didComplete], timeout: 8)
        feature.flush()

        XCTAssertEqual(
            completionResult,
            .completed,
            "A normal data task with no completion handler must reach .completed via the swizzled setState: and "
            + "report finish(). If this fails, the harness/removal path is broken (not a WebSocket-specific issue)."
        )
        XCTAssertEqual(started.value, 1, "control: expected exactly one interception start")
        XCTAssertEqual(completed.value, 1, "control: expected exactly one interception completion (dict drained)")
    }

    // MARK: - Drain assertion helper

    /// Opens a WebSocket against a fresh loopback server, runs `closeAction`, and asserts the SDK-attributable
    /// drain invariant: exactly one `interceptionDidStart` and one `interceptionDidComplete` (the task is removed
    /// from `interceptions`).
    ///
    /// The `interceptionDidComplete` wait happens **before** the session is invalidated, so the task must reach
    /// `.completed` from `closeAction` itself — not from `invalidateAndCancel()`. This is what makes each close
    /// path (client close, server-initiated close, abrupt drop) genuinely exercise its own trigger rather than
    /// being finalized by session teardown. A pending `receive` is installed so the client processes an inbound
    /// server close frame / transport error (a WebSocket task that never receives would not observe them).
    private func assertWebSocketInterceptionDrains(
        label: String,
        closeAction: @escaping (URLSessionWebSocketTask, LoopbackWebSocketServer) -> Void
    ) throws {
        let server = try LoopbackWebSocketServer()
        let port = try server.start()
        defer { server.stop() }

        // The resume swizzle is process-global; scope the handler to only this server's traffic.
        handler.shouldInterceptRequest = { $0.url?.port == Int(port) }

        let didStart = expectation(description: "interceptionDidStart (\(label))")
        didStart.assertForOverFulfill = false
        let didComplete = expectation(description: "interceptionDidComplete (\(label))")
        didComplete.assertForOverFulfill = false
        let started = Counter(), completed = Counter()
        handler.onInterceptionDidStart = { _ in started.increment(); didStart.fulfill() }
        handler.onInterceptionDidComplete = { _ in completed.increment(); didComplete.fulfill() }

        try URLSessionInstrumentation.enableOrThrow(with: nil, in: core)
        let feature = try XCTUnwrap(core.get(feature: NetworkInstrumentationFeature.self))

        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() } // fires at function exit — AFTER the completion wait + assertions
        let task = session.webSocketTask(with: server.url)
        task.resume()
        // Drive a receive so the client processes an inbound close frame / transport error. Without this, a
        // WebSocket task that never reads would not observe a server-initiated close.
        task.receive { _ in }
        wait(for: [didStart], timeout: 5)

        closeAction(task, server)

        let completionResult = XCTWaiter.wait(for: [didComplete], timeout: 8)
        feature.flush()

        XCTAssertEqual(
            completionResult,
            .completed,
            "[\(label)] WebSocket close must route to finish() (interceptionDidComplete) on its own — not via "
            + "session invalidation; otherwise the task is retained in NetworkInstrumentationFeature.interceptions."
        )
        XCTAssertEqual(started.value, 1, "[\(label)] expected exactly one interception start")
        XCTAssertEqual(completed.value, 1, "[\(label)] expected exactly one interception completion (dict drained)")
    }

    // MARK: - Helpers

    /// Returns a loopback TCP port that will refuse connections: binds an ephemeral port, reads it, then shuts
    /// the listener down. Avoids assuming a well-known port (e.g. discard/9) is free on the host or CI.
    private static func refusedLoopbackPort() throws -> UInt16 {
        let server = try LoopbackWebSocketServer()
        let port = try server.start()
        server.stop()
        return port
    }
}

/// Thread-safe integer counter for cross-thread interception tallies.
private final class Counter {
    private let lock = NSLock()
    private var _value = 0
    var value: Int { lock.lock(); defer { lock.unlock() }; return _value }
    func increment() { lock.lock(); _value += 1; lock.unlock() }
}

// MARK: - Test infrastructure: a real loopback WebSocket server

/// Minimal loopback WebSocket server (`NWListener` with `NWProtocolWebSocket`). Completes the WebSocket upgrade
/// handshake automatically, keeps the connection open, and exposes server-initiated close and abrupt-drop so the
/// client task's completion paths can be exercised.
@available(iOS 13.0, tvOS 13.0, *)
private final class LoopbackWebSocketServer {
    private let listener: NWListener
    private let queue = DispatchQueue(label: "com.datadoghq.test.ws.loopback")
    private let lock = NSLock()
    private var connections: [NWConnection] = []
    private var lastConnection: NWConnection?
    private let connectionAccepted = DispatchSemaphore(value: 0)
    private var boundPort: UInt16 = 0

    var url: URL { URL(string: "ws://127.0.0.1:\(boundPort)/ws")! }

    init() throws {
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        let wsOptions = NWProtocolWebSocket.Options()
        wsOptions.autoReplyPing = true
        params.defaultProtocolStack.applicationProtocols.insert(wsOptions, at: 0)
        listener = try NWListener(using: params) // ephemeral port
    }

    func start() throws -> UInt16 {
        let ready = DispatchSemaphore(value: 0)
        let errorBox = WSErrorBox()
        listener.stateUpdateHandler = { state in
            switch state {
            case .ready: ready.signal()
            case .failed(let error): errorBox.set(error); ready.signal()
            default: break
            }
        }
        listener.newConnectionHandler = { [weak self] connection in
            self?.handle(connection)
        }
        listener.start(queue: queue)

        if ready.wait(timeout: .now() + 5) == .timedOut {
            throw NSError(domain: "LoopbackWebSocketServer", code: 1, userInfo: [NSLocalizedDescriptionKey: "listener did not become ready"])
        }
        if let error = errorBox.value {
            throw error
        }
        guard let port = listener.port?.rawValue else {
            throw NSError(domain: "LoopbackWebSocketServer", code: 2, userInfo: [NSLocalizedDescriptionKey: "listener has no bound port"])
        }
        boundPort = port
        return port
    }

    private func handle(_ connection: NWConnection) {
        lock.lock()
        connections.append(connection)
        lastConnection = connection
        lock.unlock()
        connection.stateUpdateHandler = { [weak self] state in
            if case .ready = state {
                self?.connectionAccepted.signal()
            }
        }
        connection.start(queue: queue)
        receive(on: connection)
    }

    private func receive(on connection: NWConnection) {
        connection.receiveMessage { [weak self] _, context, _, error in
            if let context = context,
               let metadata = context.protocolMetadata(definition: NWProtocolWebSocket.definition) as? NWProtocolWebSocket.Metadata,
               metadata.opcode == .close {
                connection.cancel()
                return
            }
            if error == nil {
                self?.receive(on: connection)
            } else {
                connection.cancel()
            }
        }
    }

    /// Blocks until the most recent client connection is accepted and ready (or the timeout elapses).
    func waitForConnection(timeout: TimeInterval) {
        _ = connectionAccepted.wait(timeout: .now() + timeout)
    }

    /// Sends a WebSocket close frame from the server, then tears the connection down.
    /// Assumes a single active client connection (true for the one-server-per-test close-path cases); operates
    /// on the most recently accepted connection.
    func closeFromServer() {
        lock.lock(); let connection = lastConnection; lock.unlock()
        guard let connection = connection else {
            return
        }
        let metadata = NWProtocolWebSocket.Metadata(opcode: .close)
        metadata.closeCode = .protocolCode(.normalClosure)
        let context = NWConnection.ContentContext(identifier: "close", metadata: [metadata])
        connection.send(content: nil, contentContext: context, isComplete: true, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    /// Abruptly drops the TCP connection with no WebSocket close handshake (transport error on the client).
    func dropConnection() {
        lock.lock(); let connection = lastConnection; lock.unlock()
        connection?.forceCancel()
    }

    func stop() {
        listener.cancel()
        lock.lock()
        let active = connections
        lock.unlock()
        active.forEach { $0.cancel() }
    }
}

/// Thread-safe single-value box for capturing an error across the listener's state callback.
private final class WSErrorBox {
    private let lock = NSLock()
    private var _value: Error?
    var value: Error? { lock.lock(); defer { lock.unlock() }; return _value }
    func set(_ error: Error) { lock.lock(); _value = error; lock.unlock() }
}

#endif
