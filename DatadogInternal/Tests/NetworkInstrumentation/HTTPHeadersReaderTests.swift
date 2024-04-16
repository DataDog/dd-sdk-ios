/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
@testable import DatadogInternal

class HTTPHeadersReaderTests: XCTestCase {
    func testReadingSampledTraceContext() {
        let writer = HTTPHeadersWriter(sampleRate: 100)
        writer.write(traceID: .mockAny(), spanID: .mockAny(), parentSpanID: .mockAny())

        let reader = HTTPHeadersReader(httpHeaderFields: writer.traceHeaderFields)
        XCTAssertNotNil(reader.read(), "When sampled, it should return trace context")
    }

    func testReadingNotSampledTraceContext() {
        let writer = HTTPHeadersWriter(sampleRate: 0)
        writer.write(traceID: .mockAny(), spanID: .mockAny(), parentSpanID: .mockAny())

        let reader = HTTPHeadersReader(httpHeaderFields: writer.traceHeaderFields)
        XCTAssertNil(reader.read(), "When not sampled, it should return no trace context")
    }
}
