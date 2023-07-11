/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
@testable import DatadogInternal

class W3CHTTPHeadersWriterTests: XCTestCase {
    func testW3CHTTPHeadersWriterwritesSingleHeader() {
        let sampler: Sampler = .mockKeepAll()
        let w3cHTTPHeadersWriter = W3CHTTPHeadersWriter(
            sampler: sampler
        )
        w3cHTTPHeadersWriter.write(traceID: 1_234, spanID: 2_345)

        let headers = w3cHTTPHeadersWriter.traceHeaderFields
        XCTAssertEqual(headers[W3CHTTPHeaders.traceparent], "00-000000000000000000000000000004d2-0000000000000929-01")
    }

    func testW3CHTTPHeadersWriterwritesSingleHeaderWithSampling() {
        let sampler: Sampler = .mockRejectAll()
        let w3cHTTPHeadersWriter = W3CHTTPHeadersWriter(
            sampler: sampler
        )
        w3cHTTPHeadersWriter.write(traceID: 1_234, spanID: 2_345, parentSpanID: 5_678)

        let headers = w3cHTTPHeadersWriter.traceHeaderFields
        XCTAssertEqual(headers[W3CHTTPHeaders.traceparent], "00-000000000000000000000000000004d2-0000000000000929-00")
    }
}
