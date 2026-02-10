/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import TestUtilities
import DatadogInternal

@testable import DatadogTrace

class DDSpanTests: XCTestCase {
    // MARK: - Sending SpanEvent

    func testWhenSpanIsFinished_itWritesSpanEventToCore() throws {
        let writeSpansExpectation = expectation(description: "write span event")
        let core = PassthroughCoreMock()
        core.onEventWriteContext = { _ in writeSpansExpectation.fulfill() }

        // Given
        let tracer: DatadogTracer = .mockWith(core: core)
        let span = tracer.startSpan(operationName: .mockAny())

        // When
        span.finish()

        // Then
        waitForExpectations(timeout: 0.5, handler: nil)
    }

    // MARK: - Customizing SpanEvents

    func testWhenSettingCustomOperationName_itOverwritesOriginalName() throws {
        let writeSpansExpectation = expectation(description: "write 2 span events")
        writeSpansExpectation.expectedFulfillmentCount = 2
        let core = PassthroughCoreMock()
        core.onEventWriteContext = { _ in writeSpansExpectation.fulfill() }

        // Given
        let defaultOperationName: String = .mockRandom()
        let tracer: DatadogTracer = .mockWith(core: core)
        let defaultSpan = tracer.startSpan(operationName: defaultOperationName)
        let customizedSpan = tracer.startSpan(operationName: defaultOperationName)

        // When
        let customizedOperationName: String = .mockRandom()
        customizedSpan.setOperationName(customizedOperationName)

        // Then
        defaultSpan.finish()
        customizedSpan.finish()

        waitForExpectations(timeout: 0.5, handler: nil)
        let events: [SpanEventsEnvelope] = core.events()
        XCTAssertEqual(events.count, 2)
        XCTAssertEqual(events[0].spans.first?.operationName, defaultOperationName)
        XCTAssertEqual(events[1].spans.first?.operationName, customizedOperationName)
    }

    func testWhenSettingCustomTags_theyAreMergedWithDefaultTags() throws {
        let writeSpansExpectation = expectation(description: "write 2 span events")
        writeSpansExpectation.expectedFulfillmentCount = 2
        let core = PassthroughCoreMock()
        core.onEventWriteContext = { _ in writeSpansExpectation.fulfill() }

        // Given
        let defaultTags: [String: String] = .mockRandom()
        let tracer: DatadogTracer = .mockWith(core: core)
        let defaultSpan = tracer.startSpan(operationName: .mockAny(), tags: defaultTags)
        let customizedSpan = tracer.startSpan(operationName: .mockAny(), tags: defaultTags)

        // When
        let customTags: [String: String] = .mockRandom()
        customTags.forEach { tagKey, tagValue in
            customizedSpan.setTag(key: tagKey, value: tagValue)
        }

        // Then
        defaultSpan.finish()
        customizedSpan.finish()

        waitForExpectations(timeout: 0.5, handler: nil)
        let events: [SpanEventsEnvelope] = core.events()
        XCTAssertEqual(events.count, 2)
        XCTAssertEqual(events[0].spans.first?.tags, defaultTags)
        XCTAssertEqual(events[1].spans.first?.tags, defaultTags.merging(customTags) { _, custom in custom })
    }

    func testSettingBaggageItems() {
        // Given
        let span: DDSpan = .mockWith(
            core: PassthroughCoreMock(),
            context: .mockWith(baggageItems: BaggageItems())
        )
        XCTAssertEqual(span.ddContext.baggageItems.all, [:])

        // When
        span.setBaggageItem(key: "foo", value: "bar")
        span.setBaggageItem(key: "bizz", value: "buzz")

        // Then
        XCTAssertEqual(span.baggageItem(withKey: "foo"), "bar")
        XCTAssertEqual(span.baggageItem(withKey: "bizz"), "buzz")
        XCTAssertEqual(span.ddContext.baggageItems.all, ["foo": "bar", "bizz": "buzz"])
    }

    // MARK: - Thread Safety

    func testSpanCanBeSafelyAccessedFromDifferentThreads() throws {
        let writeSpansExpectation = expectation(description: "write span event")
        let core = PassthroughCoreMock()
        core.onEventWriteContext = { _ in writeSpansExpectation.fulfill() }

        // Given
        let tracer: DatadogTracer = .mockWith(core: core)
        let span = tracer.startSpan(operationName: .mockAny())

        // When
        callConcurrently(
            closures: [
                // swiftlint:disable opening_brace
                { span.setTag(key: .mockRandom(), value: "value") },
                { span.setBaggageItem(key: .mockRandom(), value: "value") },
                { _ = span.baggageItem(withKey: .mockRandom()) },
                { _ = span.context.forEachBaggageItem { _, _ in return false } },
                // swiftlint:enable opening_brace
            ],
            iterations: 100
        )

        span.finish()

        // Then
        waitForExpectations(timeout: 2, handler: nil)
        let events: [SpanEventsEnvelope] = core.events()
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events[0].spans.first?.tags.count, 200, "It should contain 200 tags (100 explicit tags + 100 baggage items as tags)")
    }

    // MARK: - Usage

    func testGivenFinishedSpan_whenCallingItsAPI_itPrintsErrors() {
        let dd = DD.mockWith(logger: CoreLoggerMock())
        defer { dd.reset() }

        let core = PassthroughCoreMock(messageReceiver: FeatureMessageReceiverMock())
        let tracer: DatadogTracer = .mockWith(core: core)
        let span = tracer.startSpan(operationName: "the span")
        span.finish()

        let fixtures: [(() -> Void, String)] = [
            ({ span.setOperationName(.mockAny()) },
            "🔥 Calling `setOperationName(_:)` on a finished span (\"the span\") is not allowed."),
            ({ span.setTag(key: .mockAny(), value: 0) },
            "🔥 Calling `setTag(key:value:)` on a finished span (\"the span\") is not allowed."),
            ({ span.setBaggageItem(key: .mockAny(), value: .mockAny()) },
            "🔥 Calling `setBaggageItem(key:value:)` on a finished span (\"the span\") is not allowed."),
            ({ _ = span.baggageItem(withKey: .mockAny()) },
            "🔥 Calling `baggageItem(withKey:)` on a finished span (\"the span\") is not allowed."),
            ({ span.finish(at: .mockAny()) },
            "🔥 Calling `finish(at:)` on a finished span (\"the span\") is not allowed."),
            ({ span.log(fields: [:], timestamp: .mockAny()) },
            "🔥 Calling `log(fields:timestamp:)` on a finished span (\"the span\") is not allowed."),
        ]

        fixtures.forEach { tracerMethod, expectedConsoleWarning in
            tracerMethod()
            XCTAssertEqual(dd.logger.warnLog?.message, expectedConsoleWarning)
        }
    }

    // MARK: Sampling convenience methods

    func testKeepTraceFunctionSetsExpectedSamplingDecision() {
        let dd = DD.mockWith(logger: CoreLoggerMock())
        defer { dd.reset() }

        let core = PassthroughCoreMock(messageReceiver: FeatureMessageReceiverMock())
        let tracer: DatadogTracer = .mockWith(core: core)
        let span = tracer.startSpan(operationName: "the span") as! DDSpan
        let context = span.context as! DDSpanContext

        XCTAssertTrue(context.samplingDecision.samplingPriority == .autoKeep || context.samplingDecision.samplingPriority == .autoDrop)
        XCTAssertEqual(context.samplingDecision.decisionMaker, .agentRate)

        span.keepTrace()

        XCTAssertEqual(context.samplingDecision.samplingPriority, .manualKeep)
        XCTAssertEqual(context.samplingDecision.decisionMaker, .manual)
    }

    func testDropTraceFunctionSetsExpectedSamplingDecision() {
        let dd = DD.mockWith(logger: CoreLoggerMock())
        defer { dd.reset() }

        let core = PassthroughCoreMock(messageReceiver: FeatureMessageReceiverMock())
        let tracer: DatadogTracer = .mockWith(core: core)
        let span = tracer.startSpan(operationName: "the span") as! DDSpan
        let context = span.context as! DDSpanContext

        XCTAssertTrue(context.samplingDecision.samplingPriority == .autoKeep || context.samplingDecision.samplingPriority == .autoDrop)
        XCTAssertEqual(context.samplingDecision.decisionMaker, .agentRate)

        span.dropTrace()

        XCTAssertEqual(context.samplingDecision.samplingPriority, .manualDrop)
        XCTAssertEqual(context.samplingDecision.decisionMaker, .manual)
    }

    // MARK: - Attribute Encoding Error Handling

    /// These tests use `AnyEncodable` to wrap non-`Encodable` types, simulating real production scenarios.
    /// There are 2 possible use-cases:
    /// - **ObjC APIs** (primary production path): Customers use ObjC APIs like `startSpan(_:tags:)` which accepts `NSDictionary`.
    ///   SDK automatically wraps non-String/URL values in `AnyEncodable`, losing type safety. Telemetry shows this is the dominant error path.
    /// - **Swift APIs with manual wrapping**: Swift API requires `Encodable`, but customers can explicitly wrap non-encodable
    ///   types using `AnyEncodable(value)` to bypass compile-time checks.

    func testWhenMultipleSpanTagsFailToEncode_itSkipsAllMalformedTags() throws {
        // Given
        let dd = DD.mockWith(logger: CoreLoggerMock())
        defer { dd.reset() }

        let core = PassthroughCoreMock()
        let tracer: DatadogTracer = .mockWith(core: core)
        let span = tracer.startSpan(operationName: "test operation")

        // When - test various non-encodable types (closures are most common from telemetry)
        let closure1: (NSArray) -> Void = { _ in }
        let closure2: () -> Void = { }
        span.setTag(key: "valid_tag", value: "test_value")
        span.setTag(key: "onComplete", value: AnyEncodable(closure1))
        span.setTag(key: "callback", value: AnyEncodable(closure2))
        span.setTag(key: "custom_object", value: AnyEncodable(NSObject()))
        span.finish()

        // Then
        let events: [SpanEventsEnvelope] = core.events()
        XCTAssertEqual(events.count, 1)

        let spanEvent = try XCTUnwrap(events.first?.spans.first)

        // Encode to JSON to trigger attribute encoding
        let jsonData = try JSONEncoder().encode(spanEvent)
        let jsonObject = try JSONSerialization.jsonObject(with: jsonData) as! [String: Any]

        // Span sent with only valid tag
        XCTAssertEqual(jsonObject["meta.valid_tag"] as? String, "test_value")
        XCTAssertNil(jsonObject["meta.onComplete"])
        XCTAssertNil(jsonObject["meta.callback"])
        XCTAssertNil(jsonObject["meta.custom_object"])

        // And all errors logged
        XCTAssertEqual(
            dd.logger.errorLogs.filter { $0.message.contains("Failed to encode attribute") }.count,
            3
        )
    }

    func testWhenOnlyMalformedSpanTagsAdded_itSendsSpanWithoutCustomTags() throws {
        // Given
        let dd = DD.mockWith(logger: CoreLoggerMock())
        defer { dd.reset() }

        let core = PassthroughCoreMock()
        let tracer: DatadogTracer = .mockWith(core: core)
        let span = tracer.startSpan(operationName: "test operation")

        // When
        span.setTag(key: "invalid_tag1", value: AnyEncodable(NSObject()))
        span.setTag(key: "invalid_tag2", value: AnyEncodable(NSObject()))
        span.finish()

        // Then
        let events: [SpanEventsEnvelope] = core.events()
        XCTAssertEqual(events.count, 1)

        let spanEvent = try XCTUnwrap(events.first?.spans.first)
        XCTAssertEqual(spanEvent.operationName, "test operation")

        // Encode to JSON
        let jsonData = try JSONEncoder().encode(spanEvent)
        let jsonObject = try JSONSerialization.jsonObject(with: jsonData) as! [String: Any]

        // Span still sent, just without custom tags
        XCTAssertNil(jsonObject["meta.invalid_tag1"])
        XCTAssertNil(jsonObject["meta.invalid_tag2"])

        // And errors logged
        XCTAssertEqual(
            dd.logger.errorLogs.filter { $0.message.contains("Failed to encode attribute") }.count,
            2
        )
    }
}
