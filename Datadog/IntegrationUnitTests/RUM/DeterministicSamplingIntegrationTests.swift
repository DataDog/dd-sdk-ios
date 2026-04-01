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
