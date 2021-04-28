/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import XCTest
@testable import Datadog

class SpanBuilderTests: XCTestCase {
    func testBuildingBasicSpan() {
        let builder: SpanBuilder = .mockWith(serviceName: "test-service-name")
        let ddspan = DDSpan(
            tracer: .mockAny(),
            context: .mockWith(traceID: 1, spanID: 2, parentSpanID: 1),
            operationName: "operation-name",
            startTime: .mockDecember15th2019At10AMUTC(),
            tags: ["foo": "bar", "bizz": 123]
        )
        let span = builder.createSpan(from: ddspan, finishTime: .mockDecember15th2019At10AMUTC(addingTimeInterval: 0.5))

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
        XCTAssertEqual(span.tags, ["foo": "bar", "bizz": "123"])
    }

    func testBuildingSpanWithErrorTagSet() {
        let builder: SpanBuilder = .mockAny()

        // given
        var ddspan: DDSpan = .mockWith(tags: [OTTags.error: true])
        var span = builder.createSpan(from: ddspan, finishTime: .mockAny())

        // then
        XCTAssertTrue(span.isError)
        XCTAssertEqual(span.tags, ["error": "true"])

        // given
        ddspan = .mockWith(tags: [OTTags.error: false])
        span = builder.createSpan(from: ddspan, finishTime: .mockAny())

        // then
        XCTAssertFalse(span.isError)
        XCTAssertEqual(span.tags, ["error": "false"])
    }

    func testBuildingSpanWithErrorLogsSend() {
        let builder: SpanBuilder = .mockAny()

        // given
        var ddspan: DDSpan = .mockWith(tags: [:])
        ddspan.log(fields: [OTLogFields.errorKind: "Swift error"])
        var span = builder.createSpan(from: ddspan, finishTime: .mockAny())

        // then
        XCTAssertTrue(span.isError)
        XCTAssertEqual(span.tags, ["error.type": "Swift error"]) // remapped to `error.type`

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
        span = builder.createSpan(from: ddspan, finishTime: .mockAny())

        // then
        XCTAssertTrue(span.isError)
        XCTAssertEqual(
            span.tags,
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
        span = builder.createSpan(from: ddspan, finishTime: .mockAny())

        // then
        XCTAssertTrue(span.isError)
        XCTAssertEqual(span.tags, ["error.type": "Swift error 1"]) // only first error log is captured
    }

    func testBuildingSpanWithErrorTagAndErrorLogsSend() {
        let builder: SpanBuilder = .mockAny()

        // given
        var ddspan: DDSpan = .mockWith(tags: ["error": true])
        ddspan.log(fields: [OTLogFields.event: "error"])
        var span = builder.createSpan(from: ddspan, finishTime: .mockAny())

        // then
        XCTAssertTrue(span.isError)

        // given
        ddspan = .mockWith(tags: ["error": false])
        ddspan.log(fields: [OTLogFields.event: "error"])
        span = builder.createSpan(from: ddspan, finishTime: .mockAny())

        // then
        XCTAssertTrue(span.isError)
    }

    func testBuildingSpanWithResourceNameTagSet() {
        let builder: SpanBuilder = .mockAny()

        // given
        let ddspan: DDSpan = .mockWith(tags: [DDTags.resource: "custom resource name"])
        let span = builder.createSpan(from: ddspan, finishTime: .mockAny())

        // then
        XCTAssertEqual(span.resource, "custom resource name")
        XCTAssertEqual(span.tags, [:])
    }

    // MARK: - Attributes Conversion

    private struct Foo: Encodable {
        let bar: String = "bar"
        let bizz = Bizz()

        struct Bizz: Encodable {
            let buzz: String = "buzz"
        }
    }

    func testWhenBuildingSpan_itConvertsTagValuesToString() {
        let builder: SpanBuilder = .mockAny()
        let ddspan: DDSpan = .mockAny()

        ddspan.setTag(key: "string-attribute", value: "string value")
        ddspan.setTag(key: "int-attribute", value: 42)
        ddspan.setTag(key: "int64-attribute", value: Int64(42))
        ddspan.setTag(key: "double-attribute", value: 42.5)
        ddspan.setTag(key: "bool-attribute", value: true)
        ddspan.setTag(key: "int-array-attribute", value: [1, 2, 3, 4])
        ddspan.setTag(key: "dictionary-attribute", value: ["key": 1])
        ddspan.setTag(key: "url-attribute", value: URL(string: "https://datadoghq.com")!)
        ddspan.setTag(key: "encodable-struct-attribute", value: Foo())

        // When
        let span = builder.createSpan(from: ddspan, finishTime: .mockAny())

        // Then
        XCTAssertEqual(span.tags["string-attribute"], "string value")
        XCTAssertEqual(span.tags["int-attribute"], "42")
        XCTAssertEqual(span.tags["int64-attribute"], "42")
        XCTAssertEqual(span.tags["double-attribute"], "42.5")
        XCTAssertEqual(span.tags["bool-attribute"], "true")
        XCTAssertEqual(span.tags["int-array-attribute"], "[1,2,3,4]")
        XCTAssertEqual(span.tags["dictionary-attribute"], "{\"key\":1}")
        XCTAssertEqual(span.tags["url-attribute"], "https://datadoghq.com")
        XCTAssertEqual(span.tags["encodable-struct-attribute"], "{\"bar\":\"bar\",\"bizz\":{\"buzz\":\"buzz\"}}")
    }

    func testWhenBuildingSpan_itConvertsUserExtraInfoValuesToString() {
        let builder: SpanBuilder = .mockWith(
            userInfoProvider: .mockWith(
                userInfo: .init(
                    id: .mockRandom(),
                    name: .mockRandom(),
                    email: .mockRandom(),
                    extraInfo: [
                        "string-attribute": "string value",
                        "int-attribute": 42,
                        "int64-attribute": Int64(42),
                        "double-attribute": 42.5,
                        "bool-attribute": true,
                        "int-array-attribute": [1, 2, 3, 4],
                        "dictionary-attribute": ["key": 1],
                        "url-attribute": URL(string: "https://datadoghq.com")!,
                        "encodable-struct-attribute": Foo()
                    ]
                )
            )
        )
        let ddspan: DDSpan = .mockAny()

        // When
        let span = builder.createSpan(from: ddspan, finishTime: .mockAny())

        // Then
        XCTAssertEqual(span.userInfo.extraInfo["string-attribute"], "string value")
        XCTAssertEqual(span.userInfo.extraInfo["int-attribute"], "42")
        XCTAssertEqual(span.userInfo.extraInfo["int64-attribute"], "42")
        XCTAssertEqual(span.userInfo.extraInfo["double-attribute"], "42.5")
        XCTAssertEqual(span.userInfo.extraInfo["bool-attribute"], "true")
        XCTAssertEqual(span.userInfo.extraInfo["int-array-attribute"], "[1,2,3,4]")
        XCTAssertEqual(span.userInfo.extraInfo["dictionary-attribute"], "{\"key\":1}")
        XCTAssertEqual(span.userInfo.extraInfo["url-attribute"], "https://datadoghq.com")
        XCTAssertEqual(span.userInfo.extraInfo["encodable-struct-attribute"], "{\"bar\":\"bar\",\"bizz\":{\"buzz\":\"buzz\"}}")
    }

    func testWhenTagValueCannotBeConvertedToString_itPrintsErrorAndSkipsTheTag() {
        let previousUserLogger = userLogger
        defer { userLogger = previousUserLogger }

        let output = LogOutputMock()
        userLogger = .mockWith(logOutput: output)

        let builder: SpanBuilder = .mockAny()
        let ddspan: DDSpan = .mockAny()

        // When
        ddspan.setTag(key: "failing-tag", value: FailingEncodableMock(errorMessage: "Value cannot be encoded."))

        // Then
        let span = builder.createSpan(from: ddspan, finishTime: .mockAny())

        XCTAssertNil(span.tags["failing-tag"])
        XCTAssertEqual(output.recordedLog?.status, .error)
        XCTAssertEqual(
            output.recordedLog?.message,
            """
            Failed to convert span `Encodable` attribute to `String`. The value of `failing-tag` will not be sent.
            """
        )
        XCTAssertEqual(output.recordedLog?.error?.message, "Value cannot be encoded.")
    }
}
