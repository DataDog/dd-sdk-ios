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
        let writer = HTTPHeadersWriter(samplingStrategy: .custom(sampleRate: 100), traceContextInjection: .all)
        writer.write(traceContext: .mockRandom())

        let reader = HTTPHeadersReader(httpHeaderFields: writer.traceHeaderFields)
        XCTAssertNotNil(reader.read(), "When sampled, it should return trace context")
        XCTAssertEqual(reader.sampled, true)
    }

    func testReadingNotSampledTraceContext_givenTraceContextInjectionIsAll() {
        let writer = HTTPHeadersWriter(samplingStrategy: .custom(sampleRate: 0), traceContextInjection: .all)
        writer.write(traceContext: .mockRandom())

        let reader = HTTPHeadersReader(httpHeaderFields: writer.traceHeaderFields)
        XCTAssertNotNil(reader.read(), "When not sampled, it should return no trace context")
        XCTAssertEqual(reader.sampled, false)
    }

    func testReadingNotSampledTraceContext_givenTraceContextInjectionIsSampled() {
        let writer = HTTPHeadersWriter(samplingStrategy: .custom(sampleRate: 0), traceContextInjection: .sampled)
        writer.write(traceContext: .mockRandom())

        let reader = HTTPHeadersReader(httpHeaderFields: writer.traceHeaderFields)
        XCTAssertNil(reader.read(), "When not sampled, it should return no trace context")
        XCTAssertNil(reader.sampled)
    }
}
