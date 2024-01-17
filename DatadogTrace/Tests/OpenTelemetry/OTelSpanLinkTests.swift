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

final class OTelSpanLinkTests: XCTestCase {
    func testEncoder_givenAllPropertiesArePresent() throws {
        let encoder = JSONEncoder()
        let traceId = TraceId(idHi: 101, idLo: 102)
        let spanId = SpanId(id: 103)
        var traceFlags = TraceFlags()
        traceFlags.setIsSampled(true)
        let traceState = TraceState(
            entries: [
                .init(key: "foo", value: "bar")!,
                .init(key: "bar", value: "baz")!
            ]
        )!

        let spanContext = OpenTelemetryApi.SpanContext.create(
            traceId: traceId,
            spanId: spanId,
            traceFlags: traceFlags,
            traceState: traceState
        )
        let attributes: [String: OpenTelemetryApi.AttributeValue] = [
            "foo": .string("bar")
        ]

        let spanLink = OTelSpanLink(
            context: spanContext,
            attributes: attributes
        )

        let encoded = try encoder.encode(spanLink)
        let decoded = try JSONDecoder().decode([String: AnyDecodable].self, from: encoded)

        XCTAssertEqual(decoded["trace_id"]?.value as? String, "00000000000000000000000000000065")
        XCTAssertEqual(decoded["span_id"]?.value as? String, "0000000000000067")
        XCTAssertEqual(decoded["attributes"]?.value as? [String: String], ["foo": "bar"])
        XCTAssertEqual(decoded["tracestate"]?.value as? String, "foo=bar,bar=baz")
        XCTAssertEqual(decoded["flags"]?.value as? Int, 1)
    }

    func testEncoder_givenOnlyRequiredPropertiesArePresent() throws {
        let encoder = JSONEncoder()
        let traceId = TraceId(idHi: 101, idLo: 102)
        let spanId = SpanId(id: 103)
        let traceFlags = TraceFlags()
        let traceState = TraceState()

        let spanContext = OpenTelemetryApi.SpanContext.create(
            traceId: traceId,
            spanId: spanId,
            traceFlags: traceFlags,
            traceState: traceState
        )

        let spanLink = OTelSpanLink(
            context: spanContext,
            attributes: [:]
        )

        let encoded = try encoder.encode(spanLink)
        let decoded = try JSONDecoder().decode([String: AnyDecodable].self, from: encoded)

        XCTAssertEqual(decoded["trace_id"]?.value as? String, "00000000000000000000000000000065")
        XCTAssertEqual(decoded["span_id"]?.value as? String, "0000000000000067")
        XCTAssertNil(decoded["attributes"]?.value)
        XCTAssertNil(decoded["tracestate"]?.value)
        XCTAssertEqual(decoded["flags"]?.value as? Int, 0)
    }
}
