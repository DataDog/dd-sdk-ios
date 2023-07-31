/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
@testable import DatadogInternal

class OTelHTTPHeadersWriterTests: XCTestCase {
    func testOTelHTTPHeadersWriterwritesSingleHeader() {
        let sampler: Sampler = .mockKeepAll()
        let oTelHTTPHeadersWriter = OTelHTTPHeadersWriter(
            sampler: sampler,
            injectEncoding: .single
        )

        oTelHTTPHeadersWriter.write(
            traceID: 1_234,
            spanID: 2_345,
            parentSpanID: 5_678
        )

        let headers = oTelHTTPHeadersWriter.traceHeaderFields
        XCTAssertEqual(headers[OTelHTTPHeaders.Single.b3Field], "000000000000000000000000000004d2-0000000000000929-1-000000000000162e")
    }

    func testOTelHTTPHeadersWriterwritesSingleHeaderWithSampling() {
        let sampler: Sampler = .mockRejectAll()
        let oTelHTTPHeadersWriter = OTelHTTPHeadersWriter(
            sampler: sampler,
            injectEncoding: .single
        )

        oTelHTTPHeadersWriter.write(
            traceID: 1_234,
            spanID: 2_345,
            parentSpanID: 5_678
        )

        let headers = oTelHTTPHeadersWriter.traceHeaderFields
        XCTAssertEqual(headers[OTelHTTPHeaders.Single.b3Field], "0")
    }

    func testOTelHTTPHeadersWriterwritesSingleHeaderWithoutOptionalValues() {
        let sampler: Sampler = .mockKeepAll()
        let oTelHTTPHeadersWriter = OTelHTTPHeadersWriter(
            sampler: sampler,
            injectEncoding: .single
        )
        oTelHTTPHeadersWriter.write(traceID: 1_234, spanID: 2_345)

        let headers = oTelHTTPHeadersWriter.traceHeaderFields
        XCTAssertEqual(headers[OTelHTTPHeaders.Single.b3Field], "000000000000000000000000000004d2-0000000000000929-1")
    }

    func testOTelHTTPHeadersWriterwritesMultipleHeader() {
        let sampler: Sampler = .mockKeepAll()
        let oTelHTTPHeadersWriter = OTelHTTPHeadersWriter(
            sampler: sampler,
            injectEncoding: .multiple
        )
        oTelHTTPHeadersWriter.write(
            traceID: 1_234,
            spanID: 2_345,
            parentSpanID: 5_678
        )

        let headers = oTelHTTPHeadersWriter.traceHeaderFields
        XCTAssertEqual(headers[OTelHTTPHeaders.Multiple.traceIDField], "000000000000000000000000000004d2")
        XCTAssertEqual(headers[OTelHTTPHeaders.Multiple.spanIDField], "0000000000000929")
        XCTAssertEqual(headers[OTelHTTPHeaders.Multiple.sampledField], "1")
        XCTAssertEqual(headers[OTelHTTPHeaders.Multiple.parentSpanIDField], "000000000000162e")
    }

    func testOTelHTTPHeadersWriterwritesMultipleHeaderWithSampling() {
        let sampler: Sampler = .mockRejectAll()
        let oTelHTTPHeadersWriter = OTelHTTPHeadersWriter(
            sampler: sampler,
            injectEncoding: .multiple
        )
        oTelHTTPHeadersWriter.write(
            traceID: 1_234,
            spanID: 2_345,
            parentSpanID: 5_678
        )

        let headers = oTelHTTPHeadersWriter.traceHeaderFields
        XCTAssertNil(headers[OTelHTTPHeaders.Multiple.traceIDField])
        XCTAssertNil(headers[OTelHTTPHeaders.Multiple.spanIDField])
        XCTAssertEqual(headers[OTelHTTPHeaders.Multiple.sampledField], "0")
        XCTAssertNil(headers[OTelHTTPHeaders.Multiple.parentSpanIDField])
    }

    func testOTelHTTPHeadersWriterwritesMultipleHeaderWithoutOptionalValues() {
        let sampler: Sampler = .mockKeepAll()
        let oTelHTTPHeadersWriter = OTelHTTPHeadersWriter(
            sampler: sampler,
            injectEncoding: .multiple
        )
        oTelHTTPHeadersWriter.write(traceID: 1_234, spanID: 2_345)

        let headers = oTelHTTPHeadersWriter.traceHeaderFields
        XCTAssertEqual(headers[OTelHTTPHeaders.Multiple.traceIDField], "000000000000000000000000000004d2")
        XCTAssertEqual(headers[OTelHTTPHeaders.Multiple.spanIDField], "0000000000000929")
        XCTAssertEqual(headers[OTelHTTPHeaders.Multiple.sampledField], "1")
        XCTAssertNil(headers[OTelHTTPHeaders.Multiple.parentSpanIDField])
    }
}
