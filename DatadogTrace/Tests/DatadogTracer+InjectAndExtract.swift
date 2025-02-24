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
    var extractedIsKept: Bool? = nil

    func read() -> (traceID: TraceID, spanID: SpanID, parentSpanID: SpanID?)? { extractedIDs }
    var sampled: Bool? { extractedIsKept }
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
            isKept: .random()
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
            isKept: spanContext.isKept,
            rumSessionId: nil
        )
        XCTAssertEqual(writer.injectedTraceContext, expectedTraceContext)
    }

    func testExtractnigSpanContextFromReader() throws {
        // Given
        let tracer = createTracer(sampleRate: 42)
        let reader = MockReader()
        let ids: (traceID: TraceID, spanID: SpanID, parentSpanID: SpanID?) = (.mockRandom(), .mockRandom(), .mockRandom())
        let isKept: Bool = .mockRandom()
        reader.extractedIDs = ids
        reader.extractedIsKept = isKept

        // When
        let spanContext = try XCTUnwrap(tracer.extract(reader: reader) as? DDSpanContext)

        // Then
        XCTAssertEqual(spanContext.traceID, ids.traceID)
        XCTAssertEqual(spanContext.spanID, ids.spanID)
        XCTAssertEqual(spanContext.parentSpanID, ids.parentSpanID)
        XCTAssertEqual(spanContext.sampleRate, 42)
        XCTAssertEqual(spanContext.isKept, isKept)
    }

    func testExtractsEmptySpanContextFromReader() throws {
        // Given
        let tracer = createTracer(sampleRate: 42)
        let reader = MockReader()
        reader.extractedIDs = nil
        reader.extractedIsKept = nil

        // When
        XCTAssertNil(tracer.extract(reader: reader))
    }
}
