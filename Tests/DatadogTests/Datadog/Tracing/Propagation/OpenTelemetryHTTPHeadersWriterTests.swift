/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import XCTest
@testable import Datadog

class OpenTelemetryHTTPHeadersWriterTests: XCTestCase {
    // swiftlint:disable implicitly_unwrapped_optional
    var openTelemetryHTTPHeadersWriter: OpenTelemetryHTTPHeadersWriter!
    var sampler: Sampler!
    var context: OTSpanContext!
    // swiftlint:enable implicitly_unwrapped_optional

    override func setUp() {
        super.setUp()
    }

    override func tearDown() {
        super.tearDown()
    }

    func testOpenTelemetryHTTPHeadersWriterwritesSingleHeader() {
        sampler = .mockKeepAll()
        context = DDSpanContext.mockWith(
            traceID: .mock(1_234),
            spanID: .mock(2_345),
            parentSpanID: .mock(5_678),
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

    func testOpenTelemetryHTTPHeadersWriterwritesSingleHeaderWithSampling() {
        sampler = .mockRejectAll()
        context = DDSpanContext.mockWith(
            traceID: .mock(1_234),
            spanID: .mock(2_345),
            parentSpanID: .mock(5_678),
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

    func testOpenTelemetryHTTPHeadersWriterwritesSingleHeaderWithoutOptionalValues() {
        sampler = .mockKeepAll()
        context = DDSpanContext.mockWith(
            traceID: .mock(1_234),
            spanID: .mock(2_345),
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

    func testOpenTelemetryHTTPHeadersWriterwritesMultipleHeader() {
        sampler = .mockKeepAll()
        context = DDSpanContext.mockWith(
            traceID: .mock(1_234),
            spanID: .mock(2_345),
            parentSpanID: .mock(5_678),
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

    func testOpenTelemetryHTTPHeadersWriterwritesMultipleHeaderWithSampling() {
        sampler = .mockRejectAll()
        context = DDSpanContext.mockWith(
            traceID: .mock(1_234),
            spanID: .mock(2_345),
            parentSpanID: .mock(5_678),
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

    func testOpenTelemetryHTTPHeadersWriterwritesMultipleHeaderWithoutOptionalValues() {
        sampler = .mockKeepAll()
        context = DDSpanContext.mockWith(
            traceID: .mock(1_234),
            spanID: .mock(2_345),
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
