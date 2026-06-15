/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import TestUtilities
@testable import DatadogInternal

class HostPatternSanitizerTests: XCTestCase {
    func testSanitizationAndWarningMessages() throws {
        let printFunction = PrintFunctionSpy()
        consolePrint = printFunction.print
        defer { consolePrint = { message, _ in print(message) } }

        let patterns: [String: Set<TracingHeaderType>] = [
            "*.example.com": [.datadog],
            "preview-*.shopist.io": [.tracecontext],
            "*.UPPER.COM": [.datadog],
            "*.invalid_pattern.com": [.datadog],
            "*.foo.*.bar.com": [.datadog],
            "": [.datadog],
        ]

        let sanitized = sanitizeHostPatterns(patterns, warningMessage: "Pattern not valid")

        XCTAssertEqual(sanitized["*.example.com"], [.datadog])
        XCTAssertEqual(sanitized["preview-*.shopist.io"], [.tracecontext])
        XCTAssertEqual(sanitized["*.upper.com"], [.datadog])
        XCTAssertNil(sanitized["*.UPPER.COM"])
        XCTAssertNil(sanitized["*.invalid_pattern.com"])
        XCTAssertNil(sanitized["*.foo.*.bar.com"])
        XCTAssertNil(sanitized[""])
        XCTAssertEqual(sanitized.count, 3)

        XCTAssertEqual(printFunction.printedMessages.count, 3)
        XCTAssertTrue(printFunction.printedMessages.contains(
            "⚠️ Pattern not valid: '*.invalid_pattern.com' is not a valid host pattern and will be dropped."
        ))
        XCTAssertTrue(printFunction.printedMessages.contains(
            "⚠️ Pattern not valid: '*.foo.*.bar.com' is not a valid host pattern and will be dropped."
        ))
        XCTAssertTrue(printFunction.printedMessages.contains(
            "⚠️ Pattern not valid: '' is not a valid host name and will be dropped."
        ))
    }

    func testPlainHostAsPattern_isAccepted() {
        let sanitized = sanitizeHostPatterns(["example.com": [.datadog]], warningMessage: "")
        XCTAssertEqual(sanitized["example.com"], [.datadog])
    }

    func testBareWildcard_isDropped() {
        let printFunction = PrintFunctionSpy()
        consolePrint = printFunction.print
        defer { consolePrint = { message, _ in print(message) } }

        let sanitized = sanitizeHostPatterns(["*": [.datadog]], warningMessage: "Pattern not valid")

        XCTAssertNil(sanitized["*"])
        XCTAssertEqual(sanitized.count, 0)
        XCTAssertEqual(printFunction.printedMessages.count, 1)
        XCTAssertTrue(printFunction.printedMessages.contains(
            "⚠️ Pattern not valid: '*' is not a valid host pattern and will be dropped."
        ))
    }
}
