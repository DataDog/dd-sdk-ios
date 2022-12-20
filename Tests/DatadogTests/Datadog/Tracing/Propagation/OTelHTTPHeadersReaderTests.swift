/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
@testable import Datadog

class OTelHTTPHeadersReaderTests: XCTestCase {
    func testOTelHTTPHeadersReaderreadsSingleHeader() {
        let oTelHTTPHeadersReader = OTelHTTPHeadersReader(httpHeaderFields: ["b3": "4d2-929-1-162e"])
        oTelHTTPHeadersReader.use(baggageItemQueue: .main)

        let spanContext = oTelHTTPHeadersReader.extract()?.dd

        XCTAssertEqual(spanContext?.traceID, TracingUUID(rawValue: 1_234))
        XCTAssertEqual(spanContext?.spanID, TracingUUID(rawValue: 2_345))
        XCTAssertEqual(spanContext?.parentSpanID, TracingUUID(rawValue: 5_678))
    }

    func testOTelHTTPHeadersReaderreadsSingleHeaderWithSampling() {
        let oTelHTTPHeadersReader = OTelHTTPHeadersReader(httpHeaderFields: ["b3": "0"])
        oTelHTTPHeadersReader.use(baggageItemQueue: .main)

        let spanContext = oTelHTTPHeadersReader.extract()?.dd

        XCTAssertNil(spanContext?.traceID)
        XCTAssertNil(spanContext?.spanID)
        XCTAssertNil(spanContext?.parentSpanID)
    }

    func testOTelHTTPHeadersReaderreadsSingleHeaderWithoutOptionalValues() {
        let oTelHTTPHeadersReader = OTelHTTPHeadersReader(httpHeaderFields: ["b3": "4d2-929"])
        oTelHTTPHeadersReader.use(baggageItemQueue: .main)

        let spanContext = oTelHTTPHeadersReader.extract()?.dd

        XCTAssertEqual(spanContext?.traceID, TracingUUID(rawValue: 1_234))
        XCTAssertEqual(spanContext?.spanID, TracingUUID(rawValue: 2_345))
        XCTAssertNil(spanContext?.parentSpanID)
    }

    func testOTelHTTPHeadersReaderreadsMultipleHeader() {
        let oTelHTTPHeadersReader = OTelHTTPHeadersReader(httpHeaderFields: [
            "X-B3-TraceId": "4d2",
            "X-B3-SpanId": "929",
            "X-B3-Sampled": "1",
            "X-B3-ParentSpanId": "162e"
        ])
        oTelHTTPHeadersReader.use(baggageItemQueue: .main)

        let spanContext = oTelHTTPHeadersReader.extract()?.dd

        XCTAssertEqual(spanContext?.traceID, TracingUUID(rawValue: 1_234))
        XCTAssertEqual(spanContext?.spanID, TracingUUID(rawValue: 2_345))
        XCTAssertEqual(spanContext?.parentSpanID, TracingUUID(rawValue: 5_678))
    }

    func testOTelHTTPHeadersReaderreadsMultipleHeaderWithSampling() {
        let oTelHTTPHeadersReader = OTelHTTPHeadersReader(httpHeaderFields: [
            "X-B3-Sampled": "0"
        ])
        oTelHTTPHeadersReader.use(baggageItemQueue: .main)

        let spanContext = oTelHTTPHeadersReader.extract()?.dd

        XCTAssertNil(spanContext?.traceID)
        XCTAssertNil(spanContext?.spanID)
        XCTAssertNil(spanContext?.parentSpanID)
    }

    func testOTelHTTPHeadersReaderreadsMultipleHeaderWithoutOptionalValues() {
        let oTelHTTPHeadersReader = OTelHTTPHeadersReader(httpHeaderFields: [
            "X-B3-TraceId": "4d2",
            "X-B3-SpanId": "929"
        ])
        oTelHTTPHeadersReader.use(baggageItemQueue: .main)

        let spanContext = oTelHTTPHeadersReader.extract()?.dd

        XCTAssertEqual(spanContext?.traceID, TracingUUID(rawValue: 1_234))
        XCTAssertEqual(spanContext?.spanID, TracingUUID(rawValue: 2_345))
        XCTAssertNil(spanContext?.parentSpanID)
    }
}
