/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import TestUtilities
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

    private func makeSessionSampling() -> RUMSessionSamplerProviderMock {
        RUMSessionSamplerProviderMock(
            identity: .init(
                sessionID: "a1b2c3d4-e5f6-7890-abcd-ceb01cf21171",
                sampler: DeterministicSampler(uuid: sessionUUID, samplingRate: sessionRate)
            )
        )
    }

    func testWhenARUMSessionIsActive_thenTheTraceRateIsNotComposedWithTheSessionRate() {
        // Given
        let sessionSampling = makeSessionSampling()
        let provider = SamplerProvider(sampleRate: traceRate, sessionSampling: { sessionSampling })

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
        let provider = SamplerProvider(sampleRate: traceRate, sessionSampling: { sessionSampling })

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
        let provider = SamplerProvider(sampleRate: 0, sessionSampling: { sessionSampling })

        // When — a span asks for its own rate, unrelated to the feature's configured one
        let sampler = provider.makeSamplerFor(samplingRate: traceRate)

        // Then
        XCTAssertEqual(sampler.samplingRate, traceRate)
        XCTAssertTrue(sampler.sample())
    }

    func testTheDecisionIsStableAcrossReads() {
        // Given
        let sessionSampling = makeSessionSampling()
        let provider = SamplerProvider(sampleRate: 50, sessionSampling: { sessionSampling })

        // When — a rate that a random sampler would decide differently on nearly every call
        let decisions = (0..<50).map { _ in provider.sampler.sample() }

        // Then
        XCTAssertEqual(Set(decisions).count, 1, "Every span in one session must land on the same side")
    }

    func testWhenNoRUMSessionIsActive_thenTheSamplerIsRandomAtTheTraceRate() {
        // Given — RUM enabled but between sessions, or RUM not enabled at all
        let provider = SamplerProvider(sampleRate: 50, sessionSampling: { RUMSessionSamplerProviderMock() })

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
