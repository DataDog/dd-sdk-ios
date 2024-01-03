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

class OTelTraceIdDatadogTests: XCTestCase {
    func testToDatadog_onlyHigherOrderBitsAreConsidered() {
        let otelId = TraceId.random()
        let ddId = otelId.toDatadog()
        XCTAssertEqual(otelId.rawHigherLong, ddId.rawValue)
    }
}
