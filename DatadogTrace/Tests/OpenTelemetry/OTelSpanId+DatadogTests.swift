/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import TestUtilities
import DatadogInternal
import OpenTelemetryApi

@testable import DatadogTrace

class OTelSpanIdDatadogTests: XCTestCase {
    func testToDatadog() {
        let otelId = SpanId(id: 1)
        let ddId = otelId.toDatadog()
        XCTAssertEqual(1, ddId.rawValue)
    }
}
