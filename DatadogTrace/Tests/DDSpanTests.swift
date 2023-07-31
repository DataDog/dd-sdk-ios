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
        let core = PassthroughCoreMock(expectation: writeSpansExpectation)

        // Given
        let tracer: DatadogTracer = .mockWith(core: core)
        let span: DDSpan = .mockWith(tracer: tracer)

        // When
        span.finish()

        // Then
        waitForExpectations(timeout: 0.5, handler: nil)
    }

    // MARK: - Customizing SpanEvents

    func testWhenSettingCustomOperationName_itOverwritesOriginalName() throws {
        let writeSpansExpectation = expectation(description: "write 2 span events")
        writeSpansExpectation.expectedFulfillmentCount = 2
        let core = PassthroughCoreMock(expectation: writeSpansExpectation)

        // Given
        let defaultOperationName: String = .mockRandom()
        let tracer: DatadogTracer = .mockWith(core: core)
        let defaultSpan: DDSpan = .mockWith(tracer: tracer, operationName: defaultOperationName)
        let customizedSpan: DDSpan = .mockWith(tracer: tracer, operationName: defaultOperationName)

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
        let core = PassthroughCoreMock(expectation: writeSpansExpectation)

        // Given
        let defaultTags: [String: String] = .mockRandom()
        let tracer: DatadogTracer = .mockWith(core: core)
        let defaultSpan: DDSpan = .mockWith(tracer: tracer, tags: defaultTags)
        let customizedSpan: DDSpan = .mockWith(tracer: tracer, tags: defaultTags)

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
        let core = PassthroughCoreMock(expectation: writeSpansExpectation)

        // Given
        let tracer: DatadogTracer = .mockWith(core: core)
        let span: DDSpan = .mockWith(tracer: tracer)

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
        let span: DDSpan = .mockWith(
            tracer: .mockWith(core: core),
            operationName: "the span"
        )
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
            span.tracer().dd.queue.sync {} // wait synchronizing span's internal state
            XCTAssertEqual(dd.logger.warnLog?.message, expectedConsoleWarning)
        }
    }
}
