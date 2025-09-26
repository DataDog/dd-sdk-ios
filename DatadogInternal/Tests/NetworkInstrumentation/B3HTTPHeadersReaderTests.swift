/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import TestUtilities
import DatadogInternal

class B3HTTPHeadersReaderTests: XCTestCase {
    func testItReadsSingleHeader() {
        let reader = B3HTTPHeadersReader(httpHeaderFields: ["b3": "4d2-929-1-162e"])

        let ids = reader.read()

        XCTAssertEqual(ids?.traceID, 1_234)
        XCTAssertEqual(ids?.spanID, 2_345)
        XCTAssertEqual(ids?.parentSpanID, 5_678)
    }

    func testItReadsSingleHeaderWithSampling() {
        let reader = B3HTTPHeadersReader(httpHeaderFields: ["b3": "0"])

        let ids = reader.read()

        XCTAssertNil(ids?.traceID)
        XCTAssertNil(ids?.spanID)
        XCTAssertNil(ids?.parentSpanID)
    }

    func testItReadsSingleHeaderWithoutOptionalValues() {
        let reader = B3HTTPHeadersReader(httpHeaderFields: ["b3": "4d2-929"])

        let ids = reader.read()

        XCTAssertEqual(ids?.traceID, 1_234)
        XCTAssertEqual(ids?.spanID, 2_345)
        XCTAssertNil(ids?.parentSpanID)
    }

    func testItReadsMultipleHeader() {
        let reader = B3HTTPHeadersReader(httpHeaderFields: [
            "X-B3-TraceId": "4d2",
            "X-B3-SpanId": "929",
            "X-B3-Sampled": "1",
            "X-B3-ParentSpanId": "162e"
        ])

        let ids = reader.read()

        XCTAssertEqual(ids?.traceID, 1_234)
        XCTAssertEqual(ids?.spanID, 2_345)
        XCTAssertEqual(ids?.parentSpanID, 5_678)
    }

    func testItReadsMultipleHeaderWithSampling() {
        let reader = B3HTTPHeadersReader(httpHeaderFields: [
            "X-B3-Sampled": "0"
        ])

        let ids = reader.read()

        XCTAssertNil(ids?.traceID)
        XCTAssertNil(ids?.spanID)
        XCTAssertNil(ids?.parentSpanID)
    }

    func testItReadsMultipleHeaderWithoutOptionalValues() {
        let reader = B3HTTPHeadersReader(httpHeaderFields: [
            "X-B3-TraceId": "4d2",
            "X-B3-SpanId": "929"
        ])

        let ids = reader.read()

        XCTAssertEqual(ids?.traceID, 1_234)
        XCTAssertEqual(ids?.spanID, 2_345)
        XCTAssertNil(ids?.parentSpanID)
    }

    func testReadingSampledTraceContext() {
        let encoding: B3HTTPHeadersWriter.InjectEncoding = [.multiple, .single].randomElement()!
        let writer = B3HTTPHeadersWriter(injectEncoding: encoding, traceContextInjection: .all)
        writer.write(traceContext: .mockWith(isKept: true))

        let reader = B3HTTPHeadersReader(httpHeaderFields: writer.traceHeaderFields)
        XCTAssertNotNil(reader.read(), "When sampled, it should return trace context")
        XCTAssertEqual(reader.sampled, true)
    }

    func testReadingNotSampledTraceContext_givenTraceContextInjectionIsAll() {
        let encoding: B3HTTPHeadersWriter.InjectEncoding = [.multiple, .single].randomElement()!
        let writer = B3HTTPHeadersWriter(injectEncoding: encoding, traceContextInjection: .all)
        writer.write(traceContext: .mockWith(isKept: false))

        let reader = B3HTTPHeadersReader(httpHeaderFields: writer.traceHeaderFields)
        XCTAssertNil(reader.read(), "When not sampled, it should return no trace context")
        XCTAssertEqual(reader.sampled, false)
    }

    func testReadingNotSampledTraceContext_givenTraceContextInjectionIsSampled() {
        let encoding: B3HTTPHeadersWriter.InjectEncoding = [.multiple, .single].randomElement()!
        let writer = B3HTTPHeadersWriter(injectEncoding: encoding, traceContextInjection: .sampled)
        writer.write(traceContext: .mockWith(isKept: false))

        let reader = B3HTTPHeadersReader(httpHeaderFields: writer.traceHeaderFields)
        XCTAssertNil(reader.read(), "When not sampled, it should return no trace context")
        XCTAssertNil(reader.sampled)
    }
}
