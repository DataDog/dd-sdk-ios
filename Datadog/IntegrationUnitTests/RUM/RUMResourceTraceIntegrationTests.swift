/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
@_spi(Internal)
import DatadogInternal
import TestUtilities
@testable import DatadogCore
@testable import DatadogRUM
@testable import DatadogTrace

class RUMResourceTraceIntegrationTests: RUMSessionTestsBase {
    private var core: DatadogCoreProxy! // swiftlint:disable:this implicitly_unwrapped_optional

    override func setUp() {
        super.setUp()
        core = DatadogCoreProxy()
    }

    override func tearDownWithError() throws {
        try core.flushAndTearDown()
        core = nil
        super.tearDown()
    }

    func testNoActiveSpan_traceSampled_sessionSampled_requestSampled() throws {
        let span = prepare(activeSpan: false, spanSampled: true, sessionSampled: true, urlSessionTrackingSampled: true)
        try performRequestAndVerifyIfSampled(.rum, span: span)
    }

    func testNoActiveSpan_traceSampled_sessionSampled_requestNotSampled() throws {
        let span = prepare(activeSpan: false, spanSampled: true, sessionSampled: true, urlSessionTrackingSampled: false)
        try performRequestAndVerifyIfSampled(.sessionSampledRequestNotSampled, span: span)
    }

    func testNoActiveSpan_traceSampled_sessionNotSampled_requestSampled() throws {
        let span = prepare(activeSpan: false, spanSampled: true, sessionSampled: false, urlSessionTrackingSampled: true)
        try performRequestAndVerifyIfSampled(.sessionNotSampled, span: span)
    }

    func testNoActiveSpan_traceSampled_sessionNotSampled_requestNotSampled() throws {
        let span = prepare(activeSpan: false, spanSampled: true, sessionSampled: false, urlSessionTrackingSampled: false)
        try performRequestAndVerifyIfSampled(.sessionNotSampled, span: span)
    }

    func testNoActiveSpan_traceNotSampled_sessionSampled_requestSampled() throws {
        let span = prepare(activeSpan: false, spanSampled: false, sessionSampled: true, urlSessionTrackingSampled: true)
        try performRequestAndVerifyIfSampled(.rum, span: span)
    }

    func testNoActiveSpan_traceNotSampled_sessionSampled_requestNotSampled() throws {
        let span = prepare(activeSpan: false, spanSampled: false, sessionSampled: true, urlSessionTrackingSampled: false)
        try performRequestAndVerifyIfSampled(.sessionSampledRequestNotSampled, span: span)
    }

    func testNoActiveSpan_traceNotSampled_sessionNotSampled_requestSampled() throws {
        let span = prepare(activeSpan: false, spanSampled: false, sessionSampled: false, urlSessionTrackingSampled: true)
        try performRequestAndVerifyIfSampled(.sessionNotSampled, span: span)
    }

    func testNoActiveSpan_traceNotSampled_sessionNotSampled_requestNotSampled() throws {
        let span = prepare(activeSpan: false, spanSampled: false, sessionSampled: false, urlSessionTrackingSampled: false)
        try performRequestAndVerifyIfSampled(.sessionNotSampled, span: span)
    }

    func testActiveSpan_traceSampled_sessionSampled_requestSampled() throws {
        let span = prepare(activeSpan: true, spanSampled: true, sessionSampled: true, urlSessionTrackingSampled: true)
        try performRequestAndVerifyIfSampled(.activeSpan, span: span)
    }

    func testActiveSpan_traceSampled_sessionSampled_requestNotSampled() throws {
        let span = prepare(activeSpan: true, spanSampled: true, sessionSampled: true, urlSessionTrackingSampled: false)
        try performRequestAndVerifyIfSampled(.activeSpan, span: span)
    }

    func testActiveSpan_traceSampled_sessionNotSampled_requestSampled() throws {
        let span = prepare(activeSpan: true, spanSampled: true, sessionSampled: false, urlSessionTrackingSampled: true)
        try performRequestAndVerifyIfSampled(.sessionNotSampled, span: span)
    }

    func testActiveSpan_traceSampled_sessionNotSampled_requestNotSampled() throws {
        let span = prepare(activeSpan: true, spanSampled: true, sessionSampled: false, urlSessionTrackingSampled: false)
        try performRequestAndVerifyIfSampled(.sessionNotSampled, span: span)
    }

    func testActiveSpan_traceNotSampled_sessionSampled_requestSampled() throws {
        let span = prepare(activeSpan: true, spanSampled: false, sessionSampled: true, urlSessionTrackingSampled: true)
        try performRequestAndVerifyIfSampled(.rum, span: span)
    }

    func testActiveSpan_traceNotSampled_sessionSampled_requestNotSampled() throws {
        let span = prepare(activeSpan: true, spanSampled: false, sessionSampled: true, urlSessionTrackingSampled: false)
        try performRequestAndVerifyIfSampled(.sessionSampledRequestNotSampled, span: span)
    }

    func testActiveSpan_traceNotSampled_sessionNotSampled_requestSampled() throws {
        let span = prepare(activeSpan: true, spanSampled: false, sessionSampled: false, urlSessionTrackingSampled: true)
        try performRequestAndVerifyIfSampled(.sessionNotSampled, span: span)
    }

    func testActiveSpan_traceNotSampled_sessionNotSampled_requestNotSampled() throws {
        let span = prepare(activeSpan: true, spanSampled: false, sessionSampled: false, urlSessionTrackingSampled: false)
        try performRequestAndVerifyIfSampled(.sessionNotSampled, span: span)
    }

    #if os(iOS)
    func testTraceSurvivesRejectedSceneResource_whenTraceRegistersFirst() throws {
        try assertStandaloneTraceWhenRUMRejectsResource(traceFirst: true)
    }

    func testTraceSurvivesRejectedSceneResource_whenRUMRegistersFirst() throws {
        try assertStandaloneTraceWhenRUMRejectsResource(traceFirst: false)
    }

    @MainActor
    func testTraceFallsBackWhenQueuedRUMReservationRejectsTheCapturedView() async throws {
        guard #available(iOS 27.0, *) else { throw XCTSkip("Scene request capture requires iOS 27") }
        try await assertTraceResourceStartOutcome(stopsViewFirst: true)
    }

    @MainActor
    func testTraceDoesNotDuplicateACommittedRUMResourceAfterTheViewStops() async throws {
        guard #available(iOS 27.0, *) else { throw XCTSkip("Scene request capture requires iOS 27") }
        try await assertTraceResourceStartOutcome(stopsViewFirst: false)
    }

    @available(iOS 27.0, *)
    @MainActor
    private func assertTraceResourceStartOutcome(stopsViewFirst: Bool) async throws {
        let url = try XCTUnwrap(URL(string: "https://www.example.com/captured-view-request"))
        let hosts: [String: Set<TracingHeaderType>] = ["www.example.com": [.datadog]]
        let intake = HTTPClientMock()
        let root = obtainUniqueTemporaryDirectory()
        let sdkDirectory = root.appendingPathComponent("sdk", isDirectory: true)
        try FileManager.default.createDirectory(at: sdkDirectory, withIntermediateDirectories: true)
        let core = DatadogCore(
            directory: .init(osDirectory: .init(url: root), coreDirectory: .init(url: sdkDirectory)),
            dateProvider: SystemDateProvider(),
            initialConsent: .granted,
            performance: .mockAny(),
            httpClient: intake,
            encryption: nil,
            contextProvider: .mockAny(),
            applicationVersion: .mockAny(),
            maxBatchesPerUpload: 1,
            backgroundTasksEnabled: false
        )
        defer {
            core.stop()
            try? FileManager.default.removeItem(at: root)
        }
        let date = Date()
        core.contextProvider.write {
            $0 = .mockWith(
                sdkInitDate: date,
                trackingConsent: .granted,
                launchInfo: .mockWith(launchReason: .userLaunch, processLaunchDate: date),
                applicationStateHistory: .mockWith(initialState: .active, date: date)
            )
        }
        core.flush()
        let feature = try enableFirstPartyTracing(hosts: hosts, trackRUMResources: true, in: core)
        Trace.enable(with: Trace.Configuration(urlSessionTracking: .init(
            firstPartyHostsTracing: .traceWithHeaders(hostsWithHeaders: hosts, sampleRate: 100)
        )), in: core)
        let monitor = feature.monitor
        monitor.startView(key: "source", name: "Source", attributes: [:])
        core.flush()
        let source = try XCTUnwrap(monitor.rumContextSnapshot(for: .processRepresentative))
        let sourceViewID = try XCTUnwrap(source.viewID)
        let owner = try XCTUnwrap(feature.rumContextHandoffOwner)
        let captured = RUMContextHandoff.CurrentValue(
            rumContext: source, sceneIdentifier: nil, hasPendingUserAction: false, excludedUserActionID: nil
        )

        let entered = DispatchSemaphore(value: 0)
        let release = DispatchSemaphore(value: 0)
        defer { release.signal() }
        core.contextProvider.write { _ in
            entered.signal()
            release.wait()
        }
        guard entered.wait(timeout: .now() + 5) == .success else {
            return XCTFail("Could not hold the Core context queue")
        }
        if stopsViewFirst {
            monitor.stopView(key: "source", attributes: [:])
            monitor.startView(key: "peer", name: "Peer", attributes: [:])
        }

        let server = ServerMock(delivery: .success(response: .mockResponseWith(statusCode: 200), data: Data()))
        let session = server.getInterceptedURLSession()
        let request = RUMContextHandoff.withValue(captured, for: owner) {
            Task {
                XCTAssertEqual(RUMContextHandoff.current(for: owner)?.rumContext?.viewID, sourceViewID)
                return try await session.data(for: URLRequest(url: url, timeoutInterval: 5))
            }
        }
        let (_, response) = try await request.value
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
        let wire = try XCTUnwrap(server.waitAndReturnRequests(count: 1).first)
        let wireTraceID = try XCTUnwrap(wire.value(forHTTPHeaderField: "x-datadog-trace-id"))
        let wireSpanID = try XCTUnwrap(wire.value(forHTTPHeaderField: "x-datadog-parent-id"))

        if !stopsViewFirst {
            monitor.stopView(key: "source", attributes: [:])
        }
        release.signal()
        core.flushAndUpload()

        let rows = try intake.requestsSent().flatMap { request -> [[String: Any]] in
            guard let path = request.url?.path, path.hasSuffix("/rum") || path.hasSuffix("/spans"),
                  let body = try request.decompressed().httpBody else {
                return []
            }
            return try body.split(separator: 0x0A).compactMap {
                try JSONSerialization.jsonObject(with: Data($0)) as? [String: Any]
            }
        }
        XCTAssertTrue(rows.contains { ($0["view"] as? [String: Any])?["id"] as? String == sourceViewID })
        let resources = rows.filter {
            $0["type"] as? String == "resource" && ($0["resource"] as? [String: Any])?["url"] as? String == url.absoluteString
        }
        let spans = rows.flatMap { $0["spans"] as? [[String: Any]] ?? [] }
            .filter { $0["name"] as? String == "urlsession.request" && $0["resource"] as? String == url.absoluteString }

        if stopsViewFirst {
            XCTAssertTrue(resources.isEmpty)
            XCTAssertEqual(spans.count, 1)
            let span = try XCTUnwrap(spans.first)
            let trace = try XCTUnwrap(span["trace_id"] as? String)
            let spanID = try XCTUnwrap(span["span_id"] as? String)
            XCTAssertEqual(UInt64(trace, radix: 16).map { String($0) }, wireTraceID)
            XCTAssertEqual(UInt64(spanID, radix: 16).map { String($0) }, wireSpanID)
            XCTAssertNotNil(span["meta.tracer.version"])
            XCTAssertNil(span["meta.\(SpanTags.rumSessionID)"])
            XCTAssertNil(span["meta.\(SpanTags.rumViewID)"])
            XCTAssertNil(span["meta.\(SpanTags.rumActionID)"])
        } else {
            XCTAssertTrue(spans.isEmpty)
            XCTAssertEqual(resources.count, 1)
            let resource = try XCTUnwrap(resources.first)
            XCTAssertEqual((resource["view"] as? [String: Any])?["id"] as? String, sourceViewID)
        }
    }

    func testTraceBaggageKeepsTheCapturedSessionAfterRollover() throws {
        try assertBaggageKeepsCapturedSessionAfterRollover(trackRUMResources: false)
    }

    func testRUMResourceBaggageKeepsTheCapturedSessionAfterRollover() throws {
        try assertBaggageKeepsCapturedSessionAfterRollover(trackRUMResources: true)
    }

    private func assertBaggageKeepsCapturedSessionAfterRollover(trackRUMResources: Bool) throws {
        guard #available(iOS 27.0, *) else { throw XCTSkip("Scene request capture requires iOS 27") }
        let hosts: [String: Set<TracingHeaderType>] = ["datadog.example.com": [.datadog], "w3c.example.com": [.tracecontext]]
        // The proxy's FeatureScope does not implement captured Resource preparation.
        let root = obtainUniqueTemporaryDirectory()
        let sdkDirectory = root.appendingPathComponent("sdk", isDirectory: true)
        try FileManager.default.createDirectory(at: sdkDirectory, withIntermediateDirectories: true)
        let directory = CoreDirectory(osDirectory: .init(url: root), coreDirectory: .init(url: sdkDirectory))
        let real = DatadogCore(
            directory: directory,
            dateProvider: SystemDateProvider(),
            initialConsent: .granted,
            performance: .mockAny(),
            httpClient: HTTPClientMock(),
            encryption: nil,
            contextProvider: .mockAny(),
            applicationVersion: .mockAny(),
            maxBatchesPerUpload: 1,
            backgroundTasksEnabled: false
        )
        defer {
            real.flushAndTearDown()
            try? FileManager.default.removeItem(at: root)
        }
        let feature = try enableFirstPartyTracing(hosts: hosts, trackRUMResources: trackRUMResources, in: real)
        let owner = try XCTUnwrap(feature.rumContextHandoffOwner)
        let monitor = feature.monitor
        monitor.startView(key: "previous", name: "Previous", attributes: [:])
        real.flush()
        let previous = try XCTUnwrap(monitor.rumContextSnapshot(for: .processRepresentative))
        XCTAssertNotNil(previous.viewID)
        XCTAssertTrue(previous.sessionSampler.isSampled)
        monitor.stopSession()
        monitor.startView(key: "current", name: "Current", attributes: [:])
        real.flush()
        let current = try XCTUnwrap(feature.decision(for: .combinedWithSessionRate, rate: 100))
        XCTAssertNotEqual(previous.sessionID, current.sessionID)

        let capture = RUMContextHandoff.CurrentValue(
            rumContext: previous,
            sceneIdentifier: nil,
            hasPendingUserAction: false,
            excludedUserActionID: nil
        )
        for (host, traceHeader) in [("datadog.example.com", "x-datadog-trace-id"), ("w3c.example.com", "traceparent")] {
            let url = try XCTUnwrap(URL(string: "https://\(host)/captured"))
            let request = try RUMContextHandoff.withValue(capture, for: owner) {
                try sendURLSessionRequest(to: url)
            }
            XCTAssertEqual(request.value(forHTTPHeaderField: "baggage"), "session.id=\(previous.sessionID)")
            XCTAssertNotNil(request.value(forHTTPHeaderField: traceHeader))
        }
    }

    func testTraceWithEmptyCaptureOmitsRUMSessionButUnscopedRequestsUseTheStore() throws {
        guard #available(iOS 27.0, *) else { throw XCTSkip("Scene request capture requires iOS 27") }
        let feature = try enableFirstPartyTracing(hosts: ["www.example.com": [.tracecontext]], trackRUMResources: false, in: core)
        let owner = try XCTUnwrap(feature.rumContextHandoffOwner)
        feature.monitor.startView(key: "live", name: "Live", attributes: [:])
        core.flush()
        let current = try XCTUnwrap(feature.decision(for: .combinedWithSessionRate, rate: 100))
        let url = try XCTUnwrap(URL(string: "https://www.example.com/empty-capture"))
        let capture = RUMContextHandoff.CurrentValue(
            rumContext: nil,
            sceneIdentifier: "empty",
            hasPendingUserAction: false,
            excludedUserActionID: nil
        )
        let scopedRequest = try RUMContextHandoff.withValue(capture, for: owner) {
            try sendURLSessionRequest(to: url)
        }
        XCTAssertNil(scopedRequest.value(forHTTPHeaderField: "baggage"))
        XCTAssertNotNil(scopedRequest.value(forHTTPHeaderField: "traceparent"))

        let unscopedRequest = try sendURLSessionRequest(to: url)
        XCTAssertEqual(unscopedRequest.value(forHTTPHeaderField: "baggage"), "session.id=\(current.sessionID)")
        XCTAssertNotNil(unscopedRequest.value(forHTTPHeaderField: "traceparent"))
    }

    private func enableFirstPartyTracing(
        hosts: [String: Set<TracingHeaderType>],
        trackRUMResources: Bool,
        in core: DatadogCoreProtocol
    ) throws -> RUMFeature {
        var config = RUM.Configuration(applicationID: .mockAny())
        // Register one network handler so the observed header has an unambiguous source.
        if trackRUMResources {
            config.urlSessionTracking = .init(firstPartyHostsTracing: .traceWithHeaders(hostsWithHeaders: hosts, sampleRate: 100))
        } else {
            Trace.enable(with: Trace.Configuration(urlSessionTracking: .init(
                firstPartyHostsTracing: .traceWithHeaders(hostsWithHeaders: hosts, sampleRate: 100)
            )), in: core)
        }
        config.bundle = .mockWith(UIApplicationSceneManifest: ["UIApplicationSupportsMultipleScenes": true])
        config.featureFlags = [.multiSceneTracking: true]
        config.longTaskThreshold = nil
        config.appHangThreshold = nil
        try RUM.enableOrThrow(with: config, in: core)
        return try XCTUnwrap(core.get(feature: RUMFeature.self))
    }

    func testTraceIgnoresRUMModifierRegisteredAfterPreparationStarted() throws {
        let lateModifier = RequestModifier(header: "x-late-modifier")
        let preparedModifier = RequestModifier(header: "x-prepared-modifier") { [weak core] in
            do {
                try XCTUnwrap(core).register(urlSessionHandler: lateModifier)
            } catch {
                XCTFail("Could not register modifier during request preparation: \(error)")
            }
        }
        let request = try assertStandaloneTraceWhenRUMRejectsResource(traceFirst: true, modifier: preparedModifier)
        XCTAssertEqual(request.value(forHTTPHeaderField: "x-prepared-modifier"), "set")
        XCTAssertNil(request.value(forHTTPHeaderField: "x-late-modifier"))
    }

    @discardableResult
    private func assertStandaloneTraceWhenRUMRejectsResource(
        traceFirst: Bool,
        modifier: RequestModifier? = nil
    ) throws -> URLRequest {
        guard #available(iOS 27.0, *) else { throw XCTSkip("Scene request capture requires iOS 27") }
        let hosts: [String: Set<TracingHeaderType>] = ["www.example.com": [.datadog, .tracecontext]]
        let traceConfig = Trace.Configuration(urlSessionTracking: .init(
            firstPartyHostsTracing: .traceWithHeaders(hostsWithHeaders: hosts, sampleRate: 100)
        ))
        var rumConfig = RUM.Configuration(
            applicationID: .mockAny(),
            urlSessionTracking: .init(firstPartyHostsTracing: .traceWithHeaders(hostsWithHeaders: hosts, sampleRate: 100))
        )
        rumConfig.bundle = .mockWith(UIApplicationSceneManifest: ["UIApplicationSupportsMultipleScenes": true])
        rumConfig.featureFlags = [.multiSceneTracking: true]
        rumConfig.longTaskThreshold = nil
        rumConfig.appHangThreshold = nil
        if traceFirst {
            Trace.enable(with: traceConfig, in: core)
            try RUM.enableOrThrow(with: rumConfig, in: core)
        } else {
            try RUM.enableOrThrow(with: rumConfig, in: core)
            Trace.enable(with: traceConfig, in: core)
        }
        if let modifier {
            try core.register(urlSessionHandler: modifier)
        }
        core.flush()

        let feature = try XCTUnwrap(core.get(feature: RUMFeature.self))
        let owner = try XCTUnwrap(feature.rumContextHandoffOwner)
        let context = RUMContextHandoff.CurrentValue(
            rumContext: nil,
            sceneIdentifier: "empty",
            hasPendingUserAction: false,
            excludedUserActionID: nil
        )
        let url = try XCTUnwrap(URL(string: "https://www.example.com/no-native-view"))
        let request = try RUMContextHandoff.withValue(context, for: owner) {
            try sendURLSessionRequest(to: url)
        }

        XCTAssertNil(request.value(forHTTPHeaderField: "x-datadog-origin"))
        XCTAssertNotNil(request.value(forHTTPHeaderField: "x-datadog-trace-id"))
        XCTAssertNotNil(request.value(forHTTPHeaderField: "traceparent"))
        XCTAssertFalse(request.value(forHTTPHeaderField: "tracestate")?.contains("o:rum") ?? false)

        let spans = try core.waitAndReturnSpanMatchers()
        XCTAssertEqual(try spans.map { try $0.operationName() }, ["urlsession.request"])
        let rumEvents = try core.waitAndReturnRUMEventMatchers()
        XCTAssertFalse(try rumEvents.contains { try $0.eventType() == "resource" })
        return request
    }

    private final class RequestModifier: DatadogURLSessionHandler, DatadogURLSessionHandlerPreparingRUM {
        let firstPartyHosts = FirstPartyHosts()
        private let header: String
        private let onPrepare: () -> Void

        init(header: String, onPrepare: @escaping () -> Void = {}) {
            self.header = header
            self.onPrepare = onPrepare
        }

        func prepareRUMResource(capturing context: RUMURLSessionContext, reusing preparation: RUMURLSessionPreparation?) -> RUMURLSessionPreparation {
            onPrepare()
            return .init(identifier: nil, capturedState: context)
        }

        func modify(request: URLRequest, headerTypes: Set<TracingHeaderType>, networkContext: NetworkContext?) -> (URLRequest, TraceContext?, URLSessionHandlerCapturedState?) {
            var request = request
            request.setValue("set", forHTTPHeaderField: header)
            return (request, nil, nil)
        }

        func interceptionDidStart(interception: URLSessionTaskInterception, capturedStates: [any URLSessionHandlerCapturedState]) {
        }

        func interceptionDidComplete(interception: URLSessionTaskInterception) {
        }
    }
    #endif

    private func prepare(activeSpan: Bool, spanSampled: Bool, sessionSampled: Bool, urlSessionTrackingSampled: Bool) -> OTSpan {
        Trace.enable(
            with: Trace.Configuration(sampleRate: spanSampled ? 90 : 5),
            in: core
        )

        var config = RUM.Configuration(
            applicationID: .mockAny(),
            sessionSampleRate: sessionSampled ? 80 : 20,
            urlSessionTracking: .init(
                firstPartyHostsTracing: .trace(
                    hosts: ["www.example.com"],
                    sampleRate: urlSessionTrackingSampled ? 70 : 10
                )
            )
        )
        // This session ID is not sampled at 50%, but it is sampled at 60%.
        config.uuidGenerator = RUMUUIDGeneratorMock(uuid: RUMUUID(rawValue: UUID(uuidString: "c5b3c4ab-fa4a-4de9-8199-a522131ec48a")!))
        RUM.enable(with: config, in: core)

        // We need to wait for all the messages between features to stabilize so we have everything setup correctly.
        core.flush()

        let span = Tracer.shared(in: core).startRootSpan(operationName: "test-op")
        if activeSpan {
            span.setActive()
        }
        return span
    }

    enum SamplingExpectation {
        case activeSpan
        case rum
        case sessionNotSampled
        case sessionSampledRequestNotSampled
    }

    private func performRequestAndVerifyIfSampled(_ expectation: SamplingExpectation, span: OTSpan) throws {
        let request = try sendURLSessionRequest(to: URL.mockAny())
        let matchers = try core.waitAndReturnRUMEventMatchers()
        let possibleResourceMatcher = try matchers.first(where: { try $0.eventType() == "resource" })

        if expectation == .sessionNotSampled {
            XCTAssertNil(possibleResourceMatcher)
            return
        }

        let resourceMatcher = try XCTUnwrap(possibleResourceMatcher)

        if expectation == .sessionSampledRequestNotSampled {
            XCTAssertNil(request.value(forHTTPHeaderField: "x-datadog-parent-id"))
            XCTAssertNil(request.value(forHTTPHeaderField: "x-datadog-trace-id"))
            XCTAssertNil(request.value(forHTTPHeaderField: "x-datadog-sampling-priority"))
            XCTAssertNil(request.value(forHTTPHeaderField: "traceparent"))
            return
        }

        let spanIDString: String = try XCTUnwrap(resourceMatcher.attribute(forKeyPath: "_dd.span_id"))
        let spanID = SpanID(spanIDString, representation: .decimal)
        let traceIDString: String = try XCTUnwrap(resourceMatcher.attribute(forKeyPath: "_dd.trace_id"))
        let traceID = TraceID(traceIDString, representation: .hexadecimal)
        let sessionSampleRate: Float = try XCTUnwrap(resourceMatcher.attribute(forKeyPath: "_dd.configuration.session_sample_rate"))
        let spanDD = try XCTUnwrap(span.context.dd)

        XCTAssertNotEqual(spanID, spanDD.spanID)
        XCTAssertNotEqual(request.value(forHTTPHeaderField: "x-datadog-parent-id"), spanDD.spanID.toString(representation: .decimal))
        XCTAssertEqual(request.value(forHTTPHeaderField: "x-datadog-sampling-priority"), "1")

        if expectation == .rum {
            XCTAssertNotEqual(traceID, span.context.dd?.traceID)
            XCTAssertNotEqual(request.value(forHTTPHeaderField: "x-datadog-trace-id"), spanDD.traceID.toString(representation: .decimal))
            XCTAssertNotNil(request.value(forHTTPHeaderField: "x-datadog-sampling-priority"))
            XCTAssertNotNil(request.value(forHTTPHeaderField: "traceparent"))
            XCTAssertEqual(sessionSampleRate, 80)
        } else { // expectation == .activeSpan
            let parentSpanIDString: String = try XCTUnwrap(resourceMatcher.attribute(forKeyPath: "_dd.parent_span_id"))
            let parentSpanID = SpanID(parentSpanIDString, representation: .decimal)
            XCTAssertEqual(traceID, spanDD.traceID)
            XCTAssertEqual(parentSpanID, spanDD.spanID)
            XCTAssertEqual(request.value(forHTTPHeaderField: "x-datadog-trace-id"), spanDD.traceID.toString(representation: .decimal))
            XCTAssertNotNil(request.value(forHTTPHeaderField: "traceparent"))
            XCTAssertEqual(sessionSampleRate, 80)
        }
    }
}
