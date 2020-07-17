/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import XCTest
@testable import Datadog

class OTGlobalTests: XCTestCase {
    func testWhenUsingDefaultGlobalTracer_itDoesNothing() {
        let noOpTracer = Global.sharedTracer
        XCTAssertTrue(noOpTracer is DDNoopTracer)

        let noOpSpan = Global.sharedTracer.startSpan(operationName: .mockAny())
        XCTAssertTrue(noOpSpan is DDNoopSpan)
        XCTAssertTrue(noOpSpan.tracer() is DDNoopTracer)
        XCTAssertTrue(noOpSpan.context is DDNoopSpanContext)

        noOpSpan.setOperationName(.mockAny())
        noOpSpan.setTag(key: .mockAny(), value: String.mockAny())
        noOpSpan.setBaggageItem(key: .mockAny(), value: .mockAny())
        _ = noOpSpan.baggageItem(withKey: .mockAny())
        _ = noOpSpan.context.forEachBaggageItem { _, _ in return false }
        noOpSpan.log(fields: [.mockAny(): String.mockAny()])
        noOpSpan.finish()

        let headersWriter = HTTPHeadersWriter()
        noOpTracer.inject(spanContext: noOpSpan.context, writer: headersWriter)
        XCTAssertEqual(headersWriter.tracePropagationHTTPHeaders.count, 0)
    }
}
