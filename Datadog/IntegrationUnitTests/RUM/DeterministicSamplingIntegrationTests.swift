/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import DatadogInternal
import TestUtilities
@testable import DatadogCore
@testable import DatadogRUM
@testable import DatadogTrace

#if os(iOS)
@_spi(Internal)
@testable import DatadogSessionReplay
#endif

/// Integration tests verifying deterministic sampling behavior.
///
/// Unit-level correctness (hash math, `combined(with:)`) is covered in `DeterministicSamplerTests`,
/// `RecordingCoordinatorTests`, and `TracingURLSessionHandlerTests`. These integration tests verify
/// the wiring through the full SDK pipeline:
/// `RUM.enable` → `RUMSessionScope` creates `DeterministicSampler(uuid: sessionUUID)` → events
/// are suppressed end-to-end when `isSampled == false`.
/// A `URLSession` delegate used only by this file.
///
/// `URLSessionInstrumentation.enable(with:)` swizzles the delegate CLASS, and that swizzling is
/// process-global and outlives the core that installed it. Using a private class rather than the
/// shared `SessionDataDelegateMock` keeps this file's instrumentation from being observable in other
/// test files. This is hygiene, not a fix for any known failure.
private final class SamplingSessionDelegate: NSObject, URLSessionDataDelegate {}

class DeterministicSamplingIntegrationTests: XCTestCase {
    // swiftlint:disable implicitly_unwrapped_optional
    private var core: DatadogCoreProxy!
    // swiftlint:enable implicitly_unwrapped_optional

    override func setUp() {
        super.setUp()
        core = DatadogCoreProxy()
    }

    override func tearDownWithError() throws {
        try core.flushAndTearDown()
        core = nil
        super.tearDown()
    }

    // MARK: - Unsampled session produces no events

    /// Verifies the full pipeline suppresses events for an unsampled session.
    ///
    /// Pins a UUID whose Knuth hash lands above the 50% threshold so `isSampled == false`,
    /// then asserts that no RUM events reach the feature scope. This exercises the real
    /// `DeterministicSampler(uuid: sessionUUID, samplingRate:)` wiring inside `RUMSessionScope`
    /// — something unit tests cannot cover because they inject mock samplers.
    ///
    /// UUID `c5b3c4ab-fa4a-4de9-8199-a522131ec48a`: Knuth hash ≈ 50.68% → not sampled at 50%.
    func testUnsampledSession_producesNoRUMEvents() throws {
        let sessionUUID = UUID(uuidString: "c5b3c4ab-fa4a-4de9-8199-a522131ec48a")!

        // Precondition guard — fail loudly if the hash properties ever change
        try XCTSkipUnless(
            !DeterministicSampler(uuid: sessionUUID, samplingRate: 50.0).isSampled,
            "Precondition: UUID must NOT be sampled at 50%"
        )

        // Given
        var rumConfig = RUM.Configuration(applicationID: "test-app-id")
        rumConfig.sessionSampleRate = 50
        rumConfig.uuidGenerator = RUMUUIDGeneratorMock(uuid: RUMUUID(rawValue: sessionUUID))
        RUM.enable(with: rumConfig, in: core)

        // When
        RUMMonitor.shared(in: core).startView(key: "test-view", name: "TestView")
        RUMMonitor.shared(in: core).addAction(type: .tap, name: "Tap")
        _ = core.waitAndReturnEventsData(ofFeature: RUMFeature.name)

        // Then — no events must be written for an unsampled session
        let events = core.waitAndReturnEventsData(ofFeature: RUMFeature.name)
        XCTAssertTrue(events.isEmpty, "Unsampled session must produce no RUM events")
    }

    // MARK: - Initial session adopts the synchronously created identity

    /// Verifies the initial session adopts the session ID created in `RUM.enable()` instead of generating
    /// its own once the asynchronous session-creation flow runs.
    ///
    /// The generator hands out a different UUID on every call, so if the initial session generated its own
    /// ID the sampler published by `onSessionUpdate` would differ from the one exposed synchronously. This
    /// is what guarantees an early request and the rest of the session share one decision. See RUM-17921.
    func testInitialSession_adoptsTheIdentityCreatedAtEnableTime() throws {
        // Given
        let presetUUID = UUID(uuidString: "c5b3c4ab-fa4a-4de9-8199-a522131ec48a")!
        let nextUUID = UUID(uuidString: "c5b3c4ab-fa4a-4de9-8199-a5221003fa41")!
        let generator = SequencedRUMUUIDGeneratorMock(uuids: [RUMUUID(rawValue: presetUUID), RUMUUID(rawValue: nextUUID)])

        var rumConfig = RUM.Configuration(applicationID: "test-app-id")
        rumConfig.sessionSampleRate = 60
        rumConfig.uuidGenerator = generator

        // When
        RUM.enable(with: rumConfig, in: core)

        let rum = try XCTUnwrap(core.get(feature: RUMFeature.self))
        let synchronousSnapshot = try XCTUnwrap(
            rum.decision(for: .combinedWithSessionRate, rate: .maxSampleRate),
            "The session identity must exist before any flush"
        )

        // Let the asynchronous session-creation flow run
        RUMMonitor.shared(in: core).startView(key: "test-view", name: "TestView")
        core.flush()

        // Then - the session published by `onSessionUpdate` must be the one created at enable time
        XCTAssertEqual(
            rum.decision(for: .combinedWithSessionRate, rate: .maxSampleRate),
            synchronousSnapshot,
            "The initial session must adopt the preset identity, not generate a new one"
        )
        XCTAssertEqual(synchronousSnapshot.sessionID, RUMUUID(rawValue: presetUUID).toRUMDataFormat)
        XCTAssertEqual(synchronousSnapshot.isSampled, DeterministicSampler(uuid: presetUUID, samplingRate: 60).isSampled)
    }

    // MARK: - The two sampling rate policies

    /*
     A feature's sampling rate relates to the RUM session rate in one of two ways, and the two must
     not be mixed up:

       - `Trace.Configuration.sampleRate` is an absolute trace sampling rate. The session supplies
         only the seed, so 20% stays 20%.
       - `urlSessionTracking.firstPartyHostsTracing`'s rate is a share of the sessions RUM keeps, so
         20% inside a 10% session is an effective 2%.

     Both features now read the same synchronous store, which makes it easy to apply one policy to
     both by accident. These tests pin the difference. See RUM-17921.
     */

    /// A session UUID whose Knuth hash fraction is roughly 6.4%.
    ///
    /// It is kept at 20% applied alone, and dropped at the 2% that composing 20% with a 10% session
    /// rate produces, so one session exercises both policies in opposite directions.
    private static let policyVectorUUID = UUID(uuidString: "a1b2c3d4-e5f6-7890-abcd-ceb01cf21171")!

    func testManualTraceSpan_appliesTheTraceRateWithoutComposingItWithTheSessionRate() throws {
        let sessionUUID = Self.policyVectorUUID
        let sessionRate: SampleRate = 10
        let traceRate: SampleRate = 20

        // Premise guards, ASSERTED rather than skipped. If a change to the Knuth math or to
        // `SampleRate.composed(with:)` stops this vector separating the two policies, the assertions
        // further down stop proving anything. A skip would turn that into a green build; a failure
        // makes it visible. See RUM-17921.
        let sessionSampler = DeterministicSampler(uuid: sessionUUID, samplingRate: sessionRate)
        XCTAssertTrue(sessionSampler.isSampled, "Precondition: the session must be sampled at \(sessionRate)%")
        XCTAssertTrue(
            DeterministicSampler(uuid: sessionUUID, samplingRate: traceRate).isSampled,
            "Precondition: the vector must be kept at the trace rate applied alone"
        )
        XCTAssertFalse(
            sessionSampler.combined(with: traceRate).isSampled,
            "Precondition: the vector must be dropped at the composed rate"
        )

        // Given
        var rumConfig = RUM.Configuration(applicationID: "test-app-id")
        rumConfig.sessionSampleRate = sessionRate
        rumConfig.uuidGenerator = RUMUUIDGeneratorMock(uuid: RUMUUID(rawValue: sessionUUID))
        RUM.enable(with: rumConfig, in: core)

        var traceConfig = Trace.Configuration()
        traceConfig.sampleRate = traceRate
        Trace.enable(with: traceConfig, in: core)

        // When
        Tracer.shared(in: core).startSpan(operationName: "manual").finish()

        // Then — a 20% trace rate keeps this session; composing it down to 2% would drop it
        let spans = core.waitAndReturnSpanEvents()
        XCTAssertEqual(spans.count, 1)
        XCTAssertTrue(
            try XCTUnwrap(spans.first).samplingPriority.isKept,
            "The trace sample rate is absolute, so the session must contribute only the seed"
        )
    }

    func testURLSessionRequest_composesTheTracingRateWithTheSessionRate() throws {
        let sessionUUID = Self.policyVectorUUID
        let sessionRate: SampleRate = 10
        let tracingRate: SampleRate = 20

        let sessionSampler = DeterministicSampler(uuid: sessionUUID, samplingRate: sessionRate)
        XCTAssertTrue(sessionSampler.isSampled, "Precondition: the session must be sampled at \(sessionRate)%")
        XCTAssertTrue(
            DeterministicSampler(uuid: sessionUUID, samplingRate: tracingRate).isSampled,
            "Precondition: the vector must be kept at the tracing rate applied alone"
        )
        XCTAssertFalse(
            sessionSampler.combined(with: tracingRate).isSampled,
            "Precondition: the vector must be dropped at the composed rate"
        )

        // Given
        var rumConfig = RUM.Configuration(applicationID: "test-app-id")
        rumConfig.sessionSampleRate = sessionRate
        rumConfig.uuidGenerator = RUMUUIDGeneratorMock(uuid: RUMUUID(rawValue: sessionUUID))
        rumConfig.urlSessionTracking = .init(
            // `.all` so the dropped request still carries its headers, with priority 0. The default
            // `.sampled` would inject nothing, which is indistinguishable from the request never
            // having been instrumented.
            firstPartyHostsTracing: .trace(
                hosts: ["www.example.com"],
                sampleRate: tracingRate,
                traceControlInjection: .all
            )
        )
        RUM.enable(with: rumConfig, in: core)

        // When
        URLSessionInstrumentation.enable(
            with: .init(delegateClass: SamplingSessionDelegate.self),
            in: core
        )
        let server = ServerMock(delivery: .success(response: .mockResponseWith(statusCode: 200), data: .mock(ofSize: 10)))
        let session = server.getInterceptedURLSession(delegate: SamplingSessionDelegate())
        let completed = expectation(description: "request completes")
        session
            .dataTask(with: URLRequest(url: URL(string: "https://www.example.com/resource")!)) { _, _, _ in
                completed.fulfill()
            }
            .resume()
        waitForExpectations(timeout: 5)

        // Then — 20% of a 10% session is an effective 2%, which drops this request
        let sentRequest = try XCTUnwrap(server.waitAndReturnRequests(count: 1).first)
        XCTAssertEqual(
            sentRequest.value(forHTTPHeaderField: "x-datadog-sampling-priority"),
            "0",
            "The tracing rate applies on top of the session rate, so the two must be composed"
        )
        XCTAssertEqual(
            sentRequest.value(forHTTPHeaderField: "baggage"),
            "session.id=\(RUMUUID(rawValue: sessionUUID).toRUMDataFormat)",
            "The request must carry the session the decision was made for, even before the RUM context is broadcast"
        )
    }

    func testStopSession_emptiesTheStoreSoConsumersStopAttachingTheStoppedSession() throws {
        // Given
        let sessionUUID = Self.policyVectorUUID
        var rumConfig = RUM.Configuration(applicationID: "test-app-id")
        rumConfig.sessionSampleRate = .maxSampleRate
        rumConfig.uuidGenerator = RUMUUIDGeneratorMock(uuid: RUMUUID(rawValue: sessionUUID))
        RUM.enable(with: rumConfig, in: core)

        let rum = try XCTUnwrap(core.get(feature: RUMFeature.self))
        RUMMonitor.shared(in: core).startView(key: "test-view", name: "TestView")
        core.flush()
        XCTAssertNotNil(
            rum.decision(for: .combinedWithSessionRate, rate: .maxSampleRate),
            "Precondition: a session must be active before stopping it"
        )

        // When
        RUMMonitor.shared(in: core).stopSession()
        core.flush()

        // Then — the store must be empty, so a request issued now falls back to its own sampling instead
        // of attaching the stopped session's ID and decision. Because the URLSession handler holds the
        // store strongly, a store that kept the stopped identity would keep stamping it indefinitely.
        XCTAssertNil(
            rum.decision(for: .combinedWithSessionRate, rate: .maxSampleRate),
            "`stopSession()` must clear the synchronous store, not just the RUM scope"
        )
    }

    func testTraceOwnedURLSessionTracking_composesTheTracingRateWithTheRUMSessionRate() throws {
        let sessionUUID = Self.policyVectorUUID
        let sessionRate: SampleRate = 10
        let tracingRate: SampleRate = 20

        let sessionSampler = DeterministicSampler(uuid: sessionUUID, samplingRate: sessionRate)
        XCTAssertTrue(sessionSampler.isSampled, "Precondition: the session must be sampled at \(sessionRate)%")
        XCTAssertTrue(
            DeterministicSampler(uuid: sessionUUID, samplingRate: tracingRate).isSampled,
            "Precondition: the vector must be kept at the tracing rate applied alone"
        )
        XCTAssertFalse(
            sessionSampler.combined(with: tracingRate).isSampled,
            "Precondition: the vector must be dropped at the composed rate"
        )

        // Given — RUM owns the session but NOT resource tracking, so only Trace's handler is registered.
        // Enabling both `urlSessionTracking` configurations for the same requests is documented as
        // unsupported, and this test covers the Trace-owned wiring at `Trace.swift`.
        var rumConfig = RUM.Configuration(applicationID: "test-app-id")
        rumConfig.sessionSampleRate = sessionRate
        rumConfig.uuidGenerator = RUMUUIDGeneratorMock(uuid: RUMUUID(rawValue: sessionUUID))
        rumConfig.urlSessionTracking = nil
        RUM.enable(with: rumConfig, in: core)

        var traceConfig = Trace.Configuration(
            urlSessionTracking: .init(
                firstPartyHostsTracing: .trace(
                    hosts: ["www.example.com"],
                    sampleRate: tracingRate,
                    traceControlInjection: .all
                )
            )
        )
        traceConfig.traceIDGenerator = RelativeTracingUUIDGenerator(startingFrom: .init(idHi: 10, idLo: 100))
        Trace.enable(with: traceConfig, in: core)

        // When
        URLSessionInstrumentation.enable(
            with: .init(delegateClass: SamplingSessionDelegate.self),
            in: core
        )
        let server = ServerMock(delivery: .success(response: .mockResponseWith(statusCode: 200), data: .mock(ofSize: 10)))
        let session = server.getInterceptedURLSession(delegate: SamplingSessionDelegate())
        let completed = expectation(description: "request completes")
        session
            .dataTask(with: URLRequest(url: URL(string: "https://www.example.com/resource")!)) { _, _, _ in
                completed.fulfill()
            }
            .resume()
        waitForExpectations(timeout: 5)

        // Then
        let sentRequest = try XCTUnwrap(server.waitAndReturnRequests(count: 1).first)
        XCTAssertEqual(
            sentRequest.value(forHTTPHeaderField: "x-datadog-sampling-priority"),
            "0",
            "Trace's URLSession rate is a share of the RUM session, so the two must be composed"
        )
        XCTAssertEqual(
            sentRequest.value(forHTTPHeaderField: "baggage"),
            "session.id=\(RUMUUID(rawValue: sessionUUID).toRUMDataFormat)",
            "Trace must attach the session the decision was made for, read synchronously from the store"
        )
    }

    /// Trace must pick up a RUM session that is enabled AFTER it.
    ///
    /// Both Trace call sites store a `RUMSessionSampler`, which holds the core weakly and resolves
    /// `RUMSessionSamplerProvider` on every read (`TraceFeature.init` for manual spans,
    /// `Trace.enableOrThrow` for the URLSession handler). That per-read lookup exists precisely for
    /// this ordering: at `Trace.enable()` time RUM may not be registered, so a provider resolved once
    /// and stored would be `nil` for the process lifetime. Every other test in this file enables RUM
    /// first, where an eagerly-resolved provider would still work.
    func testTraceEnabledBeforeRUM_stillResolvesTheSessionOnEveryRead() throws {
        let sessionUUID = Self.policyVectorUUID
        let sessionRate: SampleRate = 10
        let rate: SampleRate = 20

        let sessionSampler = DeterministicSampler(uuid: sessionUUID, samplingRate: sessionRate)
        XCTAssertTrue(sessionSampler.isSampled, "Precondition: the session must be sampled at \(sessionRate)%")
        XCTAssertTrue(
            DeterministicSampler(uuid: sessionUUID, samplingRate: rate).isSampled,
            "Precondition: the vector must be kept at the feature rate applied alone"
        )
        XCTAssertFalse(
            sessionSampler.combined(with: rate).isSampled,
            "Precondition: the vector must be dropped at the composed rate"
        )

        // Given — Trace FIRST, with no RUM on the core yet.
        var traceConfig = Trace.Configuration(
            urlSessionTracking: .init(
                firstPartyHostsTracing: .trace(
                    hosts: ["www.example.com"],
                    sampleRate: rate,
                    traceControlInjection: .all
                )
            )
        )
        traceConfig.sampleRate = rate
        traceConfig.traceIDGenerator = RelativeTracingUUIDGenerator(startingFrom: .init(idHi: 10, idLo: 100))
        Trace.enable(with: traceConfig, in: core)

        // When — RUM is enabled afterwards, and owns no resource tracking of its own.
        var rumConfig = RUM.Configuration(applicationID: "test-app-id")
        rumConfig.sessionSampleRate = sessionRate
        rumConfig.uuidGenerator = RUMUUIDGeneratorMock(uuid: RUMUUID(rawValue: sessionUUID))
        rumConfig.urlSessionTracking = nil
        RUM.enable(with: rumConfig, in: core)

        // Then (1) - the manual-span sampler, resolved through `TraceFeature.init`'s sampler, applies the trace
        // rate on its own seeded by the session, so the vector is kept.
        Tracer.shared(in: core).startSpan(operationName: "manual").finish()
        let spans = core.waitAndReturnSpanEvents()
        XCTAssertEqual(spans.count, 1)
        XCTAssertTrue(
            try XCTUnwrap(spans.first).samplingPriority.isKept,
            "A manual span must be seeded by a RUM session enabled after Trace"
        )

        // Then (2) - the URLSession handler, resolved through `Trace.enableOrThrow`'s sampler, composes the two
        // rates, so the same vector is dropped and still carries the session ID.
        URLSessionInstrumentation.enable(
            with: .init(delegateClass: SamplingSessionDelegate.self),
            in: core
        )
        let server = ServerMock(delivery: .success(response: .mockResponseWith(statusCode: 200), data: .mock(ofSize: 10)))
        let session = server.getInterceptedURLSession(delegate: SamplingSessionDelegate())
        let completed = expectation(description: "request completes")
        session
            .dataTask(with: URLRequest(url: URL(string: "https://www.example.com/resource")!)) { _, _, _ in
                completed.fulfill()
            }
            .resume()
        waitForExpectations(timeout: 5)

        let sentRequest = try XCTUnwrap(server.waitAndReturnRequests(count: 1).first)
        XCTAssertEqual(sentRequest.value(forHTTPHeaderField: "x-datadog-sampling-priority"), "0")
        XCTAssertEqual(
            sentRequest.value(forHTTPHeaderField: "baggage"),
            "session.id=\(RUMUUID(rawValue: sessionUUID).toRUMDataFormat)",
            "The handler must resolve a RUM session enabled after Trace"
        )
    }

    /// Each core carries its own RUM session, so every resolver must read its own core's store.
    func testMultipleCores_eachResolvesItsOwnSession() throws {
        let firstUUID = Self.policyVectorUUID
        let secondUUID = UUID(uuidString: "c5b3c4ab-fa4a-4de9-8199-a522131ec48a")!

        let secondCore = DatadogCoreProxy()
        defer { try? secondCore.flushAndTearDown() }

        var firstConfig = RUM.Configuration(applicationID: "first-app-id")
        firstConfig.sessionSampleRate = .maxSampleRate
        firstConfig.uuidGenerator = RUMUUIDGeneratorMock(uuid: RUMUUID(rawValue: firstUUID))
        RUM.enable(with: firstConfig, in: core)

        var secondConfig = RUM.Configuration(applicationID: "second-app-id")
        secondConfig.sessionSampleRate = .maxSampleRate
        secondConfig.uuidGenerator = RUMUUIDGeneratorMock(uuid: RUMUUID(rawValue: secondUUID))
        RUM.enable(with: secondConfig, in: secondCore)

        // Then - resolving through `DatadogCoreProtocol.rumSessionSampler`, which is what Trace and
        // WebView tracking use, must never cross cores.
        let first = try XCTUnwrap(
            core.rumSessionSampler.decision(for: .combinedWithSessionRate, rate: .maxSampleRate)
        )
        let second = try XCTUnwrap(
            secondCore.rumSessionSampler.decision(for: .combinedWithSessionRate, rate: .maxSampleRate)
        )

        XCTAssertEqual(first.sessionID, RUMUUID(rawValue: firstUUID).toRUMDataFormat)
        XCTAssertEqual(second.sessionID, RUMUUID(rawValue: secondUUID).toRUMDataFormat)
        XCTAssertNotEqual(first.sessionID, second.sessionID)
    }

    // MARK: - Session Replay child-rate correction

    #if os(iOS)
    /// Verifies the child-rate correction end-to-end: given a session UUID whose Knuth hash
    /// lands in the band [40%, 80%) — sampled at the RUM session rate (80%) but NOT at the
    /// effective combined rate (session=80% × SR=50% = 40%) — SR must set `has_replay = false`.
    ///
    /// This proves that SR uses `sessionSampler.combined(with: replaySampleRate)` rather than
    /// an independent draw against its own rate.
    ///
    /// UUID `c5b3c4ab-fa4a-4de9-8199-a522131ec48a`: sampled at 80%, NOT sampled at 40%.
    func testSRChildRateCorrection_sessionInBand_isNotRecorded() throws {
        let sessionUUID = UUID(uuidString: "c5b3c4ab-fa4a-4de9-8199-a522131ec48a")!

        // Precondition guard — if hash properties ever change, fail loudly
        let sampler = DeterministicSampler(uuid: sessionUUID, samplingRate: 80.0)
        try XCTSkipUnless(sampler.isSampled, "Precondition: UUID must be sampled at 80%")
        try XCTSkipUnless(!sampler.combined(with: 50.0).isSampled, "Precondition: UUID must NOT be sampled at combined 40%")

        var rumConfig = RUM.Configuration(applicationID: "test-app-id")
        rumConfig.sessionSampleRate = 80
        rumConfig.uuidGenerator = RUMUUIDGeneratorMock(uuid: RUMUUID(rawValue: sessionUUID))
        RUM.enable(with: rumConfig, in: core)

        SessionReplay.enable(with: SessionReplay.Configuration(
            replaySampleRate: 50,
            textAndInputPrivacyLevel: .maskAll,
            imagePrivacyLevel: .maskAll,
            touchPrivacyLevel: .hide
        ), in: core)

        RUMMonitor.shared(in: core).startView(key: "test-view", name: "TestView")
        _ = core.waitAndReturnEventsData(ofFeature: RUMFeature.name)

        // The RUM view must exist (session sampled at 80%)
        let rumMatchers = try core.waitAndReturnRUMEventMatchers()
        XCTAssertFalse(rumMatchers.filterRUMEvents(ofType: RUMViewEvent.self).isEmpty, "RUM must record: session is sampled at 80%")

        // SR must NOT record (combined rate 40% excludes this UUID)
        let srData = core.waitAndReturnEventsData(ofFeature: SessionReplayFeature.name)
        XCTAssertTrue(srData.isEmpty, "SR must not record: UUID is excluded by the combined 40% rate")
    }
    #endif

    // MARK: - Trace (manually created spans) sampling with RUM Session ID
    // MARK: 1. Trace rate is lower than session rate

    /*
        Session sampled -> Trace may or may not be sampled
        Session not sampled -> Trace not sampled
     */
    func testManuallyCreatedSpan_traceRateLowerThanSessionRate_sampledSession() throws {
        // Session is sampled, trace is not.
        let sessionUUID = try makeValidatedSessionID()
        enabledRUMWith(samplingRate: 60, traceSamplingRate: .random(in: 0...50), sessionUUID: sessionUUID)
        let span = createViewAndSpan()
        try assert(rumViewsExist: true, span: span, spansExist: false)
    }

    func testManuallyCreatedSpan_traceRateLowerThanSessionRate_nonSampledSession() throws {
        // Session is NOT sampled, trace is also not.
        let sessionUUID = try makeValidatedSessionID()
        enabledRUMWith(samplingRate: 50, traceSamplingRate: .random(in: 0...50), sessionUUID: sessionUUID)
        let span = createViewAndSpan()
        try assert(rumViewsExist: false, span: span, spansExist: false)
    }

    func testManuallyCreatedSpan_traceRateLowerThanSessionRate_random() throws {
        let sessionUUID = UUID()
        let sampler = DeterministicSampler(uuid: sessionUUID, samplingRate: .random(in: 0...100))
        let traceSampler = DeterministicSampler(uuid: sessionUUID, samplingRate: .random(in: 0...Float.random(in: 0...(min(50, sampler.samplingRate)))))
        enabledRUMWith(samplingRate: sampler.samplingRate, traceSamplingRate: traceSampler.samplingRate, sessionUUID: sessionUUID)
        let span = createViewAndSpan()
        try assert(rumViewsExist: sampler.isSampled, span: span, spansExist: traceSampler.isSampled)
        XCTAssert(
            sampler.isSampled /* Session sampled -> Trace may or may not be sampled */
            || (traceSampler.isSampled == false) /* Session not sampled -> Trace not sampled */
        )
    }

    // MARK: 2. Trace rate is equal to session rate

    /*
       Session sampled -> Trace is sampled
       Session not sampled -> Trace not sampled
     */
    func testManuallyCreatedSpan_traceRateEqualToSessionRate_sampledSession() throws {
        let sessionUUID = try makeValidatedSessionID()
        enabledRUMWith(samplingRate: 60, traceSamplingRate: 60, sessionUUID: sessionUUID)
        let span = createViewAndSpan()
        try assert(rumViewsExist: true, span: span, spansExist: true)
    }

    func testManuallyCreatedSpan_traceRateEqualToSessionRate_nonSampledSession() throws {
        let sessionUUID = try makeValidatedSessionID()
        enabledRUMWith(samplingRate: 50, traceSamplingRate: 50, sessionUUID: sessionUUID)
        let span = createViewAndSpan()
        try assert(rumViewsExist: false, span: span, spansExist: false)
    }

    func testManuallyCreatedSpan_traceRateEqualToSessionRate_random() throws {
        let sessionUUID = UUID()
        let sampler = DeterministicSampler(uuid: sessionUUID, samplingRate: .random(in: 0...100))
        enabledRUMWith(samplingRate: sampler.samplingRate, traceSamplingRate: sampler.samplingRate, sessionUUID: sessionUUID)
        let span = createViewAndSpan()
        try assert(rumViewsExist: sampler.isSampled, span: span, spansExist: sampler.isSampled)
    }

    // MARK: 3. Trace rate is higher than session rate

    /*
        Session sampled -> Trace is sampled
        Session not sampled -> Trace may or may not be sampled
     */
    func testManuallyCreatedSpan_traceRateHigherThanSessionRate_sampledSession() throws {
        // Session is sampled, trace is.
        let sessionUUID = try makeValidatedSessionID()
        enabledRUMWith(samplingRate: 60, traceSamplingRate: .random(in: 60...100), sessionUUID: sessionUUID)
        let span = createViewAndSpan()
        try assert(rumViewsExist: true, span: span, spansExist: true)
    }

    func testManuallyCreatedSpan_traceRateHigherThanSessionRate_nonSampledSession() throws {
        // Session is NOT sampled, trace is.
        let sessionUUID = try makeValidatedSessionID()
        enabledRUMWith(samplingRate: 50, traceSamplingRate: .random(in: 60...100), sessionUUID: sessionUUID)
        let span = createViewAndSpan()
        try assert(rumViewsExist: false, span: span, spansExist: true)
    }

    func testManuallyCreatedSpan_traceRateHigherThanSessionRate_random() throws {
        let sessionUUID = UUID()
        let sampler = DeterministicSampler(uuid: sessionUUID, samplingRate: .random(in: 0...100))
        let traceSampler = DeterministicSampler(uuid: sessionUUID, samplingRate: Float.random(in: (max(60, sampler.samplingRate))...100))
        enabledRUMWith(samplingRate: sampler.samplingRate, traceSamplingRate: traceSampler.samplingRate, sessionUUID: sessionUUID)
        let span = createViewAndSpan()
        try assert(rumViewsExist: sampler.isSampled, span: span, spansExist: traceSampler.isSampled)
        XCTAssert(
            sampler.isSampled == false /* Session not sampled -> Trace may or may not be sampled */
            || traceSampler.isSampled /* Session sampled -> Trace is sampled */
        )
    }

    // MARK: Helper methods

    private func makeValidatedSessionID() throws -> UUID {
        // This session ID is not sampled at 50%, but it is sampled at 60%.
        let sessionUUID = UUID(uuidString: "c5b3c4ab-fa4a-4de9-8199-a522131ec48a")!

        // Preconditions guard — if hash properties ever change, fail loudly
        let canary1 = DeterministicSampler(uuid: sessionUUID, samplingRate: 50)
        try XCTSkipUnless(canary1.isSampled == false, "Precondition: UUID must NOT be sampled at 50%")
        let canary2 = DeterministicSampler(uuid: sessionUUID, samplingRate: 60)
        try XCTSkipUnless(canary2.isSampled == true, "Precondition: UUID must be sampled at 60%")

        return sessionUUID
    }

    private func enabledRUMWith(samplingRate rumSamplingRate: Float, traceSamplingRate: Float, sessionUUID: UUID) {
        var rumConfig = RUM.Configuration(applicationID: "test-app-id")
        rumConfig.sessionSampleRate = rumSamplingRate
        rumConfig.uuidGenerator = RUMUUIDGeneratorMock(uuid: RUMUUID(rawValue: sessionUUID))
        RUM.enable(with: rumConfig, in: core)

        let traceConfig = Trace.Configuration(sampleRate: traceSamplingRate)
        Trace.enable(with: traceConfig, in: core)

        // Wait until all the pieces injected in the context and shared between modules are in place.
        core.flush()
    }

    private func createViewAndSpan(customSpanSampleRate: Float? = nil) -> OTSpan {
        let tracer = Tracer.shared(in: core)

        RUMMonitor.shared(in: core).startView(key: "test-view", name: "TestView")
        let span = tracer.startRootSpan(operationName: "Test Action", customSampleRate: customSpanSampleRate)
        span.finish()
        _ = core.waitAndReturnEventsData(ofFeature: RUMFeature.name)
        _ = core.waitAndReturnEventsData(ofFeature: TraceFeature.name)

        return span
    }

    private func assert(rumViewsExist: Bool, span: OTSpan, spansExist: Bool) throws {
        // The RUM view must exist (session sampled at 60%)
        let rumMatchers = try core.waitAndReturnRUMEventMatchers()
        XCTAssert(rumMatchers.filterRUMEvents(ofType: RUMViewEvent.self).isEmpty != rumViewsExist)

        let traceMatchers = try core.waitAndReturnSpanMatchers()
        XCTAssert(traceMatchers.isEmpty != spansExist)

        let dd = try XCTUnwrap(span.context.dd)
        XCTAssert(dd.samplingDecision.samplingPriority.isKept == spansExist)
    }
}

/// A `RUMUUIDGenerator` that returns a different UUID on each call, then repeats the last one.
///
/// `RUMUUIDGeneratorMock` always returns the same value, which cannot distinguish "the session adopted the
/// preset ID" from "the session generated a new one".
private final class SequencedRUMUUIDGeneratorMock: RUMUUIDGenerator {
    private var uuids: [RUMUUID]
    private var index = 0

    init(uuids: [RUMUUID]) {
        precondition(!uuids.isEmpty)
        self.uuids = uuids
    }

    func generateUnique() -> RUMUUID {
        defer { index = min(index + 1, uuids.count - 1) }
        return uuids[index]
    }
}
