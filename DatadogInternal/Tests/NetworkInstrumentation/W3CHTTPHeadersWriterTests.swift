/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import TestUtilities
import DatadogInternal

class W3CHTTPHeadersWriterTests: XCTestCase {
    func testWritingSampledTraceContext_withHeadBasedSamplingStrategy() {
        let writer = W3CHTTPHeadersWriter(
            samplingStrategy: .headBased,
            tracestate: [
                W3CHTTPHeaders.Constants.origin: W3CHTTPHeaders.Constants.originRUM
            ],
            traceContextInjection: .all
        )

        writer.write(
            traceContext: .mockWith(
                traceID: .init(idHi: 1_234, idLo: 1_234),
                spanID: 2_345,
                isKept: true,
                rumSessionId: "abcdef01-2345-6789-abcd-ef0123456789"
            )
        )

        let headers = writer.traceHeaderFields
        XCTAssertEqual(headers[W3CHTTPHeaders.traceparent], "00-00000000000004d200000000000004d2-0000000000000929-01")
        XCTAssertEqual(headers[W3CHTTPHeaders.tracestate], "dd=o:rum;p:0000000000000929;s:1")
        XCTAssertEqual(headers[W3CHTTPHeaders.baggage], "session.id=abcdef01-2345-6789-abcd-ef0123456789")
    }

    func testWritingDroppedTraceContext_withHeadBasedSamplingStrategy() {
        let writer = W3CHTTPHeadersWriter(
            samplingStrategy: .headBased,
            tracestate: [
                W3CHTTPHeaders.Constants.origin: W3CHTTPHeaders.Constants.originRUM
            ],
            traceContextInjection: .all
        )

        writer.write(
            traceContext: .mockWith(
                traceID: .init(idHi: 1_234, idLo: 1_234),
                spanID: 2_345,
                parentSpanID: 5_678,
                isKept: false,
                rumSessionId: "abcdef01-2345-6789-abcd-ef0123456789"
            )
        )

        let headers = writer.traceHeaderFields
        XCTAssertEqual(headers[W3CHTTPHeaders.traceparent], "00-00000000000004d200000000000004d2-0000000000000929-00")
        XCTAssertEqual(headers[W3CHTTPHeaders.tracestate], "dd=o:rum;p:0000000000000929;s:0")
        XCTAssertEqual(headers[W3CHTTPHeaders.baggage], "session.id=abcdef01-2345-6789-abcd-ef0123456789")
    }

    func testWritingSampledTraceContext_withCustomSamplingStrategy() {
        let writer = W3CHTTPHeadersWriter(
            samplingStrategy: .headBased,
            tracestate: [
                W3CHTTPHeaders.Constants.origin: W3CHTTPHeaders.Constants.originRUM
            ],
            traceContextInjection: .all
        )

        writer.write(
            traceContext: .mockWith(
                traceID: .init(idHi: 1_234, idLo: 1_234),
                spanID: 2_345,
                isKept: true,
                rumSessionId: "abcdef01-2345-6789-abcd-ef0123456789"
            )
        )

        let headers = writer.traceHeaderFields
        XCTAssertEqual(headers[W3CHTTPHeaders.traceparent], "00-00000000000004d200000000000004d2-0000000000000929-01")
        XCTAssertEqual(headers[W3CHTTPHeaders.tracestate], "dd=o:rum;p:0000000000000929;s:1")
        XCTAssertEqual(headers[W3CHTTPHeaders.baggage], "session.id=abcdef01-2345-6789-abcd-ef0123456789")
    }

    func testWritingDroppedTraceContext_withCustomSamplingStrategy() {
        let writer = W3CHTTPHeadersWriter(
            samplingStrategy: .headBased,
            tracestate: [
                W3CHTTPHeaders.Constants.origin: W3CHTTPHeaders.Constants.originRUM
            ],
            traceContextInjection: .all
        )

        writer.write(
            traceContext: .mockWith(
                traceID: .init(idHi: 1_234, idLo: 1_234),
                spanID: 2_345,
                parentSpanID: 5_678,
                isKept: false,
                rumSessionId: "abcdef01-2345-6789-abcd-ef0123456789"
            )
        )

        let headers = writer.traceHeaderFields
        XCTAssertEqual(headers[W3CHTTPHeaders.traceparent], "00-00000000000004d200000000000004d2-0000000000000929-00")
        XCTAssertEqual(headers[W3CHTTPHeaders.tracestate], "dd=o:rum;p:0000000000000929;s:0")
        XCTAssertEqual(headers[W3CHTTPHeaders.baggage], "session.id=abcdef01-2345-6789-abcd-ef0123456789")
    }

    // The sampling based on session ID should pass at 18% sampling rate and fail at 17%
    func testWritingSampledTraceContext_withCustomSamplingStrategy_18percent() {
        let writer = W3CHTTPHeadersWriter(
            samplingStrategy: .headBased,
            tracestate: [
                W3CHTTPHeaders.Constants.origin: W3CHTTPHeaders.Constants.originRUM
            ],
            traceContextInjection: .sampled
        )

        writer.write(
            traceContext: .mockWith(
                traceID: .init(idHi: 1_234, idLo: 1_234),
                spanID: 2_345,
                parentSpanID: 5_678,
                isKept: true,
                rumSessionId: "abcdef01-2345-6789-abcd-ef0123456789"
            )
        )

        let headers = writer.traceHeaderFields
        XCTAssertEqual(headers[W3CHTTPHeaders.traceparent], "00-00000000000004d200000000000004d2-0000000000000929-01")
        XCTAssertEqual(headers[W3CHTTPHeaders.tracestate], "dd=o:rum;p:0000000000000929;s:1")
        XCTAssertEqual(headers[W3CHTTPHeaders.baggage], "session.id=abcdef01-2345-6789-abcd-ef0123456789")
    }

    func testWritingDroppedTraceContext_withCustomSamplingStrategy_17percent() {
        let writer = W3CHTTPHeadersWriter(
            samplingStrategy: .headBased,
            tracestate: [
                W3CHTTPHeaders.Constants.origin: W3CHTTPHeaders.Constants.originRUM
            ],
            traceContextInjection: .sampled
        )

        writer.write(
            traceContext: .mockWith(
                traceID: .init(idHi: 1_234, idLo: 1_234),
                spanID: 2_345,
                isKept: false,
                rumSessionId: "abcdef01-2345-6789-abcd-ef0123456789"
            )
        )

        let headers = writer.traceHeaderFields
        XCTAssertNil(headers[W3CHTTPHeaders.traceparent])
        XCTAssertNil(headers[W3CHTTPHeaders.tracestate])
        XCTAssertNil(headers[W3CHTTPHeaders.baggage])
    }

    func testNotWritingDroppedTraceContext_withCustomSamplingStrategy() {
        let writer = W3CHTTPHeadersWriter(
            samplingStrategy: .headBased,
            tracestate: [
                W3CHTTPHeaders.Constants.origin: W3CHTTPHeaders.Constants.originRUM
            ],
            traceContextInjection: .sampled
        )

        writer.write(
            traceContext: .mockWith(
                traceID: .init(idHi: 1_234, idLo: 1_234),
                spanID: 2_345,
                parentSpanID: 5_678,
                isKept: false,
                rumSessionId: "abcdef01-2345-6789-abcd-ef0123456789"
            )
        )

        let headers = writer.traceHeaderFields
        XCTAssertNil(headers[W3CHTTPHeaders.traceparent])
        XCTAssertNil(headers[W3CHTTPHeaders.tracestate])
        XCTAssertNil(headers[W3CHTTPHeaders.baggage])
    }
}
