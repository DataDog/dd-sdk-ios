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

class SpanEventBuilderTests: XCTestCase {
    func testBuildingBasicSpan() {
        let context: DatadogContext = .mockWith(sdkVersion: "1.2.3")
        let builder: SpanEventBuilder = .mockWith(service: "test-service-name")

        let span = builder.createSpanEvent(
            context: context,
            traceID: .init(idHi: 10, idLo: 100),
            spanID: 200,
            parentSpanID: 1,
            operationName: "operation-name",
            startTime: .mockDecember15th2019At10AMUTC(),
            finishTime: .mockDecember15th2019At10AMUTC(addingTimeInterval: 0.5),
            samplingRate: .mockAny(),
            samplingPriority: .mockAny(),
            samplingDecisionMaker: .mockAny(),
            tags: [
                "foo": "bar",
                "bizz": 123
            ],
            baggageItems: [:],
            logFields: []
        )

        XCTAssertEqual(span.traceID, .init(idHi: 10, idLo: 100))
        XCTAssertEqual(span.spanID, .init(rawValue: 200))
        XCTAssertEqual(span.parentID, 1)
        XCTAssertEqual(span.operationName, "operation-name")
        XCTAssertEqual(span.serviceName, "test-service-name")
        XCTAssertEqual(span.resource, "operation-name")
        XCTAssertEqual(span.startTime, .mockDecember15th2019At10AMUTC())
        XCTAssertEqual(span.duration, 0.50, accuracy: 0.01)
        XCTAssertFalse(span.isError)
        XCTAssertEqual(span.tracerVersion, "1.2.3")
        XCTAssertEqual(span.tags, ["foo": "bar", "bizz": "123"])
    }

    func testGivenBuilderWithEventMapper_whenEventIsModified_itBuildsModifiedEvent() throws {
        let builder: SpanEventBuilder = .mockWith(
            eventsMapper: { span in
                var mutableSpan = span
                mutableSpan.operationName = "modified operation name"
                mutableSpan.tags = .mockRandom()
                return mutableSpan
            }
        )

        let span = builder.createSpanEvent(
            context: .mockAny(),
            traceID: .mockAny(),
            spanID: .mockAny(),
            parentSpanID: .mockAny(),
            operationName: "original operation name",
            startTime: .mockAny(),
            finishTime: .mockAny(),
            samplingRate: .mockAny(),
            samplingPriority: .mockAny(),
            samplingDecisionMaker: .mockAny(),
            tags: [:],
            baggageItems: [:],
            logFields: []
        )

        XCTAssertEqual(span.operationName, "modified operation name")
        XCTAssertGreaterThan(span.tags.count, 0)
    }

    func testBuildingSpanWithErrorTagSet() {
        let builder: SpanEventBuilder = .mockAny()

        // given
        var span = builder.createSpanEvent(
            context: .mockAny(),
            traceID: .mockAny(),
            spanID: .mockAny(),
            parentSpanID: .mockAny(),
            operationName: .mockAny(),
            startTime: .mockAny(),
            finishTime: .mockAny(),
            samplingRate: .mockAny(),
            samplingPriority: .mockAny(),
            samplingDecisionMaker: .mockAny(),
            tags: [OTTags.error: true],
            baggageItems: [:],
            logFields: []
        )

        // then
        XCTAssertTrue(span.isError)
        XCTAssertEqual(span.tags, ["error": "true"])

        // given
        span = builder.createSpanEvent(
            context: .mockAny(),
            traceID: .mockAny(),
            spanID: .mockAny(),
            parentSpanID: .mockAny(),
            operationName: .mockAny(),
            startTime: .mockAny(),
            finishTime: .mockAny(),
            samplingRate: .mockAny(),
            samplingPriority: .mockAny(),
            samplingDecisionMaker: .mockAny(),
            tags: [OTTags.error: false],
            baggageItems: [:],
            logFields: []
        )

        // then
        XCTAssertFalse(span.isError)
        XCTAssertEqual(span.tags, ["error": "false"])
    }

    func testBuildingSpanWithErrorLogsSend() {
        let builder: SpanEventBuilder = .mockAny()

        // given
        var span = builder.createSpanEvent(
            context: .mockAny(),
            traceID: .mockAny(),
            spanID: .mockAny(),
            parentSpanID: .mockAny(),
            operationName: .mockAny(),
            startTime: .mockAny(),
            finishTime: .mockAny(),
            samplingRate: .mockAny(),
            samplingPriority: .mockAny(),
            samplingDecisionMaker: .mockAny(),
            tags: [:],
            baggageItems: [:],
            logFields: [
                [OTLogFields.errorKind: "Swift error"]
            ]
        )

        // then
        XCTAssertTrue(span.isError)
        XCTAssertEqual(span.tags, ["error.type": "Swift error"]) // remapped to `error.type`

        // given
        span = builder.createSpanEvent(
            context: .mockAny(),
            traceID: .mockAny(),
            spanID: .mockAny(),
            parentSpanID: .mockAny(),
            operationName: .mockAny(),
            startTime: .mockAny(),
            finishTime: .mockAny(),
            samplingRate: .mockAny(),
            samplingPriority: .mockAny(),
            samplingDecisionMaker: .mockAny(),
            tags: [:],
            baggageItems: [:],
            logFields: [
                [
                    OTLogFields.errorKind: "Swift error",
                    OTLogFields.event: "error",
                    OTLogFields.message: "Error occurred",
                    OTLogFields.stack: "Foo.swift:42",
                ]
            ]
        )

        // then
        XCTAssertTrue(span.isError)
        XCTAssertEqual(
            span.tags,
            [
                "error.type": "Swift error",    // remapped to `error.type`
                "error.msg": "Error occurred",   // remapped to `error.msg`
                "error.stack": "Foo.swift:42",  // remapped to `error.stack`
            ]
        )

        // given
        span = builder.createSpanEvent(
            context: .mockAny(),
            traceID: .mockAny(),
            spanID: .mockAny(),
            parentSpanID: .mockAny(),
            operationName: .mockAny(),
            startTime: .mockAny(),
            finishTime: .mockAny(),
            samplingRate: .mockAny(),
            samplingPriority: .mockAny(),
            samplingDecisionMaker: .mockAny(),
            tags: [:],
            baggageItems: [:],
            logFields: [
                ["foo": "bar"], // ignored
                [OTLogFields.errorKind: "Swift error 1"], // captured
                [OTLogFields.errorKind: "Swift error 2"] // ignored
            ]
        )

        // then
        XCTAssertTrue(span.isError)
        XCTAssertEqual(span.tags, ["error.type": "Swift error 1"]) // only first error log is captured
    }

    func testBuildingSpanWithErrorTagAndErrorLogsSend() {
        let builder: SpanEventBuilder = .mockAny()

        // given
        var span = builder.createSpanEvent(
            context: .mockAny(),
            traceID: .mockAny(),
            spanID: .mockAny(),
            parentSpanID: .mockAny(),
            operationName: .mockAny(),
            startTime: .mockAny(),
            finishTime: .mockAny(),
            samplingRate: .mockAny(),
            samplingPriority: .mockAny(),
            samplingDecisionMaker: .mockAny(),
            tags: [
                "error": true
            ],
            baggageItems: [:],
            logFields: [
                [OTLogFields.event: "error"]
            ]
        )

        // then
        XCTAssertTrue(span.isError)

        // given
        span = builder.createSpanEvent(
            context: .mockAny(),
            traceID: .mockAny(),
            spanID: .mockAny(),
            parentSpanID: .mockAny(),
            operationName: .mockAny(),
            startTime: .mockAny(),
            finishTime: .mockAny(),
            samplingRate: .mockAny(),
            samplingPriority: .mockAny(),
            samplingDecisionMaker: .mockAny(),
            tags: [
                "error": false
            ],
            baggageItems: [:],
            logFields: [
                [OTLogFields.event: "error"]
            ]
        )

        // then
        XCTAssertTrue(span.isError)
    }

    func testBuildingSpanWithResourceNameTagSet() {
        let builder: SpanEventBuilder = .mockAny()

        // given
        let span = builder.createSpanEvent(
            context: .mockAny(),
            traceID: .mockAny(),
            spanID: .mockAny(),
            parentSpanID: .mockAny(),
            operationName: .mockAny(),
            startTime: .mockAny(),
            finishTime: .mockAny(),
            samplingRate: .mockAny(),
            samplingPriority: .mockAny(),
            samplingDecisionMaker: .mockAny(),
            tags: [
                SpanTags.resource: "custom resource name"
            ],
            baggageItems: [:],
            logFields: []
        )

        // then
        XCTAssertEqual(span.resource, "custom resource name")
        XCTAssertEqual(span.tags, [:])
    }

    func testBuildingSpanWithOperationNameTagSet() {
        let builder: SpanEventBuilder = .mockAny()

        // given
        let span = builder.createSpanEvent(
            context: .mockAny(),
            traceID: .mockAny(),
            spanID: .mockAny(),
            parentSpanID: .mockAny(),
            operationName: .mockAny(),
            startTime: .mockAny(),
            finishTime: .mockAny(),
            samplingRate: .mockAny(),
            samplingPriority: .mockAny(),
            samplingDecisionMaker: .mockAny(),
            tags: [
                SpanTags.operation: "custom operation name"
            ],
            baggageItems: [:],
            logFields: []
        )

        // then
        XCTAssertEqual(span.operationName, "custom operation name")
        XCTAssertEqual(span.tags, [:])
    }

    func testBuildingSpanWithServiceNameTagSet() {
        let builder: SpanEventBuilder = .mockAny()

        // given
        let span = builder.createSpanEvent(
            context: .mockAny(),
            traceID: .mockAny(),
            spanID: .mockAny(),
            parentSpanID: .mockAny(),
            operationName: .mockAny(),
            startTime: .mockAny(),
            finishTime: .mockAny(),
            samplingRate: .mockAny(),
            samplingPriority: .mockAny(),
            samplingDecisionMaker: .mockAny(),
            tags: [
                SpanTags.service: "custom service name"
            ],
            baggageItems: [:],
            logFields: []
        )

        // then
        XCTAssertEqual(span.serviceName, "custom service name")
        XCTAssertEqual(span.tags, [:])
    }

    func testItSendsBaggageItemsAsTags() {
        let builder: SpanEventBuilder = .mockAny()

        // When
        let span = builder.createSpanEvent(
            context: .mockAny(),
            traceID: .mockAny(),
            spanID: .mockAny(),
            parentSpanID: .mockAny(),
            operationName: .mockAny(),
            startTime: .mockAny(),
            finishTime: .mockAny(),
            samplingRate: .mockAny(),
            samplingPriority: .mockAny(),
            samplingDecisionMaker: .mockAny(),
            tags: [
                "tag-name": "tag value"
            ],
            baggageItems: [
                "item-1": "value 1",
                "item-2": "value 2",
                "tag-name": "baggage item value"
            ],
            logFields: []
        )

        // Then
        XCTAssertEqual(span.tags.count, 3)
        XCTAssertEqual(span.tags["item-1"], "value 1")
        XCTAssertEqual(span.tags["item-2"], "value 2")
        XCTAssertEqual(span.tags["tag-name"], "tag value", "It should prefer tags over baggage items if their names duplicate")
    }

    func testBuildingKeptRootSpanWithSamplingRateSet() {
        let builder: SpanEventBuilder = .mockAny()

        // When
        let span = builder.createSpanEvent(
            context: .mockAny(),
            traceID: .mockAny(),
            spanID: .mockAny(),
            parentSpanID: nil,
            operationName: .mockAny(),
            startTime: .mockAny(),
            finishTime: .mockAny(),
            samplingRate: 0.42,
            samplingPriority: .autoKeep,
            samplingDecisionMaker: .agentRate,
            tags: [
                "tag-name": "tag value"
            ],
            baggageItems: [
                "item-1": "value 1",
                "item-2": "value 2",
                "tag-name": "baggage item value"
            ],
            logFields: []
        )

        // Then
        XCTAssertEqual(span.samplingRate, 0.42)
        XCTAssertTrue(span.samplingPriority.isKept)
        XCTAssertEqual(span.samplingDecisionMaker, .agentRate)
    }

    func testBuildingDiscardedRootSpanWithSamplingRateSet() {
        let builder: SpanEventBuilder = .mockAny()

        // When
        let span = builder.createSpanEvent(
            context: .mockAny(),
            traceID: .mockAny(),
            spanID: .mockAny(),
            parentSpanID: nil,
            operationName: .mockAny(),
            startTime: .mockAny(),
            finishTime: .mockAny(),
            samplingRate: 0.13,
            samplingPriority: .autoDrop,
            samplingDecisionMaker: .agentRate,
            tags: [
                "tag-name": "tag value"
            ],
            baggageItems: [
                "item-1": "value 1",
                "item-2": "value 2",
                "tag-name": "baggage item value"
            ],
            logFields: []
        )

        // Then
        XCTAssertEqual(span.samplingRate, 0.13)
        XCTAssertFalse(span.samplingPriority.isKept)
        XCTAssertEqual(span.samplingDecisionMaker, .agentRate)
    }

    // MARK: - Attributes Conversion

    private struct Foo: Encodable {
        let bar: String = "bar"
        let bizz = Bizz()

        struct Bizz: Encodable {
            let buzz: String = "buzz"
        }
    }

    private func createMockAttributes() -> [String: Encodable] {
        [
            "string-attribute": "string value",
            "int-attribute": 42,
            "int64-attribute": Int64(42),
            "double-attribute": 42.5,
            "bool-attribute": true,
            "int-array-attribute": [1, 2, 3, 4],
            "dictionary-attribute": ["key": 1],
            "url-attribute": URL(string: "https://datadoghq.com")!,
            "encodable-struct-attribute": Foo(),
        ]
    }

    private let expectedAttributes: [String: String] = [
        "string-attribute": "string value",
        "int-attribute": "42",
        "int64-attribute": "42",
        "double-attribute": "42.5",
        "bool-attribute": "true",
        "int-array-attribute": "[1,2,3,4]",
        "dictionary-attribute": "{\"key\":1}",
        "url-attribute": "https://datadoghq.com",
        "encodable-struct-attribute": "{\"bar\":\"bar\",\"bizz\":{\"buzz\":\"buzz\"}}",
    ]

    func testWhenBuildingSpan_itConvertsTagValuesToString() {
        let builder: SpanEventBuilder = .mockAny()

        // When
        let span = builder.createSpanEvent(
            context: .mockAny(),
            traceID: .mockAny(),
            spanID: .mockAny(),
            parentSpanID: .mockAny(),
            operationName: .mockAny(),
            startTime: .mockAny(),
            finishTime: .mockAny(),
            samplingRate: .mockAny(),
            samplingPriority: .mockAny(),
            samplingDecisionMaker: .mockAny(),
            tags: createMockAttributes(),
            baggageItems: [:],
            logFields: []
        )

        // Then
        expectedAttributes.forEach { tagKey, tagValue in
            XCTAssertEqual(span.tags[tagKey], tagValue)
        }
    }

    func testWhenBuildingSpan_itConvertsUserExtraInfoValuesToString() {
        let builder: SpanEventBuilder = .mockAny()

        // When
        let span = builder.createSpanEvent(
            context: .mockWith(
                userInfo: .init(
                    id: .mockRandom(),
                    name: .mockRandom(),
                    email: .mockRandom(),
                    extraInfo: createMockAttributes()
                )
            ),
            traceID: .mockAny(),
            spanID: .mockAny(),
            parentSpanID: .mockAny(),
            operationName: .mockAny(),
            startTime: .mockAny(),
            finishTime: .mockAny(),
            samplingRate: .mockAny(),
            samplingPriority: .mockAny(),
            samplingDecisionMaker: .mockAny(),
            tags: [:],
            baggageItems: [:],
            logFields: []
        )

        // Then
        expectedAttributes.forEach { extraInfoKey, extraInfoValue in
            XCTAssertEqual(span.userInfo.extraInfo[extraInfoKey], extraInfoValue)
        }
    }

    func testWhenTagValueCannotBeConvertedToString_itPrintsErrorAndSkipsTheTag() {
        let dd = DD.mockWith(logger: CoreLoggerMock())
        defer { dd.reset() }

        let builder: SpanEventBuilder = .mockAny()

        // When
        let errorMessage = "Value cannot be encoded."
        let span = builder.createSpanEvent(
            context: .mockAny(),
            traceID: .mockAny(),
            spanID: .mockAny(),
            parentSpanID: .mockAny(),
            operationName: .mockAny(),
            startTime: .mockAny(),
            finishTime: .mockAny(),
            samplingRate: .mockAny(),
            samplingPriority: .mockAny(),
            samplingDecisionMaker: .mockAny(),
            tags: [
                "failing-tag": FailingEncodableMock(errorMessage: errorMessage)
            ],
            baggageItems: [:],
            logFields: []
        )

        // Then
        XCTAssertNil(span.tags["failing-tag"])
        XCTAssertEqual(
            dd.logger.errorLog?.message,
            """
            Failed to encode attribute \'failing-tag\' to `String`. This attribute will be dropped from the span.
            """
        )
        XCTAssertEqual(dd.logger.errorLog?.error?.message, errorMessage)
    }

    func testBuildingSpanWhenSpanLinkIsPresentInTags() {
        let dd = DD.mockWith(logger: CoreLoggerMock())
        defer { dd.reset() }

        let builder: SpanEventBuilder = .mockAny()

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

        // When
        let span = builder.createSpanEvent(
            context: .mockAny(),
            traceID: .mockAny(),
            spanID: .mockAny(),
            parentSpanID: .mockAny(),
            operationName: .mockAny(),
            startTime: .mockAny(),
            finishTime: .mockAny(),
            samplingRate: .mockAny(),
            samplingPriority: .mockAny(),
            samplingDecisionMaker: .mockAny(),
            tags: [
                DatadogTagKeys.spanLinks.rawValue: [spanLink]
            ],
            baggageItems: [:],
            logFields: []
        )

        // Then
        XCTAssertEqual(span.tags.count, 1)
        let expectedTags = "[{\"attributes\":{\"foo\":\"bar\"},\"flags\":1,\"span_id\":\"0000000000000067\",\"trace_id\":\"00000000000000650000000000000066\",\"tracestate\":\"foo=bar,bar=baz\"}]"
        let actualTags = span.tags["_dd.span_links"]

        DDAssertJSONEqual(expectedTags, actualTags!)
    }

    // MARK: - RUM context enrichment

    // swiftlint:disable opening_brace
    func testWhenBundleWithRUMisEnabled_itCreatesSpanWithRUMContext() {
        // Given
        let rum = oneOf([
            { RUMCoreContext(applicationID: .mockRandom(), sessionID: .mockRandom(), viewID: .mockRandom(), userActionID: .mockRandom()) },
            { RUMCoreContext(applicationID: .mockRandom(), sessionID: .mockRandom(), viewID: .mockRandom(), userActionID: nil) },
            { RUMCoreContext(applicationID: .mockRandom(), sessionID: .mockRandom(), viewID: nil, userActionID: nil) }
        ])
        let context: DatadogContext = .mockWith(additionalContext: [rum])

        // When
        let builder: SpanEventBuilder = .mockWith(bundleWithRUM: true)
        let span = builder.createSpanEvent(
            context: context,
            traceID: .mockAny(),
            spanID: .mockAny(),
            parentSpanID: .mockAny(),
            operationName: .mockAny(),
            startTime: .mockAny(),
            finishTime: .mockAny(),
            samplingRate: .mockAny(),
            samplingPriority: .mockAny(),
            samplingDecisionMaker: .mockAny(),
            tags: [:],
            baggageItems: [:],
            logFields: []
        )

        // Then
        XCTAssertEqual(span.tags[SpanTags.rumApplicationID], rum.applicationID)
        XCTAssertEqual(span.tags[SpanTags.rumSessionID], rum.sessionID)
        XCTAssertEqual(span.tags[SpanTags.rumViewID], rum.viewID)
        XCTAssertEqual(span.tags[SpanTags.rumActionID], rum.userActionID)
    }
    // swiftlint:enable opening_brace

    func testWhenBundleWithRUMisDisabled_itCreatesSpanWithNoRUMContext() {
        // Given
        let rum = RUMCoreContext(
            applicationID: .mockRandom(),
            sessionID: .mockRandom(),
            viewID: .mockRandom(),
            userActionID: .mockRandom()
        )
        let context: DatadogContext = .mockWith(additionalContext: [rum])

        // When
        let builder: SpanEventBuilder = .mockWith(bundleWithRUM: false)
        let span = builder.createSpanEvent(
            context: context,
            traceID: .mockAny(),
            spanID: .mockAny(),
            parentSpanID: .mockAny(),
            operationName: .mockAny(),
            startTime: .mockAny(),
            finishTime: .mockAny(),
            samplingRate: .mockAny(),
            samplingPriority: .mockAny(),
            samplingDecisionMaker: .mockAny(),
            tags: [:],
            baggageItems: [:],
            logFields: []
        )

        // Then
        XCTAssertNil(span.tags[SpanTags.rumApplicationID])
        XCTAssertNil(span.tags[SpanTags.rumSessionID])
        XCTAssertNil(span.tags[SpanTags.rumViewID])
        XCTAssertNil(span.tags[SpanTags.rumActionID])
    }
}
