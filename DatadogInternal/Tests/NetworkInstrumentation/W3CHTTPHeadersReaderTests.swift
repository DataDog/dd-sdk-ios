/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import DatadogInternal

class W3CHTTPHeadersReaderTests: XCTestCase {
    func testW3CHTTPHeadersReaderReadsSingleHeader() {
        let w3cHTTPHeadersReader = W3CHTTPHeadersReader(httpHeaderFields: ["traceparent": "00-4d2-929-01"])
        let ids = w3cHTTPHeadersReader.read()

        XCTAssertEqual(ids?.traceID, TraceID(idLo: 1_234))
        XCTAssertEqual(ids?.spanID, SpanID(2_345))
        XCTAssertNil(ids?.parentSpanID)
        XCTAssertEqual(w3cHTTPHeadersReader.samplingPriority, .autoKeep)
        XCTAssertNil(w3cHTTPHeadersReader.samplingDecisionMaker)
        XCTAssertEqual(w3cHTTPHeadersReader.sampled, true)
    }

    func testW3CHTTPHeadersReaderReadsSingleHeaderWithSampling() {
        let w3cHTTPHeadersReader = W3CHTTPHeadersReader(httpHeaderFields: ["traceparent": "00-0-0-00"])
        let ids = w3cHTTPHeadersReader.read()

        XCTAssertNil(ids?.traceID)
        XCTAssertNil(ids?.spanID)
        XCTAssertNil(ids?.parentSpanID)
        XCTAssertEqual(w3cHTTPHeadersReader.samplingPriority, .autoDrop)
        XCTAssertNil(w3cHTTPHeadersReader.samplingDecisionMaker)
        XCTAssertEqual(w3cHTTPHeadersReader.sampled, false)
    }

    func testReadingSampledTraceContext() {
        let writer = W3CHTTPHeadersWriter(traceContextInjection: .all)
        writer.write(traceContext: .mockWith(
            samplingPriority: .autoKeep,
            samplingDecisionMaker: .agentRate
        ))

        let reader = W3CHTTPHeadersReader(httpHeaderFields: writer.traceHeaderFields)
        XCTAssertNotNil(reader.read(), "When sampled, it should return trace context")
        XCTAssertEqual(reader.samplingPriority, .autoKeep)
        XCTAssertNil(reader.samplingDecisionMaker)
        XCTAssertEqual(reader.sampled, true)
    }

    func testReadingNotSampledTraceContext_givenTraceContextInjectionIsAll() {
        let writer = W3CHTTPHeadersWriter(traceContextInjection: .all)
        writer.write(traceContext: .mockWith(
            samplingPriority: .autoDrop,
            samplingDecisionMaker: .agentRate
        ))

        let reader = W3CHTTPHeadersReader(httpHeaderFields: writer.traceHeaderFields)
        XCTAssertNil(reader.read(), "When not sampled, it should return no trace context")
        XCTAssertEqual(reader.samplingPriority, .autoDrop)
        XCTAssertNil(reader.samplingDecisionMaker)
        XCTAssertEqual(reader.sampled, false)
    }

    func testReadingManuallyKeptTraceContext() {
        let writer = W3CHTTPHeadersWriter(traceContextInjection: .all)
        writer.write(traceContext: .mockWith(
            samplingPriority: .manualKeep,
            samplingDecisionMaker: .manual
        ))

        let reader = W3CHTTPHeadersReader(httpHeaderFields: writer.traceHeaderFields)
        XCTAssertNotNil(reader.read(), "When sampled, it should return trace context")

        // W3C reader is based on the non-vendor-specific standard header so we only
        // read values 0 or 1, not -1 and 2. Therefore we can't tell apart between
        // .autoKeep and .manualKeep
        XCTAssertEqual(reader.samplingPriority, .autoKeep)
        XCTAssertNil(reader.samplingDecisionMaker)
        XCTAssertEqual(reader.sampled, true)
    }

    func testReadingManuallyDroppedTraceContext_givenTraceContextInjectionIsAll() {
        let writer = W3CHTTPHeadersWriter(traceContextInjection: .all)
        writer.write(traceContext: .mockWith(
            samplingPriority: .manualDrop,
            samplingDecisionMaker: .manual
        ))

        let reader = W3CHTTPHeadersReader(httpHeaderFields: writer.traceHeaderFields)
        XCTAssertNil(reader.read(), "When not sampled, it should return no trace context")

        // W3C reader is based on the non-vendor-specific standard header so we only
        // read values 0 or 1, not -1 and 2. Therefore we can't tell apart between
        // .autoDrop and .manualDrop
        XCTAssertEqual(reader.samplingPriority, .autoDrop)
        XCTAssertNil(reader.samplingDecisionMaker)
        XCTAssertEqual(reader.sampled, false)
    }

    func testReadingNotSampledTraceContext_givenTraceContextInjectionIsSampled() {
        let writer = W3CHTTPHeadersWriter(traceContextInjection: .sampled)
        writer.write(traceContext: .mockWith(
            samplingPriority: .autoDrop,
            samplingDecisionMaker: .agentRate
        ))

        let reader = W3CHTTPHeadersReader(httpHeaderFields: writer.traceHeaderFields)
        XCTAssertNil(reader.read(), "When not sampled, it should not return trace context")
        XCTAssertNil(reader.samplingPriority)
        XCTAssertNil(reader.samplingDecisionMaker)
        XCTAssertNil(reader.sampled)
    }

    func testReadingManuallyDroppedTraceContext_givenTraceContextInjectionIsSampled() {
        let writer = W3CHTTPHeadersWriter(traceContextInjection: .sampled)
        writer.write(traceContext: .mockWith(
            samplingPriority: .manualDrop,
            samplingDecisionMaker: .manual
        ))

        let reader = W3CHTTPHeadersReader(httpHeaderFields: writer.traceHeaderFields)
        XCTAssertNil(reader.read(), "When not sampled, it should not return trace context")
        XCTAssertNil(reader.samplingPriority)
        XCTAssertNil(reader.samplingDecisionMaker)
        XCTAssertNil(reader.sampled)
    }
}
