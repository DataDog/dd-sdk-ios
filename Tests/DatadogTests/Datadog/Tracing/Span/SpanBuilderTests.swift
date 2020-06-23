/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import XCTest
@testable import Datadog

class SpanBuilderTests: XCTestCase {
    func testBuildingBasicSpan() throws {
        let builder: SpanBuilder = .mockWith(serviceName: "test-service-name")
        let ddspan = DDSpan(
            tracer: .mockAny(),
            context: .mockWith(traceID: 1, spanID: 2, parentSpanID: 1),
            operationName: "operation-name",
            startTime: .mockDecember15th2019At10AMUTC(),
            tags: ["foo": "bar", "bizz": 123]
        )
        let span = try builder.createSpan(from: ddspan, finishTime: .mockDecember15th2019At10AMUTC(addingTimeInterval: 0.5))

        XCTAssertEqual(span.traceID, 1)
        XCTAssertEqual(span.spanID, 2)
        XCTAssertEqual(span.parentID, 1)
        XCTAssertEqual(span.operationName, "operation-name")
        XCTAssertEqual(span.serviceName, "test-service-name")
        XCTAssertEqual(span.resource, "operation-name")
        XCTAssertEqual(span.startTime, .mockDecember15th2019At10AMUTC())
        XCTAssertEqual(span.duration, 0.50, accuracy: 0.01)
        XCTAssertFalse(span.isError)
        XCTAssertEqual(span.tracerVersion, sdkVersion)
        XCTAssertEqual(try span.tags.toEquatable(), ["foo": "bar", "bizz": "123"])
    }

    func testBuildingSpanWithErrorTagSet() throws {
        let builder: SpanBuilder = .mockAny()

        // given
        var ddspan: DDSpan = .mockWith(tags: [OTTags.error: true])
        var span = try builder.createSpan(from: ddspan, finishTime: .mockAny())

        // then
        XCTAssertTrue(span.isError)
        XCTAssertEqual(try span.tags.toEquatable(), ["error": "true"])

        // given
        ddspan = .mockWith(tags: [OTTags.error: false])
        span = try builder.createSpan(from: ddspan, finishTime: .mockAny())

        // then
        XCTAssertFalse(span.isError)
        XCTAssertEqual(try span.tags.toEquatable(), ["error": "false"])
    }

    func testBuildingSpanWithErrorLogsSend() throws {
        let builder: SpanBuilder = .mockAny()

        // given
        var ddspan: DDSpan = .mockWith(tags: [:])
        ddspan.log(fields: [OTLogFields.errorKind: "Swift error"])
        var span = try builder.createSpan(from: ddspan, finishTime: .mockAny())

        // then
        XCTAssertTrue(span.isError)
        XCTAssertEqual(try span.tags.toEquatable(), ["error.type": "Swift error"]) // remapped to `error.type`

        // given
        ddspan = .mockWith(tags: [:])
        ddspan.log(
            fields: [
                OTLogFields.errorKind: "Swift error",
                OTLogFields.event: "error",
                OTLogFields.message: "Error occured",
                OTLogFields.stack: "Foo.swift:42",
            ]
        )
        span = try builder.createSpan(from: ddspan, finishTime: .mockAny())

        // then
        XCTAssertTrue(span.isError)
        XCTAssertEqual(
            try span.tags.toEquatable(),
            [
                "error.type": "Swift error",    // remapped to `error.type`
                "error.msg": "Error occured",   // remapped to `error.msg`
                "error.stack": "Foo.swift:42",  // remapped to `error.stack`
            ]
        )

        // given
        ddspan = .mockWith(tags: [:])
        ddspan.log(fields: ["foo": "bar"]) // ignored
        ddspan.log(fields: [OTLogFields.errorKind: "Swift error 1"]) // captured
        ddspan.log(fields: [OTLogFields.errorKind: "Swift error 2"]) // ignored
        span = try builder.createSpan(from: ddspan, finishTime: .mockAny())

        // then
        XCTAssertTrue(span.isError)
        XCTAssertEqual(try span.tags.toEquatable(), ["error.type": "Swift error 1"]) // only first error log is captured
    }

    func testBuildingSpanWithErrorTagAndErrorLogsSend() throws {
        let builder: SpanBuilder = .mockAny()

        // given
        var ddspan: DDSpan = .mockWith(tags: ["error": true])
        ddspan.log(fields: [OTLogFields.event: "error"])
        var span = try builder.createSpan(from: ddspan, finishTime: .mockAny())

        // then
        XCTAssertTrue(span.isError)

        // given
        ddspan = .mockWith(tags: ["error": false])
        ddspan.log(fields: [OTLogFields.event: "error"])
        span = try builder.createSpan(from: ddspan, finishTime: .mockAny())

        // then
        XCTAssertTrue(span.isError)
    }

    func testBuildingSpanWithResourceNameTagSet() throws {
        let builder: SpanBuilder = .mockAny()

        // given
        let ddspan: DDSpan = .mockWith(tags: [DDTags.resource: "custom resource name"])
        let span = try builder.createSpan(from: ddspan, finishTime: .mockAny())

        // then
        XCTAssertEqual(span.resource, "custom resource name")
        XCTAssertEqual(try span.tags.toEquatable(), [:])
    }
}

private extension Dictionary where Key == String, Value == JSONStringEncodableValue {
    /// Converts `[String: JSONStringEncodableValue]` to `[String: String]` for equitability comparison.
    func toEquatable() throws -> [String: String] {
        let data = try JSONEncoder().encode(self)
        return try data.toJSONObject().mapValues { $0 as! String }
    }
}
