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

final class OTelTraceStateDatadogTests: XCTestCase {
    func testW3C_givenEmptyEntries() throws {
        let traceState = TraceState(entries: [])!
        XCTAssertEqual("", traceState.w3c())
    }

    func testW3C_givenSomeEntries() throws {
        let traceState = TraceState(
            entries: [
                .init(key: "foo", value: "bar")!,
                .init(key: "bar", value: "baz")!
            ]
        )!

        XCTAssertEqual("foo=bar,bar=baz", traceState.w3c())
    }
}
