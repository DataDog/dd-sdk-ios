/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
@testable import Datadog

class OTelHTTPHeadersWriterTests: XCTestCase {
    func testOTelHTTPHeadersWriterwritesSingleHeader() {
        let sampler: Sampler = .mockKeepAll()
        let context: OTSpanContext = DDSpanContext.mockWith(
            traceID: .mock(1_234),
            spanID: .mock(2_345),
            parentSpanID: .mock(5_678),
            baggageItems: .mockAny()
        )
        let oTelHTTPHeadersWriter = OTelHTTPHeadersWriter(
            sampler: sampler,
            injectEncoding: .single
        )
        oTelHTTPHeadersWriter.inject(spanContext: context)

        let headers = oTelHTTPHeadersWriter.tracePropagationHTTPHeaders
        XCTAssertEqual(headers[OTelHTTPHeaders.Single.b3Field], "000000000000000000000000000004d2-0000000000000929-1-000000000000162e")
    }

    func testOTelHTTPHeadersWriterwritesSingleHeaderWithSampling() {
        let sampler: Sampler = .mockRejectAll()
        let context: OTSpanContext = DDSpanContext.mockWith(
            traceID: .mock(1_234),
            spanID: .mock(2_345),
            parentSpanID: .mock(5_678),
            baggageItems: .mockAny()
        )
        let oTelHTTPHeadersWriter = OTelHTTPHeadersWriter(
            sampler: sampler,
            injectEncoding: .single
        )
        oTelHTTPHeadersWriter.inject(spanContext: context)

        let headers = oTelHTTPHeadersWriter.tracePropagationHTTPHeaders
        XCTAssertEqual(headers[OTelHTTPHeaders.Single.b3Field], "0")
    }

    func testOTelHTTPHeadersWriterwritesSingleHeaderWithoutOptionalValues() {
        let sampler: Sampler = .mockKeepAll()
        let context: OTSpanContext = DDSpanContext.mockWith(
            traceID: .mock(1_234),
            spanID: .mock(2_345),
            parentSpanID: nil,
            baggageItems: .mockAny()
        )
        let oTelHTTPHeadersWriter = OTelHTTPHeadersWriter(
            sampler: sampler,
            injectEncoding: .single
        )
        oTelHTTPHeadersWriter.inject(spanContext: context)

        let headers = oTelHTTPHeadersWriter.tracePropagationHTTPHeaders
        XCTAssertEqual(headers[OTelHTTPHeaders.Single.b3Field], "000000000000000000000000000004d2-0000000000000929-1")
    }

    func testOTelHTTPHeadersWriterwritesMultipleHeader() {
        let sampler: Sampler = .mockKeepAll()
        let context: OTSpanContext = DDSpanContext.mockWith(
            traceID: .mock(1_234),
            spanID: .mock(2_345),
            parentSpanID: .mock(5_678),
            baggageItems: .mockAny()
        )
        let oTelHTTPHeadersWriter = OTelHTTPHeadersWriter(
            sampler: sampler,
            injectEncoding: .multiple
        )
        oTelHTTPHeadersWriter.inject(spanContext: context)

        let headers = oTelHTTPHeadersWriter.tracePropagationHTTPHeaders
        XCTAssertEqual(headers[OTelHTTPHeaders.Multiple.traceIDField], "000000000000000000000000000004d2")
        XCTAssertEqual(headers[OTelHTTPHeaders.Multiple.spanIDField], "0000000000000929")
        XCTAssertEqual(headers[OTelHTTPHeaders.Multiple.sampledField], "1")
        XCTAssertEqual(headers[OTelHTTPHeaders.Multiple.parentSpanIDField], "000000000000162e")
    }

    func testOTelHTTPHeadersWriterwritesMultipleHeaderWithSampling() {
        let sampler: Sampler = .mockRejectAll()
        let context: OTSpanContext = DDSpanContext.mockWith(
            traceID: .mock(1_234),
            spanID: .mock(2_345),
            parentSpanID: .mock(5_678),
            baggageItems: .mockAny()
        )
        let oTelHTTPHeadersWriter = OTelHTTPHeadersWriter(
            sampler: sampler,
            injectEncoding: .multiple
        )
        oTelHTTPHeadersWriter.inject(spanContext: context)

        let headers = oTelHTTPHeadersWriter.tracePropagationHTTPHeaders
        XCTAssertNil(headers[OTelHTTPHeaders.Multiple.traceIDField])
        XCTAssertNil(headers[OTelHTTPHeaders.Multiple.spanIDField])
        XCTAssertEqual(headers[OTelHTTPHeaders.Multiple.sampledField], "0")
        XCTAssertNil(headers[OTelHTTPHeaders.Multiple.parentSpanIDField])
    }

    func testOTelHTTPHeadersWriterwritesMultipleHeaderWithoutOptionalValues() {
        let sampler: Sampler = .mockKeepAll()
        let context: OTSpanContext = DDSpanContext.mockWith(
            traceID: .mock(1_234),
            spanID: .mock(2_345),
            parentSpanID: nil,
            baggageItems: .mockAny()
        )
        let oTelHTTPHeadersWriter = OTelHTTPHeadersWriter(
            sampler: sampler,
            injectEncoding: .multiple
        )
        oTelHTTPHeadersWriter.inject(spanContext: context)

        let headers = oTelHTTPHeadersWriter.tracePropagationHTTPHeaders
        XCTAssertEqual(headers[OTelHTTPHeaders.Multiple.traceIDField], "000000000000000000000000000004d2")
        XCTAssertEqual(headers[OTelHTTPHeaders.Multiple.spanIDField], "0000000000000929")
        XCTAssertEqual(headers[OTelHTTPHeaders.Multiple.sampledField], "1")
        XCTAssertNil(headers[OTelHTTPHeaders.Multiple.parentSpanIDField])
    }
}
