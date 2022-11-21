/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import XCTest
@testable import Datadog

class OpenTelemetryHTTPHeadersWriterTests: XCTestCase {

    var openTelemetryHTTPHeadersWriter: OpenTelemetryHTTPHeadersWriter!
    var sampler: Sampler!
    var context: OTSpanContext!

    override func setUp() {
        super.setUp()
    }

    override func tearDown() {
        super.tearDown()
    }

    func test_OpenTelemetryHTTPHeadersWriter_writesSingleHeader() {
        sampler = .mockKeepAll()
        context = DDSpanContext.mockWith(
            traceID: .mock(1234),
            spanID: .mock(2345),
            parentSpanID: .mock(5678),
            baggageItems: .mockAny()
        )
        openTelemetryHTTPHeadersWriter = OpenTelemetryHTTPHeadersWriter(
            sampler: sampler,
            openTelemetryHeaderType: .single
        )
        openTelemetryHTTPHeadersWriter.inject(spanContext: context)

        let headers = openTelemetryHTTPHeadersWriter.tracePropagationHTTPHeaders
        XCTAssertEqual(headers[OpenTelemetryHTTPHeaders.Single.b3Field], "4D2-929-1-162E")
    }

    func test_OpenTelemetryHTTPHeadersWriter_writesSingleHeaderWithSampling() {
        sampler = .mockRejectAll()
        context = DDSpanContext.mockWith(
            traceID: .mock(1234),
            spanID: .mock(2345),
            parentSpanID: .mock(5678),
            baggageItems: .mockAny()
        )
        openTelemetryHTTPHeadersWriter = OpenTelemetryHTTPHeadersWriter(
            sampler: sampler,
            openTelemetryHeaderType: .single
        )
        openTelemetryHTTPHeadersWriter.inject(spanContext: context)

        let headers = openTelemetryHTTPHeadersWriter.tracePropagationHTTPHeaders
        XCTAssertEqual(headers[OpenTelemetryHTTPHeaders.Single.b3Field], "0")
    }

    func test_OpenTelemetryHTTPHeadersWriter_writesSingleHeaderWithoutOptionalValues() {
        sampler = .mockKeepAll()
        context = DDSpanContext.mockWith(
            traceID: .mock(1234),
            spanID: .mock(2345),
            parentSpanID: nil,
            baggageItems: .mockAny()
        )
        openTelemetryHTTPHeadersWriter = OpenTelemetryHTTPHeadersWriter(
            sampler: sampler,
            openTelemetryHeaderType: .single
        )
        openTelemetryHTTPHeadersWriter.inject(spanContext: context)

        let headers = openTelemetryHTTPHeadersWriter.tracePropagationHTTPHeaders
        XCTAssertEqual(headers[OpenTelemetryHTTPHeaders.Single.b3Field], "4D2-929-1")
    }

    func test_OpenTelemetryHTTPHeadersWriter_writesMultipleHeader() {
        sampler = .mockKeepAll()
        context = DDSpanContext.mockWith(
            traceID: .mock(1234),
            spanID: .mock(2345),
            parentSpanID: .mock(5678),
            baggageItems: .mockAny()
        )
        openTelemetryHTTPHeadersWriter = OpenTelemetryHTTPHeadersWriter(
            sampler: sampler,
            openTelemetryHeaderType: .multiple
        )
        openTelemetryHTTPHeadersWriter.inject(spanContext: context)

        let headers = openTelemetryHTTPHeadersWriter.tracePropagationHTTPHeaders
        XCTAssertEqual(headers[OpenTelemetryHTTPHeaders.Multiple.traceIDField], "4D2")
        XCTAssertEqual(headers[OpenTelemetryHTTPHeaders.Multiple.spanIDField], "929")
        XCTAssertEqual(headers[OpenTelemetryHTTPHeaders.Multiple.sampledField], "1")
        XCTAssertEqual(headers[OpenTelemetryHTTPHeaders.Multiple.parentSpanIDField], "162E")
    }

    func test_OpenTelemetryHTTPHeadersWriter_writesMultipleHeaderWithSampling() {
        sampler = .mockRejectAll()
        context = DDSpanContext.mockWith(
            traceID: .mock(1234),
            spanID: .mock(2345),
            parentSpanID: .mock(5678),
            baggageItems: .mockAny()
        )
        openTelemetryHTTPHeadersWriter = OpenTelemetryHTTPHeadersWriter(
            sampler: sampler,
            openTelemetryHeaderType: .multiple
        )
        openTelemetryHTTPHeadersWriter.inject(spanContext: context)

        let headers = openTelemetryHTTPHeadersWriter.tracePropagationHTTPHeaders
        XCTAssertNil(headers[OpenTelemetryHTTPHeaders.Multiple.traceIDField])
        XCTAssertNil(headers[OpenTelemetryHTTPHeaders.Multiple.spanIDField])
        XCTAssertEqual(headers[OpenTelemetryHTTPHeaders.Multiple.sampledField], "0")
        XCTAssertNil(headers[OpenTelemetryHTTPHeaders.Multiple.parentSpanIDField])
    }

    func test_OpenTelemetryHTTPHeadersWriter_writesMultipleHeaderWithoutOptionalValues() {
        sampler = .mockKeepAll()
        context = DDSpanContext.mockWith(
            traceID: .mock(1234),
            spanID: .mock(2345),
            parentSpanID: nil,
            baggageItems: .mockAny()
        )
        openTelemetryHTTPHeadersWriter = OpenTelemetryHTTPHeadersWriter(
            sampler: sampler,
            openTelemetryHeaderType: .multiple
        )
        openTelemetryHTTPHeadersWriter.inject(spanContext: context)

        let headers = openTelemetryHTTPHeadersWriter.tracePropagationHTTPHeaders
        XCTAssertEqual(headers[OpenTelemetryHTTPHeaders.Multiple.traceIDField], "4D2")
        XCTAssertEqual(headers[OpenTelemetryHTTPHeaders.Multiple.spanIDField], "929")
        XCTAssertEqual(headers[OpenTelemetryHTTPHeaders.Multiple.sampledField], "1")
        XCTAssertNil(headers[OpenTelemetryHTTPHeaders.Multiple.parentSpanIDField])
    }
}
