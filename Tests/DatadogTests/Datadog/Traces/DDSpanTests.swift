/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import XCTest
@testable import Datadog

class DDSpanTests: XCTestCase {
    func testSettingOperationName() {
        let span = DDSpan(tracer: .mockNoOp(), operationName: "initial", parentSpanContext: nil, startTime: .mockAny())
        span.setOperationName("new")
        XCTAssertEqual(span.operationName, "new")
    }
}
