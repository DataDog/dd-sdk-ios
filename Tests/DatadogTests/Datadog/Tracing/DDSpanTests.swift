/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import XCTest
@testable import Datadog

class DDSpanTests: XCTestCase {
    func testOverwritingOperationName() {
        let span: DDSpan = .mockWith(operationName: "initial")
        span.setOperationName("new")
        XCTAssertEqual(span.operationName, "new")
    }

    // MARK: - Tags

    func testSettingTag() {
        let span: DDSpan = .mockWith(operationName: "operation")
        XCTAssertEqual(span.tags.count, 0)

        span.setTag(key: "key1", value: "value1")
        span.setTag(key: "key2", value: "value2")

        XCTAssertEqual(span.tags.count, 2)
        XCTAssertEqual(span.tags["key1"] as? String, "value1")
        XCTAssertEqual(span.tags["key2"] as? String, "value2")
    }

    // MARK: - Baggage Items

    func testSettingBaggageItems() {
        let queue = DispatchQueue(label: "com.datadoghq.\(#function)")
        let span: DDSpan = .mockWith(
            context: .mockWith(baggageItems: BaggageItems(targetQueue: queue, parentSpanItems: nil))
        )

        XCTAssertEqual(span.ddContext.baggageItems.all, [:])

        span.setBaggageItem(key: "foo", value: "bar")
        span.setBaggageItem(key: "bizz", value: "buzz")

        XCTAssertEqual(span.baggageItem(withKey: "foo"), "bar")
        XCTAssertEqual(span.baggageItem(withKey: "bizz"), "buzz")
        XCTAssertEqual(span.ddContext.baggageItems.all, ["foo": "bar", "bizz": "buzz"])
    }

    // MARK: - Usage

    func testGivenFinishedSpan_whenCallingItsAPI_itPrintsErrors() {
        let previousUserLogger = userLogger
        defer { userLogger = previousUserLogger }

        let output = LogOutputMock()
        userLogger = Logger(logOutput: output, dateProvider: SystemDateProvider(), identifier: "sdk-user")

        let span: DDSpan = .mockWith(operationName: "the span")
        span.finish()

        let fixtures: [(() -> Void, String)] = [
            ({ _ = span.setOperationName(.mockAny()) },
            "🔥 Calling `setOperationName(_:)` on a finished span (\"the span\") is not allowed."),
            ({ _ = span.setTag(key: .mockAny(), value: 0) },
            "🔥 Calling `setTag(key:value:)` on a finished span (\"the span\") is not allowed."),
            ({ _ = span.setBaggageItem(key: .mockAny(), value: .mockAny()) },
            "🔥 Calling `setBaggageItem(key:value:)` on a finished span (\"the span\") is not allowed."),
            ({ _ = span.baggageItem(withKey: .mockAny()) },
            "🔥 Calling `baggageItem(withKey:)` on a finished span (\"the span\") is not allowed."),
            ({ _ = span.finish(at: .mockAny()) },
            "🔥 Calling `finish(at:)` on a finished span (\"the span\") is not allowed."),
            ({ _ = span.log(fields: [:], timestamp: .mockAny()) },
            "🔥 Calling `log(fields:timestamp:)` on a finished span (\"the span\") is not allowed."),
        ]

        fixtures.forEach { tracerMethod, expectedConsoleWarning in
            tracerMethod()
            XCTAssertEqual(output.recordedLog?.level, .warn)
            XCTAssertEqual(output.recordedLog?.message, expectedConsoleWarning)
        }
    }
}
