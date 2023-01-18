/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
@testable import Datadog

class W3CHTTPHeadersWriterTests: XCTestCase {
    func testW3CHTTPHeadersWriterwritesSingleHeader() {
        let sampler: Sampler = .mockKeepAll()
        let context: OTSpanContext = DDSpanContext.mockWith(
            traceID: .mock(1_234),
            spanID: .mock(2_345),
            parentSpanID: nil,
            baggageItems: .mockAny()
        )
        let w3cHTTPHeadersWriter = W3CHTTPHeadersWriter(
            sampler: sampler
        )
        w3cHTTPHeadersWriter.inject(spanContext: context)

        let headers = w3cHTTPHeadersWriter.tracePropagationHTTPHeaders
        XCTAssertEqual(headers[W3CHTTPHeaders.traceparent], "00-000000000000000000000000000004d2-0000000000000929-01")
    }

    func testW3CHTTPHeadersWriterwritesSingleHeaderWithSampling() {
        let sampler: Sampler = .mockRejectAll()
        let context: OTSpanContext = DDSpanContext.mockWith(
            traceID: .mock(1_234),
            spanID: .mock(2_345),
            parentSpanID: .mock(5_678),
            baggageItems: .mockAny()
        )
        let w3cHTTPHeadersWriter = W3CHTTPHeadersWriter(
            sampler: sampler
        )
        w3cHTTPHeadersWriter.inject(spanContext: context)

        let headers = w3cHTTPHeadersWriter.tracePropagationHTTPHeaders
        XCTAssertEqual(headers[W3CHTTPHeaders.traceparent], "00-000000000000000000000000000004d2-0000000000000929-00")
    }
}
