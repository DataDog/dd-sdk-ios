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
            localTraceSampler: Sampler(samplingRate: sampleRate),
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
        XCTAssertGreaterThan(events.filter({ $0.isKept }).count, 1, "Some spans should be kept")
        XCTAssertEqual(events.filter({ !$0.isKept }).count, 0, "Not kept spans should be dropped")
    }

    func testRecordingCustomSampleRateInRootSpanEvent() throws {
        // When
        let tracer = createTracer(sampleRate: 5)
        (0..<10).forEach { _ in
            let span = tracer.startRootSpan(operationName: .mockAny(), customSamplingRate: 42)
            span.finish()
        }

        // Then
        let events = try XCTUnwrap(featureScope.spanEventsWritten())
        XCTAssertEqual(events.filter({ $0.samplingRate == 0.42 }).count, 10)
    }

    func testCustomSamplingRatePropagatesToChildSpans() throws {
        // When
        let tracer = createTracer(sampleRate: 5)
        let root = tracer.startRootSpan(operationName: .mockAny(), customSamplingRate: 37)
        let child = tracer.startSpan(operationName: .mockAny(), childOf: root.context)
        let grandChild = tracer.startSpan(operationName: .mockAny(), childOf: child.context)
        grandChild.finish()
        child.finish()
        root.finish()

        // Then
        let events = try XCTUnwrap(featureScope.spanEventsWritten())
        XCTAssertEqual(events.count, 3)
        XCTAssertEqual(events.filter({ $0.samplingRate == 0.37 }).count, 3)
    }

    func testRecordingSampledSpan() throws {
        // When
        let tracer = createTracer(sampleRate: 100)
        let span = tracer.startSpan(operationName: .mockAny())
        span.finish()

        // Then
        let event = try XCTUnwrap(featureScope.spanEventsWritten().first)
        XCTAssertEqual(event.samplingRate, 1)
        XCTAssertTrue(event.isKept)
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
            XCTAssertEqual(events.filter({ $0.isKept }).count, 3, "All spans must be kept")
        }
    }
}

extension FeatureScopeMock {
    func spanEventsWritten() throws -> [SpanEvent] {
        let events: [SpanEventsEnvelope] = eventsWritten()
        return events.reduce([], { acc, next in acc + next.spans })
    }
}
