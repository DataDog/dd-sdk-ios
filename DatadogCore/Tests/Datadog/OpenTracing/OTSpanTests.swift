/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import TestUtilities
@testable import DatadogTrace

private class MockSpan: OTSpan {
    var context: OTSpanContext = DDNoopGlobals.context
    func tracer() -> OTTracer { DDNoopGlobals.tracer }
    func setOperationName(_ operationName: String) {}
    func setTag(key: String, value: Encodable) {}
    func setBaggageItem(key: String, value: String) {}
    func baggageItem(withKey key: String) -> String? { nil }
    func setActive() -> OTSpan { self }
    func finish(at time: Date) {}

    var logs: [[String: Encodable]] = []

    func log(fields: [String: Encodable], timestamp: Date) {
        logs.append(fields)
    }
}

private extension Dictionary where Key == String, Value == Encodable {
    func otEvent() throws -> String {
        try XCTUnwrap(self[OTLogFields.event] as? String)
    }

    func otKind() throws -> String {
        try XCTUnwrap(self[OTLogFields.errorKind] as? String)
    }

    func otMessage() throws -> String {
        try XCTUnwrap(self[OTLogFields.message] as? String)
    }

    func otStack() throws -> String {
        try XCTUnwrap(self[OTLogFields.stack] as? String)
    }
}

class OTSpanTests: XCTestCase {
    #if os(iOS)
    private let testModuleName = "DatadogCoreTests_iOS"
    #elseif os(tvOS)
    private let testModuleName = "DatadogCoreTests_tvOS"
    #endif

    // MARK: - Test Error Conveniences

    func testWhenSettingErrorFromSwiftError_itLogsErrorFields() throws {
        // Given
        let span = MockSpan()

        // When
        #sourceLocation(file: "File.swift", line: 42)
        span.setError(ErrorMock("swift error description"))
        #sourceLocation()
        span.finish()

        // Then
        XCTAssertEqual(span.logs.count, 1)
        XCTAssertEqual(span.logs[0].count, 4)
        XCTAssertEqual(try span.logs[0].otEvent(), "error")
        XCTAssertEqual(try span.logs[0].otKind(), "ErrorMock")
        XCTAssertEqual(try span.logs[0].otMessage(), "swift error description")
        XCTAssertEqual(
            try span.logs[0].otStack(),
            """
            \(testModuleName)/File.swift:42
            swift error description
            """
        )
    }

    func testWhenSettingErrorFromSwiftErrorWithFileAndLine_itLogsErrorFields() throws {
        // Given
        let span = MockSpan()

        // When
        span.setError(ErrorMock("swift error description"), file: "File.swift", line: 42)

        // Then
        XCTAssertEqual(span.logs.count, 1)
        XCTAssertEqual(span.logs[0].count, 4)
        XCTAssertEqual(try span.logs[0].otEvent(), "error")
        XCTAssertEqual(try span.logs[0].otKind(), "ErrorMock")
        XCTAssertEqual(try span.logs[0].otMessage(), "swift error description")
        XCTAssertEqual(
            try span.logs[0].otStack(),
            """
            File.swift:42
            swift error description
            """
        )
    }

    func testWhenSettingErrorFromNSError_itLogsErrorFields() throws {
        // Given
        let span = MockSpan()

        // When
        #sourceLocation(file: "File.swift", line: 42)
        span.setError(
            NSError(
                domain: "DDSpan",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "ns error description"]
            )
        )
        #sourceLocation()

        // Then
        XCTAssertEqual(span.logs.count, 1)
        XCTAssertEqual(span.logs[0].count, 4)
        XCTAssertEqual(try span.logs[0].otEvent(), "error")
        XCTAssertEqual(try span.logs[0].otKind(), "DDSpan - 1")
        XCTAssertEqual(try span.logs[0].otMessage(), "ns error description")
        XCTAssertEqual(
            try span.logs[0].otStack(),
            """
            \(testModuleName)/File.swift:42
            Error Domain=DDSpan Code=1 "ns error description" UserInfo={NSLocalizedDescription=ns error description}
            """
        )
    }

    func testWhenSettingErrorFromArguments_itLogsErrorFields() throws {
        // Given
        let span = MockSpan()

        // When
        #sourceLocation(file: "File.swift", line: 42)
        span.setError(kind: "custom kind", message: "DDSpan Error")
        #sourceLocation()

        // Then
        XCTAssertEqual(span.logs.count, 1)
        XCTAssertEqual(span.logs[0].count, 4)
        XCTAssertEqual(try span.logs[0].otEvent(), "error")
        XCTAssertEqual(try span.logs[0].otKind(), "custom kind")
        XCTAssertEqual(try span.logs[0].otMessage(), "DDSpan Error")
        XCTAssertEqual(
            try span.logs[0].otStack(),
            """
            \(testModuleName)/File.swift:42
            """
        )
    }

    func testWhenSettingErrorFromArgumentsWithStack_itLogsErrorFields() throws {
        // Given
        let span = MockSpan()

        // When
        let stack = """
        Thread 0 Crashed:
        0   app                                 0x0000000102bc0d8c 0x102bb8000 + 36236
        1   UIKitCore                           0x00000001b513d9ac 0x1b4739000 + 10504620
        """
        #sourceLocation(file: "File.swift", line: 42)
        span.setError(kind: "custom kind", message: "custom message", stack: stack)
        #sourceLocation()

        // Then
        XCTAssertEqual(span.logs.count, 1)
        XCTAssertEqual(span.logs[0].count, 4)
        XCTAssertEqual(try span.logs[0].otEvent(), "error")
        XCTAssertEqual(try span.logs[0].otKind(), "custom kind")
        XCTAssertEqual(try span.logs[0].otMessage(), "custom message")
        XCTAssertEqual(
            try span.logs[0].otStack(),
            """
            \(testModuleName)/File.swift:42
            Thread 0 Crashed:
            0   app                                 0x0000000102bc0d8c 0x102bb8000 + 36236
            1   UIKitCore                           0x00000001b513d9ac 0x1b4739000 + 10504620
            """
        )
    }

    func testWhenSettingErrorFromArgumentsWithFileAndLine_itLogsErrorFields() throws {
        // Given
        let span = MockSpan()

        // When
        span.setError(kind: "custom kind", message: "custom message", file: "File.swift", line: 42)

        // Then
        XCTAssertEqual(span.logs.count, 1)
        XCTAssertEqual(span.logs[0].count, 4)
        XCTAssertEqual(try span.logs[0].otEvent(), "error")
        XCTAssertEqual(try span.logs[0].otKind(), "custom kind")
        XCTAssertEqual(try span.logs[0].otMessage(), "custom message")
        XCTAssertEqual(
            try span.logs[0].otStack(),
            """
            File.swift:42
            """
        )
    }

    func testWhenSettingErrorWithEmptyFileLineAndStack_itLogsErrorFields() throws {
        // Given
        let span = MockSpan()

        // When
        span.setError(ErrorMock("swift error description"), file: "", line: 0)

        // Then
        XCTAssertEqual(span.logs.count, 1)
        XCTAssertEqual(span.logs[0].count, 4)
        XCTAssertEqual(try span.logs[0].otEvent(), "error")
        XCTAssertEqual(try span.logs[0].otKind(), "ErrorMock")
        XCTAssertEqual(try span.logs[0].otMessage(), "swift error description")
        XCTAssertEqual(
            try span.logs[0].otStack(),
            """
            swift error description
            """
        )
    }

    func testWhenSettingErrorWithEmptyFileLineAndNonEmptyStack_itLogsErrorFields() throws {
        // Given
        let span = MockSpan()

        // When
        span.setError(ErrorMock("the stack"), file: "", line: 0)

        // Then
        XCTAssertEqual(span.logs.count, 1)
        XCTAssertEqual(span.logs[0].count, 4)
        XCTAssertEqual(try span.logs[0].otEvent(), "error")
        XCTAssertEqual(try span.logs[0].otKind(), "ErrorMock")
        XCTAssertEqual(try span.logs[0].otMessage(), "the stack")
        XCTAssertEqual(
            try span.logs[0].otStack(),
            """
            the stack
            """
        )
    }
}
