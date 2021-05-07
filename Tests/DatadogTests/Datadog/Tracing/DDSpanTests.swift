/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import XCTest
@testable import Datadog

class DDSpanTests: XCTestCase {
    private let spanOutput = SpanOutputMock()
    private let logOutput = LogOutputMock()
    private lazy var mockTracer: Tracer = .mockWith(
        spanOutput: spanOutput,
        logOutput: .init(logBuilder: .mockAny(), loggingOutput: logOutput)
    )

    // MARK: - Sending SpanEvent

    func testWhenSpanIsFinished_itWritesSpanEventToSpanOutput() throws {
        let writeSpansExpectation = expectation(description: "write span event")
        spanOutput.onSpanRecorded = { _ in writeSpansExpectation.fulfill() }

        // Given
        let span: DDSpan = .mockWith(tracer: mockTracer)

        // When
        span.finish()

        // Then
        waitForExpectations(timeout: 0.5, handler: nil)
    }

    // MARK: - Sending Span Logs

    func testWhenLoggingSpanEvent_itWritesLogToLogOutput() throws {
        let writeSpanLogsExpectation = expectation(description: "write 2 logs")
        writeSpanLogsExpectation.expectedFulfillmentCount = 2
        logOutput.onLogRecorded  = { _ in writeSpanLogsExpectation.fulfill() }

        // Given
        let span: DDSpan = .mockWith(tracer: mockTracer)

        // When
        let log1Fields = mockRandomAttributes()
        span.log(fields: log1Fields)

        let log2Fields = mockRandomAttributes()
        span.log(fields: log2Fields)

        // Then
        waitForExpectations(timeout: 0.5, handler: nil)
        XCTAssertEqual(logOutput.allRecordedLogs.count, 2)
        let log1 = try XCTUnwrap(logOutput.allRecordedLogs[0])
        let log2 = try XCTUnwrap(logOutput.allRecordedLogs[1])
        AssertDictionariesEqual(log1.attributes.userAttributes, log1Fields)
        AssertDictionariesEqual(log2.attributes.userAttributes, log2Fields)
    }

    // MARK: - Customizing SpanEvents

    func testWhenSettingCustomOperationName_itOverwritesOriginalName() {
        let writeSpansExpectation = expectation(description: "write 2 span events")
        writeSpansExpectation.expectedFulfillmentCount = 2
        spanOutput.onSpanRecorded = { _ in writeSpansExpectation.fulfill() }

        // Given
        let defaultOperationName: String = .mockRandom()
        let defaultSpan: DDSpan = .mockWith(tracer: mockTracer, operationName: defaultOperationName)
        let customizedSpan: DDSpan = .mockWith(tracer: mockTracer, operationName: defaultOperationName)

        // When
        let customizedOperationName: String = .mockRandom()
        customizedSpan.setOperationName(customizedOperationName)

        // Then
        defaultSpan.finish()
        customizedSpan.finish()

        waitForExpectations(timeout: 0.5, handler: nil)
        XCTAssertEqual(spanOutput.allRecordedSpans.count, 2)
        XCTAssertEqual(spanOutput.allRecordedSpans[0].operationName, defaultOperationName)
        XCTAssertEqual(spanOutput.allRecordedSpans[1].operationName, customizedOperationName)
    }

    func testWhenSettingCustomTags_theyAreMergedWithDefaultTags() {
        let writeSpansExpectation = expectation(description: "write 2 span events")
        writeSpansExpectation.expectedFulfillmentCount = 2
        spanOutput.onSpanRecorded = { _ in writeSpansExpectation.fulfill() }

        // Given
        let defaultTags: [String: String] = .mockRandom()
        let defaultSpan: DDSpan = .mockWith(tracer: mockTracer, tags: defaultTags)
        let customizedSpan: DDSpan = .mockWith(tracer: mockTracer, tags: defaultTags)

        // When
        let customTags: [String: String] = .mockRandom()
        customTags.forEach { tagKey, tagValue in
            customizedSpan.setTag(key: tagKey, value: tagValue)
        }

        // Then
        defaultSpan.finish()
        customizedSpan.finish()

        waitForExpectations(timeout: 0.5, handler: nil)
        XCTAssertEqual(spanOutput.allRecordedSpans.count, 2)
        XCTAssertEqual(spanOutput.allRecordedSpans[0].tags, defaultTags)
        XCTAssertEqual(spanOutput.allRecordedSpans[1].tags, defaultTags.merging(customTags) { _, custom in custom })
    }

    func testSettingBaggageItems() {
        let queue = DispatchQueue(label: "com.datadoghq.\(#function)")

        // Given
        let span: DDSpan = .mockWith(
            context: .mockWith(baggageItems: BaggageItems(targetQueue: queue, parentSpanItems: nil))
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

    func testSpanCanBeSafelyAccessedFromDifferentThreads() {
        let writeSpansExpectation = expectation(description: "write span event")
        spanOutput.onSpanRecorded = { _ in writeSpansExpectation.fulfill() }

        // Given
        let span: DDSpan = .mockWith(tracer: mockTracer)

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
        XCTAssertEqual(spanOutput.allRecordedSpans.count, 1)
        XCTAssertEqual(spanOutput.allRecordedSpans[0].tags.count, 200, "It should contain 200 tags (100 explicit tags + 100 baggage items as tags)")
    }

    // MARK: - Usage

    func testGivenFinishedSpan_whenCallingItsAPI_itPrintsErrors() {
        let previousUserLogger = userLogger
        defer { userLogger = previousUserLogger }

        let output = LogOutputMock()
        userLogger = .mockWith(logOutput: output)

        let span: DDSpan = .mockWith(operationName: "the span")
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
            XCTAssertEqual(output.recordedLog?.status, .warn)
            XCTAssertEqual(output.recordedLog?.message, expectedConsoleWarning)
        }
    }
}
