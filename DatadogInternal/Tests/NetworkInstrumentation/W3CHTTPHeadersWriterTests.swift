/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import TestUtilities
import DatadogInternal

class W3CHTTPHeadersWriterTests: XCTestCase {
    func testWritingSampledTraceContext_withAutoSamplingStrategy() {
        let writer = W3CHTTPHeadersWriter(
            samplingStrategy: .headBased,
            tracestate: [
                W3CHTTPHeaders.Constants.origin: W3CHTTPHeaders.Constants.originRUM
            ]
        )

        writer.write(
            traceContext: .mockWith(
                traceID: .init(idHi: 1_234, idLo: 1_234),
                spanID: 2_345,
                isKept: true
            )
        )

        let headers = writer.traceHeaderFields
        XCTAssertEqual(headers[W3CHTTPHeaders.traceparent], "00-00000000000004d200000000000004d2-0000000000000929-01")
        XCTAssertEqual(headers[W3CHTTPHeaders.tracestate], "dd=o:rum;p:0000000000000929;s:1")
    }

    func testWritingDroppedTraceContext_withAutoSamplingStrategy() {
        let writer = W3CHTTPHeadersWriter(
            samplingStrategy: .headBased,
            tracestate: [
                W3CHTTPHeaders.Constants.origin: W3CHTTPHeaders.Constants.originRUM
            ]
        )

        writer.write(
            traceContext: .mockWith(
                traceID: .init(idHi: 1_234, idLo: 1_234),
                spanID: 2_345,
                parentSpanID: 5_678,
                isKept: false
            )
        )

        let headers = writer.traceHeaderFields
        XCTAssertEqual(headers[W3CHTTPHeaders.traceparent], "00-00000000000004d200000000000004d2-0000000000000929-00")
        XCTAssertEqual(headers[W3CHTTPHeaders.tracestate], "dd=o:rum;p:0000000000000929;s:0")
    }

    func testWritingSampledTraceContext_withCustomSamplingStrategy() {
        let writer = W3CHTTPHeadersWriter(
            samplingStrategy: .custom(sampleRate: 100),
            tracestate: [
                W3CHTTPHeaders.Constants.origin: W3CHTTPHeaders.Constants.originRUM
            ]
        )

        writer.write(
            traceContext: .mockWith(
                traceID: .init(idHi: 1_234, idLo: 1_234),
                spanID: 2_345,
                isKept: .random()
            )
        )

        let headers = writer.traceHeaderFields
        XCTAssertEqual(headers[W3CHTTPHeaders.traceparent], "00-00000000000004d200000000000004d2-0000000000000929-01")
        XCTAssertEqual(headers[W3CHTTPHeaders.tracestate], "dd=o:rum;p:0000000000000929;s:1")
    }

    func testWritingDroppedTraceContext_withCustomSamplingStrategy() {
        let writer = W3CHTTPHeadersWriter(
            samplingStrategy: .custom(sampleRate: 0),
            tracestate: [
                W3CHTTPHeaders.Constants.origin: W3CHTTPHeaders.Constants.originRUM
            ]
        )

        writer.write(
            traceContext: .mockWith(
                traceID: .init(idHi: 1_234, idLo: 1_234),
                spanID: 2_345,
                parentSpanID: 5_678,
                isKept: .random()
            )
        )

        let headers = writer.traceHeaderFields
        XCTAssertEqual(headers[W3CHTTPHeaders.traceparent], "00-00000000000004d200000000000004d2-0000000000000929-00")
        XCTAssertEqual(headers[W3CHTTPHeaders.tracestate], "dd=o:rum;p:0000000000000929;s:0")
    }
}
