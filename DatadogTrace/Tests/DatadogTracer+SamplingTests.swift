/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import TestUtilities
@_spi(Internal)
import DatadogInternal
@testable import DatadogTrace

class DatadogTracer_SamplingTests: XCTestCase {
    private let featureScope = FeatureScopeMock()

    private func createTracer(sampleRate: Float) -> DatadogTracer {
        return DatadogTracer(
            featureScope: featureScope,
            samplingProvider: TracerSamplerProviderMock(sampler: Sampler(samplingRate: sampleRate)),
            tags: [:],
            traceIDGenerator: DefaultTraceIDGenerator(),
            spanIDGenerator: DefaultSpanIDGenerator(),
            dateProvider: DateProviderMock(),
            loggingIntegration: .mockAny(),
            spanEventBuilder: .mockAny()
        )
    }

    func testRecordingSampleRateInSpanEvent() throws {
        // When
        let tracer = createTracer(sampleRate: 42)
        (0..<100).forEach { _ in
            let span = tracer.startSpan(operationName: .mockAny())
            span.finish()
        }

        // Then
        let events = try XCTUnwrap(featureScope.spanEventsWritten())
        XCTAssertTrue(events.allSatisfy({ $0.samplingRate == 0.42 }), "All kept spans must encode sample rate")
        XCTAssertGreaterThan(events.filter({ $0.samplingPriority.isKept }).count, 1, "Some spans should be kept")
        XCTAssertEqual(events.filter({ !$0.samplingPriority.isKept }).count, 0, "Not kept spans should be dropped")
    }

    func testRecordingCustomSampleRateInRootSpanEvent() throws {
        // When
        let tracer = createTracer(sampleRate: 0)
        (0..<10).forEach { _ in
            let span = tracer.startRootSpan(operationName: .mockAny(), customSampleRate: 100)
            span.finish()
        }

        // Then
        let events = try XCTUnwrap(featureScope.spanEventsWritten())
        XCTAssertEqual(events.filter({ $0.samplingRate == 1 }).count, 10)
        XCTAssertEqual(events.filter({ $0.samplingPriority.isKept }).count, 10)
    }

    func testRootSampleInOverridesTracerAndPropagatesToChildSpans() throws {
        // When
        let tracer = createTracer(sampleRate: 0)
        let root = tracer.startRootSpan(operationName: .mockAny(), customSampleRate: 100)
        let child = tracer.startSpan(operationName: .mockAny(), childOf: root.context)
        let grandChild = tracer.startSpan(operationName: .mockAny(), childOf: child.context)
        grandChild.finish()
        child.finish()
        root.finish()

        // Then
        let events = try XCTUnwrap(featureScope.spanEventsWritten())
        XCTAssertEqual(events.count, 3)
        XCTAssertEqual(events.filter({ $0.samplingRate == 1 }).count, 3)
        XCTAssertEqual(events.filter({ $0.samplingPriority.isKept }).count, 3)
    }

    func testRootSampleOutOverridesTracerAndPropagatesToChildSpans() throws {
        // When
        let tracer = createTracer(sampleRate: 100)
        let root = tracer.startRootSpan(operationName: .mockAny(), customSampleRate: 0)
        let child = tracer.startSpan(operationName: .mockAny(), childOf: root.context)
        let grandChild = tracer.startSpan(operationName: .mockAny(), childOf: child.context)
        grandChild.finish()
        child.finish()
        root.finish()

        // Then
        let events = try XCTUnwrap(featureScope.spanEventsWritten())
        XCTAssertEqual(events.count, 0)
    }

    func testRecordingSampledSpan() throws {
        // When
        let tracer = createTracer(sampleRate: 100)
        let span = tracer.startSpan(operationName: .mockAny())
        span.finish()

        // Then
        let event = try XCTUnwrap(featureScope.spanEventsWritten().first)
        XCTAssertEqual(event.samplingRate, 1)
        XCTAssertTrue(event.samplingPriority.isKept)
    }

    func testRecordingDroppedSpan() throws {
        // When
        let tracer = createTracer(sampleRate: 0)
        let span = tracer.startSpan(operationName: .mockAny())
        span.finish()

        // Then
        let event = try featureScope.spanEventsWritten().first
        XCTAssertNil(event)
    }

    // MARK: - Head-based Sampling

    func testWhenRootSpanIsSampled_thenAllChildSpansMustBeSampledTheSameWay() throws {
        // When
        let tracer = createTracer(sampleRate: 50)
        let root = tracer.startSpan(operationName: .mockAny())
        let child = tracer.startSpan(operationName: .mockAny(), childOf: root.context)
        let grandchild = tracer.startSpan(operationName: .mockAny(), childOf: child.context)
        grandchild.finish()
        child.finish()
        root.finish()

        // Then
        let events = try XCTUnwrap(featureScope.spanEventsWritten())

        if events.isEmpty {
            XCTAssert(true, "No spans were collected")
        } else {
            XCTAssertEqual(events.filter({ $0.samplingRate == 0.5 }).count, 3, "All spans must encode the same sample rate")
            XCTAssertEqual(events.filter({ $0.samplingPriority.isKept }).count, 3, "All spans must be kept")
        }
    }
}

extension FeatureScopeMock {
    func spanEventsWritten() throws -> [SpanEvent] {
        let events: [SpanEventsEnvelope] = eventsWritten()
        return events.reduce([], { acc, next in acc + next.spans })
    }
}

/// Tests for the sampler `SamplerProvider` hands to manual tracing operations.
///
/// `Trace.Configuration.sampleRate` is an absolute trace sampling rate, so it must not be composed
/// with the RUM session rate. The RUM session contributes the seed only, which keeps every span in a
/// session on the same side of the decision without changing how many traces are kept.
class SamplerProviderTests: XCTestCase {
    /// A session UUID whose Knuth hash fraction is roughly 6.4%: kept at a 20% rate applied alone,
    /// dropped at the 2% that composing 20% with a 10% session rate would produce.
    private let sessionUUID = UUID(uuidString: "a1b2c3d4-e5f6-7890-abcd-ceb01cf21171")!
    private let sessionRate: SampleRate = 10
    private let traceRate: SampleRate = 20

    /// Cores are retained for the test's lifetime: `SessionSampler` holds its core weakly, so a
    /// released core would silently report no session.
    private var cores: [FeatureRegistrationCoreMock] = []

    override func tearDown() {
        cores = []
        super.tearDown()
    }

    private func makeSessionSampling() -> SessionSamplerMock {
        SessionSamplerMock(
            identity: .init(
                sessionID: "a1b2c3d4-e5f6-7890-abcd-ceb01cf21171",
                sampler: DeterministicSampler(uuid: sessionUUID, samplingRate: sessionRate)
            )
        )
    }

    /// Wraps `provider` in a core so the subject resolves it exactly as production does.
    private func sampler(for provider: SessionSamplerMock) -> SessionSampler {
        let core = FeatureRegistrationCoreMock()
        try? core.register(feature: provider)
        cores.append(core)
        return core.sessionSampler
    }

    func testWhenARUMSessionIsActive_thenTheTraceRateIsNotComposedWithTheSessionRate() {
        // Given
        let sessionSampling = makeSessionSampling()
        let provider = SamplerProvider(sampleRate: traceRate, sessionSampler: sampler(for: sessionSampling))

        // When
        let sampler = provider.sampler

        // Then — the trace rate is reported and applied as configured
        XCTAssertEqual(sampler.samplingRate, traceRate)
        XCTAssertTrue(
            sampler.sample(),
            "A 20% trace rate must keep this session; composing it with the 10% session rate would drop it"
        )
        XCTAssertEqual(
            sampler.sample(),
            DeterministicSampler(uuid: sessionUUID, samplingRate: traceRate).isSampled,
            "The decision must match the session seed at the trace rate"
        )
    }

    func testItAsksForTheFeatureRatePolicy() {
        // Given
        let sessionSampling = makeSessionSampling()
        let provider = SamplerProvider(sampleRate: traceRate, sessionSampler: sampler(for: sessionSampling))

        // When
        _ = provider.sampler
        _ = provider.makeSamplerFor(samplingRate: 42)

        // Then
        XCTAssertEqual(sessionSampling.requests.map(\.policy), [.featureRate, .featureRate])
        XCTAssertEqual(sessionSampling.requests.map(\.rate), [traceRate, 42])
    }

    func testCustomSamplingRate_isAlsoSeededBySessionWithoutComposing() {
        // Given
        let sessionSampling = makeSessionSampling()
        let provider = SamplerProvider(sampleRate: 0, sessionSampler: sampler(for: sessionSampling))

        // When — a span asks for its own rate, unrelated to the feature's configured one
        let sampler = provider.makeSamplerFor(samplingRate: traceRate)

        // Then
        XCTAssertEqual(sampler.samplingRate, traceRate)
        XCTAssertTrue(sampler.sample())
    }

    func testTheDecisionIsStableAcrossReads() {
        // Given
        let sessionSampling = makeSessionSampling()
        let provider = SamplerProvider(sampleRate: 50, sessionSampler: sampler(for: sessionSampling))

        // When — a rate that a random sampler would decide differently on nearly every call
        let decisions = (0..<50).map { _ in provider.sampler.sample() }

        // Then
        XCTAssertEqual(Set(decisions).count, 1, "Every span in one session must land on the same side")
    }

    func testWhenNoRUMSessionIsActive_thenTheSamplerIsRandomAtTheTraceRate() {
        // Given — RUM enabled but between sessions, or RUM not enabled at all
        let provider = SamplerProvider(sampleRate: 50, sessionSampler: sampler(for: SessionSamplerMock()))

        // When
        let decisions = (0..<1_000).map { _ in provider.sampler.sample() }

        // Then — nothing to be consistent with, so the decision is drawn per span
        XCTAssertEqual(provider.sampler.samplingRate, 50)
        XCTAssertTrue(decisions.contains(true))
        XCTAssertTrue(decisions.contains(false))
    }

    func testByDefault_thereIsNoSessionAndTheSamplerIsRandom() {
        // The default argument exists so tests and non-RUM setups keep the previous behaviour.
        let provider = SamplerProvider(sampleRate: 100)
        XCTAssertTrue(provider.sampler.sample())
        XCTAssertEqual(provider.makeSamplerFor(samplingRate: 0).sample(), false)
    }
}

extension DatadogTracer_SamplingTests {
    @MainActor
    func testManualConstructorsInstallCapturedOwnershipBeforeDeferredSerialization() throws {
        for customRoot in [false, true] {
            for mode in TraceConstructorCaptureFixture.Mode.allCases {
                let fixture = TraceConstructorCaptureFixture(mode: mode)
                let sessionSampler = fixture.sessionSampler()
                let customRate: SampleRate = mode == .missingSession ? 100 : 37
                let tracer = DatadogTracer.mockWith(
                    featureScope: fixture.scope,
                    samplingProvider: SamplerProvider(sampleRate: 100, sessionSampler: sessionSampler),
                    spanEventBuilder: .mockWith(bundleWithRUM: true)
                )
                let span = customRoot
                    ? tracer.startRootSpan(operationName: "captured-root", customSampleRate: customRate)
                    : tracer.startSpan(operationName: "captured-manual")
                XCTAssertEqual(sessionSampler.richCalls, 1)
                XCTAssertEqual(sessionSampler.legacyCalls, 0)
                XCTAssertEqual(sessionSampler.richPolicies, [.featureRate])
                XCTAssertEqual(sessionSampler.rates, [customRoot ? customRate : 100])
                span.finish()
                XCTAssertEqual(try fixture.scope.spanEventsWritten().count, 0)
                fixture.resolveReceiptAndFlush()
                let events = try fixture.scope.spanEventsWritten()
                XCTAssertEqual(events.count, 1)
                fixture.assertCapturedTags(try XCTUnwrap(events.first))
                XCTAssertEqual(try XCTUnwrap(events.first).samplingRate, customRoot ? Float(customRate / 100) : 1, accuracy: 0.000001)
                XCTAssertEqual(sessionSampler.richCalls, 1)
            }
        }
    }

    @MainActor
    func testManualAndOTelConstructorsUseLegacyCustomProviderExactlyOnce() throws {
        for kind in ["manual", "custom-root", "otel"] {
            let fixture = TraceConstructorCaptureFixture(mode: .accepted)
            let provider = TraceConstructorLegacyProvider()
            let tracer = DatadogTracer.mockWith(
                featureScope: fixture.scope,
                samplingProvider: provider,
                spanEventBuilder: .mockWith(bundleWithRUM: true)
            )
            if kind == "otel" {
                tracer.spanBuilder(spanName: kind).startSpan().end()
            } else if kind == "custom-root" {
                tracer.startRootSpan(operationName: kind, customSampleRate: 37).finish()
            } else {
                tracer.startSpan(operationName: kind).finish()
            }
            fixture.scope.flushDeferredEventWriteContexts()
            let events = try fixture.scope.spanEventsWritten()
            XCTAssertEqual(events.count, 1)
            XCTAssertEqual(events.first?.tags[SpanTags.rumViewID], "view-b")
            XCTAssertEqual(events.first?.tags[SpanTags.rumActionID], "action-b")
            XCTAssertEqual(provider.defaultReads, kind == "custom-root" ? 0 : 1)
            XCTAssertEqual(provider.customRates, kind == "custom-root" ? [37] : [])
        }
    }

    @MainActor
    func testManualAndOTelConstructorsUseLegacySessionDecisionExactlyOnce() throws {
        for kind in ["manual", "custom-root", "otel"] {
            let fixture = TraceConstructorCaptureFixture(mode: .accepted)
            let sessionSampler = TraceConstructorLegacySessionSampler()
            let tracer = DatadogTracer.mockWith(
                featureScope: fixture.scope,
                samplingProvider: SamplerProvider(sampleRate: 100, sessionSampler: sessionSampler),
                spanEventBuilder: .mockWith(bundleWithRUM: true)
            )
            if kind == "otel" {
                tracer.spanBuilder(spanName: kind).startSpan().end()
            } else if kind == "custom-root" {
                tracer.startRootSpan(operationName: kind, customSampleRate: 37).finish()
            } else {
                tracer.startSpan(operationName: kind).finish()
            }
            fixture.scope.flushDeferredEventWriteContexts()
            let events = try fixture.scope.spanEventsWritten()
            XCTAssertEqual(events.count, 1)
            XCTAssertEqual(events.first?.tags[SpanTags.rumViewID], "view-b")
            XCTAssertEqual(sessionSampler.policies, [.featureRate])
            XCTAssertEqual(sessionSampler.rates, kind == "custom-root" ? [37] : [100])
        }
    }
}

// Shared by the actual manual, automatic and OTel constructor tests in this target.
final class TraceConstructorCaptureFixture {
    enum Mode: CaseIterable {
        case accepted, rejected, capturedNil, invalidated, foreignSession, missingSession
    }

    let mode: Mode
    let owner = RUMContextHandoff.Owner()
    let original: RUMCoreContext
    let receipt: RUMContextHandoff.ActionReceipt
    let value: RUMContextHandoff.CurrentValue
    let scope: FeatureScopeMock

    init(mode: Mode) {
        self.mode = mode
        original = RUMCoreContext(
            applicationID: "application-a",
            sessionID: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa",
            sessionSampler: DeterministicSampler(seed: 42, samplingRate: 100),
            viewID: "view-a",
            userActionID: "prior-action-a"
        )
        receipt = RUMContextHandoff.ActionReceipt(owner: owner, context: original)
        value = RUMContextHandoff.CurrentValue(
            rumContext: mode == .capturedNil ? nil : original,
            sceneIdentifier: "scene-a",
            hasPendingUserAction: true,
            excludedUserActionID: original.userActionID,
            actionReceipt: receipt
        )
        var legacy: DatadogContext = .mockAny()
        legacy.set(additionalContext: RUMCoreContext(
            applicationID: "application-b",
            sessionID: "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb",
            sessionSampler: DeterministicSampler(seed: 43, samplingRate: 100),
            viewID: "view-b",
            userActionID: "action-b"
        ))
        legacy.userInfo = UserInfo(id: "before-sampling")
        scope = FeatureScopeMock(context: legacy, deferEventWriteContext: true)
    }

    func sessionSampler() -> TraceConstructorSessionSampler {
        TraceConstructorSessionSampler(
            decision: mode == .missingSession ? nil : .init(
                sessionID: mode == .foreignSession ? "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb" : original.sessionID,
                isSampled: true
            ),
            capture: .init(owner: owner, value: value)
        )
    }

    func resolveReceiptAndFlush() {
        if mode == .rejected {
            receipt.reject()
        } else {
            receipt.accept(sessionID: original.sessionID, viewID: "view-a", actionID: "accepted-action-a")
        }
        if mode == .invalidated { owner.invalidate() }
        var delivery = scope.contextMock
        delivery.set(additionalContext: RUMCoreContext(
            applicationID: "application-c",
            sessionID: "cccccccc-cccc-cccc-cccc-cccccccccccc",
            sessionSampler: DeterministicSampler(seed: 44, samplingRate: 100),
            viewID: "view-c",
            userActionID: "action-c"
        ))
        scope.contextMock = delivery
        scope.flushDeferredEventWriteContexts()
    }

    func assertCapturedTags(_ span: SpanEvent, file: StaticString = #filePath, line: UInt = #line) {
        let keepsView = mode == .accepted || mode == .rejected
        XCTAssertEqual(span.tags[SpanTags.rumApplicationID], keepsView ? original.applicationID : nil, file: file, line: line)
        XCTAssertEqual(span.tags[SpanTags.rumSessionID], keepsView ? original.sessionID : nil, file: file, line: line)
        XCTAssertEqual(span.tags[SpanTags.rumViewID], keepsView ? "view-a" : nil, file: file, line: line)
        XCTAssertEqual(span.tags[SpanTags.rumActionID], mode == .accepted ? "accepted-action-a" : nil, file: file, line: line)
    }
}

final class TraceConstructorSessionSampler: SessionSamplerWithRUMContext {
    let snapshot: RUMSessionSamplingContext
    private(set) var richCalls = 0
    private(set) var legacyCalls = 0
    private(set) var richPolicies: [SamplingRatePolicy] = []
    private(set) var legacyPolicies: [SamplingRatePolicy] = []
    private(set) var rates: [SampleRate] = []
    var onRichDecision: (() -> Void)?

    init(decision: SessionSamplingDecision?, capture: RUMContextHandoff.Capture?) {
        snapshot = .init(decision: decision, capture: capture)
    }

    func decision(for policy: SamplingRatePolicy, rate: SampleRate) -> SessionSamplingDecision? {
        legacyCalls += 1
        legacyPolicies.append(policy)
        return snapshot.decision
    }

    func decisionWithRUMContext(for policy: SamplingRatePolicy, rate: SampleRate) -> RUMSessionSamplingContext {
        richCalls += 1
        richPolicies.append(policy)
        rates.append(rate)
        onRichDecision?()
        return snapshot
    }
}

final class TraceConstructorLegacyProvider: TracerSamplerProvider, @unchecked Sendable {
    private(set) var defaultReads = 0
    private(set) var customRates: [SampleRate] = []

    var sampler: Sampling {
        defaultReads += 1
        return Sampler(samplingRate: 100)
    }

    func makeSamplerFor(samplingRate: SampleRate) -> Sampling {
        customRates.append(samplingRate)
        return DeterministicSampler(seed: 0, samplingRate: samplingRate)
    }
}

final class TraceConstructorLegacySessionSampler: SessionSampler {
    private(set) var policies: [SamplingRatePolicy] = []
    private(set) var rates: [SampleRate] = []

    func decision(for policy: SamplingRatePolicy, rate: SampleRate) -> SessionSamplingDecision? {
        policies.append(policy)
        rates.append(rate)
        return .init(sessionID: "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb", isSampled: true)
    }
}
