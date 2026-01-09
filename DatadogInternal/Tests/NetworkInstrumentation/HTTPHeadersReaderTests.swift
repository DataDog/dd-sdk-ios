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
        let writer = HTTPHeadersWriter(traceContextInjection: .all)
        writer.write(traceContext: .mockWith(
            samplingPriority: .autoKeep,
            samplingDecisionMaker: .agentRate
        ))

        let reader = HTTPHeadersReader(httpHeaderFields: writer.traceHeaderFields)
        XCTAssertNotNil(reader.read(), "When sampled, it should return trace context")
        XCTAssertEqual(reader.samplingPriority, .autoKeep)
        XCTAssertEqual(reader.samplingDecisionMaker, .agentRate)
    }

    func testReadingManuallyKeptTraceContext() {
        let writer = HTTPHeadersWriter(traceContextInjection: .all)
        writer.write(traceContext: .mockWith(
            samplingPriority: .manualKeep,
            samplingDecisionMaker: .manual
        ))

        let reader = HTTPHeadersReader(httpHeaderFields: writer.traceHeaderFields)
        XCTAssertNotNil(reader.read(), "When sampled, it should return trace context")
        XCTAssertEqual(reader.samplingPriority, .manualKeep)
        XCTAssertEqual(reader.samplingDecisionMaker, .manual)
    }

    func testReadingNotSampledTraceContext_givenTraceContextInjectionIsAll() {
        let writer = HTTPHeadersWriter(traceContextInjection: .all)
        writer.write(traceContext: .mockWith(
            samplingPriority: .autoDrop,
            samplingDecisionMaker: .agentRate
        ))

        let reader = HTTPHeadersReader(httpHeaderFields: writer.traceHeaderFields)
        XCTAssertNotNil(reader.read(), "When not sampled, it should return no trace context")
        XCTAssertEqual(reader.samplingPriority, .autoDrop)
        XCTAssertNil(reader.samplingDecisionMaker)
    }

    func testReadingNotSampledTraceContext_givenTraceContextInjectionIsSampled() {
        let writer = HTTPHeadersWriter(traceContextInjection: .sampled)
        writer.write(traceContext: .mockWith(
            samplingPriority: .autoDrop,
            samplingDecisionMaker: .agentRate
        ))

        let reader = HTTPHeadersReader(httpHeaderFields: writer.traceHeaderFields)
        XCTAssertNil(reader.read(), "When not sampled, it should return no trace context")
        XCTAssertNil(reader.samplingPriority)
        XCTAssertNil(reader.samplingDecisionMaker)
    }

    func testReadingManuallyDroppedTraceContext_givenTraceContextInjectionIsAll() {
        let writer = HTTPHeadersWriter(traceContextInjection: .all)
        writer.write(traceContext: .mockWith(
            samplingPriority: .manualDrop,
            samplingDecisionMaker: .manual
        ))

        let reader = HTTPHeadersReader(httpHeaderFields: writer.traceHeaderFields)
        XCTAssertNotNil(reader.read(), "When not sampled, it should return no trace context")
        XCTAssertEqual(reader.samplingPriority, .manualDrop)
        XCTAssertNil(reader.samplingDecisionMaker)
    }

    func testReadingManuallyDroppedTraceContext_givenTraceContextInjectionIsSampled() {
        let writer = HTTPHeadersWriter(traceContextInjection: .sampled)
        writer.write(traceContext: .mockWith(
            samplingPriority: .manualDrop,
            samplingDecisionMaker: .manual
        ))

        let reader = HTTPHeadersReader(httpHeaderFields: writer.traceHeaderFields)
        XCTAssertNil(reader.read(), "When not sampled, it should return no trace context")
        XCTAssertNil(reader.samplingPriority)
        XCTAssertNil(reader.samplingDecisionMaker)
    }
}
