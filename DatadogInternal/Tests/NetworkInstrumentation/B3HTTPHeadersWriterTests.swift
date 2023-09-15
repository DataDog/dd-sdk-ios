/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
@testable import DatadogInternal

class B3HTTPHeadersWriterTests: XCTestCase {
    func testItWritesSingleHeader() {
        let sampler: Sampler = .mockKeepAll()
        let writer = B3HTTPHeadersWriter(
            sampler: sampler,
            injectEncoding: .single
        )

        writer.write(
            traceID: 1_234,
            spanID: 2_345,
            parentSpanID: 5_678
        )

        let headers = writer.traceHeaderFields
        XCTAssertEqual(headers[B3HTTPHeaders.Single.b3Field], "000000000000000000000000000004d2-0000000000000929-1-000000000000162e")
    }

    func testItWritesSingleHeaderWithSampling() {
        let sampler: Sampler = .mockRejectAll()
        let writer = B3HTTPHeadersWriter(
            sampler: sampler,
            injectEncoding: .single
        )

        writer.write(
            traceID: 1_234,
            spanID: 2_345,
            parentSpanID: 5_678
        )

        let headers = writer.traceHeaderFields
        XCTAssertEqual(headers[B3HTTPHeaders.Single.b3Field], "0")
    }

    func testItWritesSingleHeaderWithoutOptionalValues() {
        let sampler: Sampler = .mockKeepAll()
        let writer = B3HTTPHeadersWriter(
            sampler: sampler,
            injectEncoding: .single
        )
        writer.write(traceID: 1_234, spanID: 2_345)

        let headers = writer.traceHeaderFields
        XCTAssertEqual(headers[B3HTTPHeaders.Single.b3Field], "000000000000000000000000000004d2-0000000000000929-1")
    }

    func testItWritesMultipleHeader() {
        let sampler: Sampler = .mockKeepAll()
        let writer = B3HTTPHeadersWriter(
            sampler: sampler,
            injectEncoding: .multiple
        )
        writer.write(
            traceID: 1_234,
            spanID: 2_345,
            parentSpanID: 5_678
        )

        let headers = writer.traceHeaderFields
        XCTAssertEqual(headers[B3HTTPHeaders.Multiple.traceIDField], "000000000000000000000000000004d2")
        XCTAssertEqual(headers[B3HTTPHeaders.Multiple.spanIDField], "0000000000000929")
        XCTAssertEqual(headers[B3HTTPHeaders.Multiple.sampledField], "1")
        XCTAssertEqual(headers[B3HTTPHeaders.Multiple.parentSpanIDField], "000000000000162e")
    }

    func testItWritesMultipleHeaderWithSampling() {
        let sampler: Sampler = .mockRejectAll()
        let writer = B3HTTPHeadersWriter(
            sampler: sampler,
            injectEncoding: .multiple
        )
        writer.write(
            traceID: 1_234,
            spanID: 2_345,
            parentSpanID: 5_678
        )

        let headers = writer.traceHeaderFields
        XCTAssertNil(headers[B3HTTPHeaders.Multiple.traceIDField])
        XCTAssertNil(headers[B3HTTPHeaders.Multiple.spanIDField])
        XCTAssertEqual(headers[B3HTTPHeaders.Multiple.sampledField], "0")
        XCTAssertNil(headers[B3HTTPHeaders.Multiple.parentSpanIDField])
    }

    func testItWritesMultipleHeaderWithoutOptionalValues() {
        let sampler: Sampler = .mockKeepAll()
        let writer = B3HTTPHeadersWriter(
            sampler: sampler,
            injectEncoding: .multiple
        )
        writer.write(traceID: 1_234, spanID: 2_345)

        let headers = writer.traceHeaderFields
        XCTAssertEqual(headers[B3HTTPHeaders.Multiple.traceIDField], "000000000000000000000000000004d2")
        XCTAssertEqual(headers[B3HTTPHeaders.Multiple.spanIDField], "0000000000000929")
        XCTAssertEqual(headers[B3HTTPHeaders.Multiple.sampledField], "1")
        XCTAssertNil(headers[B3HTTPHeaders.Multiple.parentSpanIDField])
    }
}
