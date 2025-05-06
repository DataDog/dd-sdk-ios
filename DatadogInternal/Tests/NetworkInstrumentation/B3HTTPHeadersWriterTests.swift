/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import TestUtilities
import DatadogInternal

class B3HTTPHeadersWriterTests: XCTestCase {
    func testWritingSampledTraceContext_withSingleEncoding_andAutoSamplingStrategy() {
        let writer = B3HTTPHeadersWriter(
            samplingStrategy: .headBased,
            injectEncoding: .single,
            traceContextInjection: .all
        )

        writer.write(
            traceContext: .mockWith(
                traceID: .init(idHi: 1_234, idLo: 1_234),
                spanID: 2_345,
                parentSpanID: 5_678,
                isKept: true
            )
        )

        let headers = writer.traceHeaderFields
        XCTAssertEqual(headers[B3HTTPHeaders.Single.b3Field], "00000000000004d200000000000004d2-0000000000000929-1-000000000000162e")
    }

    func testWritingDroppedTraceContext_withSingleEncoding_andAutoSamplingStrategy() {
        let writer = B3HTTPHeadersWriter(
            samplingStrategy: .headBased,
            injectEncoding: .single,
            traceContextInjection: .all
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
        XCTAssertEqual(headers[B3HTTPHeaders.Single.b3Field], "0")
    }

    func testWritingSampledTraceContext_withSingleEncoding_andCustomSamplingStrategy() {
        let writer = B3HTTPHeadersWriter(
            samplingStrategy: .headBased,
            injectEncoding: .single,
            traceContextInjection: .all
        )

        writer.write(
            traceContext: .mockWith(
                traceID: .init(idHi: 1_234, idLo: 1_234),
                spanID: 2_345,
                parentSpanID: 5_678,
                isKept: true
            )
        )

        let headers = writer.traceHeaderFields
        XCTAssertEqual(headers[B3HTTPHeaders.Single.b3Field], "00000000000004d200000000000004d2-0000000000000929-1-000000000000162e")
    }

    func testWritingDroppedTraceContext_withSingleEncoding_andCustomSamplingStrategy() {
        let writer = B3HTTPHeadersWriter(
            samplingStrategy: .headBased,
            injectEncoding: .single,
            traceContextInjection: .all
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
        XCTAssertEqual(headers[B3HTTPHeaders.Single.b3Field], "0")
    }

    func testItWritesSingleHeaderWithoutOptionalValues() {
        let writer = B3HTTPHeadersWriter(
            samplingStrategy: .headBased,
            injectEncoding: .single,
            traceContextInjection: .all
        )

        writer.write(
            traceContext: .mockWith(
                traceID: .init(idHi: 1_234, idLo: 1_234),
                spanID: 2_345,
                isKept: true
            )
        )

        let headers = writer.traceHeaderFields
        XCTAssertEqual(headers[B3HTTPHeaders.Single.b3Field], "00000000000004d200000000000004d2-0000000000000929-1")
    }

    func testWritingSampledTraceContext_withMultipleEncoding_andAutoSamplingStrategy() {
        let writer = B3HTTPHeadersWriter(
            samplingStrategy: .headBased,
            injectEncoding: .multiple,
            traceContextInjection: .all
        )

        writer.write(
            traceContext: .mockWith(
                traceID: .init(idHi: 1_234, idLo: 1_234),
                spanID: 2_345,
                parentSpanID: 5_678,
                isKept: true
            )
        )

        let headers = writer.traceHeaderFields
        XCTAssertEqual(headers[B3HTTPHeaders.Multiple.traceIDField], "00000000000004d200000000000004d2")
        XCTAssertEqual(headers[B3HTTPHeaders.Multiple.spanIDField], "0000000000000929")
        XCTAssertEqual(headers[B3HTTPHeaders.Multiple.sampledField], "1")
        XCTAssertEqual(headers[B3HTTPHeaders.Multiple.parentSpanIDField], "000000000000162e")
    }

    func testWritingDroppedTraceContext_withMultipleEncoding_andAutoSamplingStrategy() {
        let writer = B3HTTPHeadersWriter(
            samplingStrategy: .headBased,
            injectEncoding: .multiple,
            traceContextInjection: .all
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
        XCTAssertNil(headers[B3HTTPHeaders.Multiple.traceIDField])
        XCTAssertNil(headers[B3HTTPHeaders.Multiple.spanIDField])
        XCTAssertEqual(headers[B3HTTPHeaders.Multiple.sampledField], "0")
        XCTAssertNil(headers[B3HTTPHeaders.Multiple.parentSpanIDField])
    }

    func testWritingSampledTraceContext_withMultipleEncoding_andCustomSamplingStrategy() {
        let writer = B3HTTPHeadersWriter(
            samplingStrategy: .headBased,
            injectEncoding: .multiple,
            traceContextInjection: .all
        )

        writer.write(
            traceContext: .mockWith(
                traceID: .init(idHi: 1_234, idLo: 1_234),
                spanID: 2_345,
                parentSpanID: 5_678,
                isKept: true
            )
        )

        let headers = writer.traceHeaderFields
        XCTAssertEqual(headers[B3HTTPHeaders.Multiple.traceIDField], "00000000000004d200000000000004d2")
        XCTAssertEqual(headers[B3HTTPHeaders.Multiple.spanIDField], "0000000000000929")
        XCTAssertEqual(headers[B3HTTPHeaders.Multiple.sampledField], "1")
        XCTAssertEqual(headers[B3HTTPHeaders.Multiple.parentSpanIDField], "000000000000162e")
    }

    func testWritingDroppedTraceContext_withMultipleEncoding_andCustomSamplingStrategy() {
        let writer = B3HTTPHeadersWriter(
            samplingStrategy: .headBased,
            injectEncoding: .multiple,
            traceContextInjection: .all
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
        XCTAssertNil(headers[B3HTTPHeaders.Multiple.traceIDField])
        XCTAssertNil(headers[B3HTTPHeaders.Multiple.spanIDField])
        XCTAssertEqual(headers[B3HTTPHeaders.Multiple.sampledField], "0")
        XCTAssertNil(headers[B3HTTPHeaders.Multiple.parentSpanIDField])
    }

    func testItWritesMultipleHeaderWithoutOptionalValues() {
        let writer = B3HTTPHeadersWriter(
            samplingStrategy: .headBased,
            injectEncoding: .multiple,
            traceContextInjection: .all
        )

        writer.write(
            traceContext: .mockWith(
                traceID: .init(idHi: 1_234, idLo: 1_234),
                spanID: 2_345,
                isKept: true
            )
        )

        let headers = writer.traceHeaderFields
        XCTAssertEqual(headers[B3HTTPHeaders.Multiple.traceIDField], "00000000000004d200000000000004d2")
        XCTAssertEqual(headers[B3HTTPHeaders.Multiple.spanIDField], "0000000000000929")
        XCTAssertEqual(headers[B3HTTPHeaders.Multiple.sampledField], "1")
        XCTAssertNil(headers[B3HTTPHeaders.Multiple.parentSpanIDField])
    }

    // The sampling based on session ID should pass at 18% sampling rate and fail at 17%
    func testWritingSampledTraceContext_withCustomSamplingStrategy_18percent() {
        let writer = B3HTTPHeadersWriter(samplingStrategy: .headBased, injectEncoding: .multiple, traceContextInjection: .sampled)

        writer.write(
            traceContext: .mockWith(
                traceID: .init(idHi: 1_234, idLo: 1_234),
                spanID: 2_345,
                isKept: true,
                rumSessionId: "abcdef01-2345-6789-abcd-ef0123456789"
            )
        )

        let headers = writer.traceHeaderFields
        XCTAssertEqual(headers[B3HTTPHeaders.Multiple.traceIDField], "00000000000004d200000000000004d2")
        XCTAssertEqual(headers[B3HTTPHeaders.Multiple.spanIDField], "0000000000000929")
        XCTAssertEqual(headers[B3HTTPHeaders.Multiple.sampledField], "1")
    }

    func testWritingDroppedTraceContext_withCustomSamplingStrategy_17percent() {
        let writer = B3HTTPHeadersWriter(samplingStrategy: .headBased, injectEncoding: .multiple, traceContextInjection: .sampled)

        writer.write(
            traceContext: .mockWith(
                traceID: .init(idHi: 1_234, idLo: 1_234),
                spanID: 2_345,
                isKept: false,
                rumSessionId: "abcdef01-2345-6789-abcd-ef0123456789"
            )
        )

        let headers = writer.traceHeaderFields
        XCTAssertNil(headers[B3HTTPHeaders.Multiple.traceIDField])
        XCTAssertNil(headers[B3HTTPHeaders.Multiple.spanIDField])
        XCTAssertNil(headers[B3HTTPHeaders.Multiple.sampledField])
        XCTAssertNil(headers[B3HTTPHeaders.Multiple.parentSpanIDField])
        XCTAssertNil(headers[W3CHTTPHeaders.baggage])
    }
}
