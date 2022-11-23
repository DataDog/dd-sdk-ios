/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import XCTest
@testable import Datadog

class OpenTelemetryHTTPHeadersReaderTests: XCTestCase {
    // swiftlint:disable implicitly_unwrapped_optional
    var openTelemetryHTTPHeadersReader: OpenTelemetryHTTPHeadersReader!
    var sampler: Sampler!
    var context: OTSpanContext!
    // swiftlint:enable implicitly_unwrapped_optional

    override func setUp() {
        super.setUp()
    }

    override func tearDown() {
        super.tearDown()
    }

    func testOpenTelemetryHTTPHeadersReaderreadsSingleHeader() {
        openTelemetryHTTPHeadersReader = OpenTelemetryHTTPHeadersReader(httpHeaderFields: ["b3": "4D2-929-1-162E"])
        openTelemetryHTTPHeadersReader.use(baggageItemQueue: .main)

        let spanContext = openTelemetryHTTPHeadersReader.extract()?.dd

        XCTAssertEqual(spanContext?.traceID, TracingUUID(rawValue: 1_234))
        XCTAssertEqual(spanContext?.spanID, TracingUUID(rawValue: 2_345))
        XCTAssertEqual(spanContext?.parentSpanID, TracingUUID(rawValue: 5_678))
    }

    func testOpenTelemetryHTTPHeadersReaderreadsSingleHeaderWithSampling() {
        openTelemetryHTTPHeadersReader = OpenTelemetryHTTPHeadersReader(httpHeaderFields: ["b3": "0"])
        openTelemetryHTTPHeadersReader.use(baggageItemQueue: .main)

        let spanContext = openTelemetryHTTPHeadersReader.extract()?.dd

        XCTAssertNil(spanContext?.traceID)
        XCTAssertNil(spanContext?.spanID)
        XCTAssertNil(spanContext?.parentSpanID)
    }

    func testOpenTelemetryHTTPHeadersReaderreadsSingleHeaderWithoutOptionalValues() {
        openTelemetryHTTPHeadersReader = OpenTelemetryHTTPHeadersReader(httpHeaderFields: ["b3": "4D2-929"])
        openTelemetryHTTPHeadersReader.use(baggageItemQueue: .main)

        let spanContext = openTelemetryHTTPHeadersReader.extract()?.dd

        XCTAssertEqual(spanContext?.traceID, TracingUUID(rawValue: 1_234))
        XCTAssertEqual(spanContext?.spanID, TracingUUID(rawValue: 2_345))
        XCTAssertNil(spanContext?.parentSpanID)
    }

    func testOpenTelemetryHTTPHeadersReaderreadsMultipleHeader() {
        openTelemetryHTTPHeadersReader = OpenTelemetryHTTPHeadersReader(httpHeaderFields: [
            "X-B3-TraceId": "4D2",
            "X-B3-SpanId": "929",
            "X-B3-Sampled": "1",
            "X-B3-ParentSpanId": "162E"
        ])
        openTelemetryHTTPHeadersReader.use(baggageItemQueue: .main)

        let spanContext = openTelemetryHTTPHeadersReader.extract()?.dd

        XCTAssertEqual(spanContext?.traceID, TracingUUID(rawValue: 1_234))
        XCTAssertEqual(spanContext?.spanID, TracingUUID(rawValue: 2_345))
        XCTAssertEqual(spanContext?.parentSpanID, TracingUUID(rawValue: 5_678))
    }

    func testOpenTelemetryHTTPHeadersReaderreadsMultipleHeaderWithSampling() {
        openTelemetryHTTPHeadersReader = OpenTelemetryHTTPHeadersReader(httpHeaderFields: [
            "X-B3-Sampled": "0"
        ])
        openTelemetryHTTPHeadersReader.use(baggageItemQueue: .main)

        let spanContext = openTelemetryHTTPHeadersReader.extract()?.dd

        XCTAssertNil(spanContext?.traceID)
        XCTAssertNil(spanContext?.spanID)
        XCTAssertNil(spanContext?.parentSpanID)
    }

    func testOpenTelemetryHTTPHeadersReaderreadsMultipleHeaderWithoutOptionalValues() {
        openTelemetryHTTPHeadersReader = OpenTelemetryHTTPHeadersReader(httpHeaderFields: [
            "X-B3-TraceId": "4D2",
            "X-B3-SpanId": "929"
        ])
        openTelemetryHTTPHeadersReader.use(baggageItemQueue: .main)

        let spanContext = openTelemetryHTTPHeadersReader.extract()?.dd

        XCTAssertEqual(spanContext?.traceID, TracingUUID(rawValue: 1_234))
        XCTAssertEqual(spanContext?.spanID, TracingUUID(rawValue: 2_345))
        XCTAssertNil(spanContext?.parentSpanID)
    }
}
