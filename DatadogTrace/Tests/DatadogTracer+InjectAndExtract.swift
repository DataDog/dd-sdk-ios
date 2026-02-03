/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import TestUtilities
import DatadogInternal
@testable import DatadogTrace

private class MockWriter: OTFormatWriter, TracePropagationHeadersWriter {
    var traceHeaderFields: [String: String] = [:]
    var injectedTraceContext: TraceContext?
    func write(traceContext: TraceContext) { injectedTraceContext = traceContext }
}

private class MockReader: OTFormatReader, TracePropagationHeadersReader {
    var extractedIDs: (traceID: TraceID, spanID: SpanID, parentSpanID: SpanID?)? = nil
    var extractedSamplingPriority: SamplingPriority? = nil
    var extractedSamplingDecisionMaker: SamplingMechanismType? = nil

    func read() -> (traceID: TraceID, spanID: SpanID, parentSpanID: SpanID?)? { extractedIDs }
    var samplingPriority: DatadogInternal.SamplingPriority? { extractedSamplingPriority }
    var samplingDecisionMaker: DatadogInternal.SamplingMechanismType? { extractedSamplingDecisionMaker }
}

class DatadogTracer_InjectAndExtract: XCTestCase {
    private func createTracer(sampleRate: Float) -> DatadogTracer {
        return DatadogTracer(
            featureScope: NOPFeatureScope(),
            localTraceSampler: Sampler(samplingRate: sampleRate),
            tags: [:],
            traceIDGenerator: DefaultTraceIDGenerator(),
            spanIDGenerator: DefaultSpanIDGenerator(),
            dateProvider: DateProviderMock(),
            loggingIntegration: .mockAny(),
            spanEventBuilder: .mockAny()
        )
    }

    func testInjectingSpanContextIntoWriter() {
        // Given
        let spanContext = DDSpanContext(
            traceID: .mockRandom(),
            spanID: .mockRandom(),
            parentSpanID: .mockRandom(),
            baggageItems: .mockAny(),
            sampleRate: .mockRandom(min: 0, max: 100),
            samplingDecision: .mockRandom()
        )

        let tracer = createTracer(sampleRate: 42)
        let writer = MockWriter()
        XCTAssertNil(writer.injectedTraceContext)

        // When
        tracer.inject(spanContext: spanContext, writer: writer)

        // Then
        let expectedTraceContext = TraceContext(
            traceID: spanContext.traceID,
            spanID: spanContext.spanID,
            parentSpanID: spanContext.parentSpanID,
            sampleRate: spanContext.sampleRate,
            samplingPriority: spanContext.samplingDecision.samplingPriority,
            samplingDecisionMaker: spanContext.samplingDecision.decisionMaker,
            rumSessionId: nil
        )
        XCTAssertEqual(writer.injectedTraceContext, expectedTraceContext)
    }

    func testExtractingSpanContextFromReader() throws {
        // Given
        let tracer = createTracer(sampleRate: 42)
        let reader = MockReader()
        let ids: (traceID: TraceID, spanID: SpanID, parentSpanID: SpanID?) = (.mockRandom(), .mockRandom(), .mockRandom())
        let samplingDecision: SamplingDecision = .mockRandom()
        reader.extractedIDs = ids
        reader.extractedSamplingPriority = samplingDecision.samplingPriority
        reader.extractedSamplingDecisionMaker = samplingDecision.decisionMaker

        // When
        let spanContext = try XCTUnwrap(tracer.extract(reader: reader) as? DDSpanContext)

        // Then
        XCTAssertEqual(spanContext.traceID, ids.traceID)
        XCTAssertEqual(spanContext.spanID, ids.spanID)
        XCTAssertEqual(spanContext.parentSpanID, ids.parentSpanID)
        XCTAssertEqual(spanContext.sampleRate, 42)
        XCTAssertEqual(spanContext.samplingDecision.samplingPriority, samplingDecision.samplingPriority)
        XCTAssertEqual(spanContext.samplingDecision.decisionMaker, samplingDecision.decisionMaker)
    }

    func testExtractsEmptySpanContextFromReader() throws {
        // Given
        let tracer = createTracer(sampleRate: 42)
        let reader = MockReader()
        reader.extractedIDs = nil
        reader.extractedSamplingPriority = nil
        reader.extractedSamplingDecisionMaker = nil

        // When
        XCTAssertNil(tracer.extract(reader: reader))
    }
}
