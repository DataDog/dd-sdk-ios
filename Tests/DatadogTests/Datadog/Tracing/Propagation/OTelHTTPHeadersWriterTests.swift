/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
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
        XCTAssertEqual(headers[OTelHTTPHeaders.Single.b3Field], "4D2-929-1-162E")
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
        XCTAssertEqual(headers[OTelHTTPHeaders.Single.b3Field], "4D2-929-1")
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
        XCTAssertEqual(headers[OTelHTTPHeaders.Multiple.traceIDField], "4D2")
        XCTAssertEqual(headers[OTelHTTPHeaders.Multiple.spanIDField], "929")
        XCTAssertEqual(headers[OTelHTTPHeaders.Multiple.sampledField], "1")
        XCTAssertEqual(headers[OTelHTTPHeaders.Multiple.parentSpanIDField], "162E")
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
        XCTAssertEqual(headers[OTelHTTPHeaders.Multiple.traceIDField], "4D2")
        XCTAssertEqual(headers[OTelHTTPHeaders.Multiple.spanIDField], "929")
        XCTAssertEqual(headers[OTelHTTPHeaders.Multiple.sampledField], "1")
        XCTAssertNil(headers[OTelHTTPHeaders.Multiple.parentSpanIDField])
    }
}
