/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import XCTest
@testable import Datadog

fileprivate extension Dictionary where Key == String, Value == Encodable {
    func otEvent() throws -> String {
        try XCTUnwrap(self[OTLogFields.event] as? String)
    }

    func otMessage() throws -> String {
        try XCTUnwrap(self[OTLogFields.message] as? String)
    }

    func otStack() throws -> String {
        try XCTUnwrap(self[OTLogFields.stack] as? String)
    }
}

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

    // MARK: - Errors

    func testSettingErrorFromSwiftError() throws {
        let span: DDSpan = .mockWith(operationName: "operation")
        XCTAssertEqual(span.logFields.count, 0)

        #sourceLocation(file: "File.swift", line: 42)
        span.setError(ErrorMock())
        #sourceLocation()

        XCTAssertEqual(span.logFields.count, 1)
        let logFields = span.logFields.first!
        XCTAssertNotEqual(logFields.count, 0)
        try XCTAssertEqual(logFields.otEvent(), "error")
        let spanErrorStack = try logFields.otStack()
        XCTAssertTrue(spanErrorStack.contains("File.swift"))
        XCTAssertTrue(spanErrorStack.contains("42"))
    }

    func testSettingErrorFromSwiftErrorWithFileAndLine() throws {
        let span: DDSpan = .mockWith(operationName: "operation")
        XCTAssertEqual(span.logFields.count, 0)

        span.setError(ErrorMock(), file: "File.swift", line: 42)

        XCTAssertEqual(span.logFields.count, 1)
        let spanErrorStack = try span.logFields.first!.otStack()
        XCTAssertTrue(spanErrorStack.contains("File.swift"))
        XCTAssertTrue(spanErrorStack.contains("42"))
    }

    func testSettingErrorFromNSError() throws {
        let span: DDSpan = .mockWith(operationName: "operation")
        XCTAssertEqual(span.logFields.count, 0)

        #sourceLocation(file: "File.swift", line: 42)
        span.setError(
            NSError(
                domain: "DDSpan",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "some error description"]
            )
        )
        #sourceLocation()

        XCTAssertEqual(span.logFields.count, 1)
        let logFields = span.logFields.first!
        XCTAssertNotEqual(logFields.count, 0)
        try XCTAssertEqual(logFields.otEvent(), "error")
        let spanErrorMessage = try logFields.otMessage()
        let spanErrorStack = try logFields.otStack()
        XCTAssertTrue(spanErrorMessage.contains("some error description"))
        XCTAssertTrue(spanErrorStack.contains("DDSpan"))
        XCTAssertTrue(spanErrorStack.contains("File.swift"))
        XCTAssertTrue(spanErrorStack.contains("42"))
    }

    func testSettingErrorFromArguments() throws {
        let span: DDSpan = .mockWith(operationName: "operation")
        XCTAssertEqual(span.logFields.count, 0)

        #sourceLocation(file: "File.swift", line: 42)
        span.setError(kind: .mockAny(), message: "DDSpan Error")
        #sourceLocation()

        XCTAssertEqual(span.logFields.count, 1)
        let logFields = span.logFields.first!
        XCTAssertNotEqual(logFields.count, 0)
        try XCTAssertEqual(logFields.otEvent(), "error")
        let spanErrorMessage = try logFields.otMessage()
        let spanErrorStack = try logFields.otStack()
        XCTAssertTrue(spanErrorMessage.contains("DDSpan Error"))
        XCTAssertTrue(spanErrorStack.contains("File.swift"))
        XCTAssertTrue(spanErrorStack.contains("42"))
    }

    func testSettingErrorFromArgumentsWithStack() throws {
        let span: DDSpan = .mockWith(operationName: "operation")

        let stack = """
        Thread 0 Crashed:
        0   app                                 0x0000000102bc0d8c 0x102bb8000 + 36236
        1   UIKitCore                           0x00000001b513d9ac 0x1b4739000 + 10504620
        """
        span.setError(kind: .mockAny(), message: .mockAny(), stack: stack)

        XCTAssertEqual(span.logFields.count, 1)
        let spanErrorStack = try span.logFields.first!.otStack()
        XCTAssertTrue(spanErrorStack.contains(stack))
    }

    func testSettingErrorFromArgumentsWithFileAndLine() throws {
        let span: DDSpan = .mockWith(operationName: "operation")
        span.setError(kind: .mockAny(), message: .mockAny(), file: "File.swift", line: 42)

        XCTAssertEqual(span.logFields.count, 1)
        let spanErrorStack = try span.logFields.first!.otStack()
        XCTAssertTrue(spanErrorStack.contains("File.swift"))
        XCTAssertTrue(spanErrorStack.contains("42"))
    }

    func testSettingErrorWithEmptyFileLineAndStack() throws {
        let span: DDSpan = .mockWith(operationName: "operation")
        XCTAssertEqual(span.logFields.count, 0)

        span.setError(ErrorMock(), file: "", line: 0)

        XCTAssertEqual(span.logFields.count, 1)
        let logFields = span.logFields.first!
        XCTAssertNotEqual(logFields.count, 0)
        XCTAssertNil(logFields[OTLogFields.stack])
    }

    func testSettingErrorWithEmptyFileLineAndNonEmptyStack() throws {
        let span: DDSpan = .mockWith(operationName: "operation")
        XCTAssertEqual(span.logFields.count, 0)

        span.setError(ErrorMock("the stack"), file: "", line: 0)

        XCTAssertEqual(span.logFields.count, 1)
        let logFields = span.logFields.first!
        XCTAssertNotEqual(logFields.count, 0)
        let spanErrorStack = try span.logFields.first!.otStack()
        XCTAssertFalse(spanErrorStack.contains("File.swift"))
        XCTAssertFalse(spanErrorStack.contains("42"))
        XCTAssertTrue(spanErrorStack.contains("the stack"))
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
            XCTAssertEqual(output.recordedLog?.status, .warn)
            XCTAssertEqual(output.recordedLog?.message, expectedConsoleWarning)
        }
    }
}
