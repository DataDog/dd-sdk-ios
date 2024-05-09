/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import TestUtilities
@testable import DatadogInternal

class HTTPHeadersReaderTests: XCTestCase {
    func testReadingSampledTraceContext() {
        let writer = HTTPHeadersWriter(samplingStrategy: .custom(sampleRate: 100))
        writer.write(traceContext: .mockRandom())

        let reader = HTTPHeadersReader(httpHeaderFields: writer.traceHeaderFields)
        XCTAssertNotNil(reader.read(), "When sampled, it should return trace context")
        XCTAssertEqual(reader.sampled, true)
    }

    func testReadingNotSampledTraceContext() {
        let writer = HTTPHeadersWriter(samplingStrategy: .custom(sampleRate: 0))
        writer.write(traceContext: .mockRandom())

        let reader = HTTPHeadersReader(httpHeaderFields: writer.traceHeaderFields)
        XCTAssertNil(reader.read(), "When not sampled, it should return no trace context")
        XCTAssertEqual(reader.sampled, false)
    }
}
