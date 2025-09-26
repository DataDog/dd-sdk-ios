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
    }

    func testW3CHTTPHeadersReaderReadsSingleHeaderWithSampling() {
        let w3cHTTPHeadersReader = W3CHTTPHeadersReader(httpHeaderFields: ["traceparent": "00-0-0-00"])
        let ids = w3cHTTPHeadersReader.read()

        XCTAssertNil(ids?.traceID)
        XCTAssertNil(ids?.spanID)
        XCTAssertNil(ids?.parentSpanID)
    }

    func testReadingSampledTraceContext() {
        let writer = W3CHTTPHeadersWriter(traceContextInjection: .all)
        writer.write(traceContext: .mockWith(isKept: true))

        let reader = W3CHTTPHeadersReader(httpHeaderFields: writer.traceHeaderFields)
        XCTAssertNotNil(reader.read(), "When sampled, it should return trace context")
        XCTAssertEqual(reader.sampled, true)
    }

    func testReadingNotSampledTraceContext_givenTraceContextInjectionIsAll() {
        let writer = W3CHTTPHeadersWriter(traceContextInjection: .all)
        writer.write(traceContext: .mockWith(isKept: false))

        let reader = W3CHTTPHeadersReader(httpHeaderFields: writer.traceHeaderFields)
        XCTAssertNil(reader.read(), "When not sampled, it should return no trace context")
        XCTAssertEqual(reader.sampled, false)
    }

    func testReadingNotSampledTraceContext_givenTraceContextInjectionIsSampled() {
        let writer = W3CHTTPHeadersWriter(traceContextInjection: .sampled)
        writer.write(traceContext: .mockWith(isKept: false))

        let reader = W3CHTTPHeadersReader(httpHeaderFields: writer.traceHeaderFields)
        XCTAssertNil(reader.read(), "When not sampled, it should not return trace context")
        XCTAssertNil(reader.sampled)
    }
}
