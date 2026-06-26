/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import TestUtilities
@testable import DatadogInternal

class HostsSanitizerTests: XCTestCase {
    func testSanitizationAndWarningMessages() throws {
        let printFunction = PrintFunctionSpy()
        consolePrint = printFunction.print
        defer { consolePrint = { message, _ in print(message) } }

        // When
        let hosts: Set<String> = [
            "https://first-party.com", // sanitize to → "first-party.com"
            "http://api.first-party.com", // sanitize to → "api.first-party.com"
            "https://first-party.com/v2/api", // sanitize to → "first-party.com"
            "https://192.168.0.1/api", // sanitize to → "192.168.0.1"
            "https://192.168.0.2", // sanitize to → "192.168.0.2"
            "invalid_host_name", // drop
            "192.168.0.3:8080", // drop
            "", // drop
            "localhost", // accept
            "192.168.0.4", // accept
            "valid-host-name.com", // accept
            "customprotocol://name" // accept
        ]

        // Then
        let sanitizer = HostsSanitizer()
        let sanitizedHosts = sanitizer.sanitized(hosts: hosts, warningMessage: "Host is not valid")

        XCTAssertEqual(sanitizedHosts.count, 8)
        XCTAssertTrue(sanitizedHosts.contains("first-party.com"))
        XCTAssertTrue(sanitizedHosts.contains("api.first-party.com"))
        XCTAssertTrue(sanitizedHosts.contains("192.168.0.1"))
        XCTAssertTrue(sanitizedHosts.contains("192.168.0.2"))
        XCTAssertTrue(sanitizedHosts.contains("localhost"))
        XCTAssertTrue(sanitizedHosts.contains("192.168.0.4"))
        XCTAssertTrue(sanitizedHosts.contains("valid-host-name.com"))
        XCTAssertTrue(sanitizedHosts.contains("name"))

        XCTAssertEqual(printFunction.printedMessages.count, 9)

        XCTAssertTrue(
            printFunction.printedMessages.contains("⚠️ Host is not valid: '192.168.0.3:8080' is not a valid host name and will be dropped.")
        )
        XCTAssertTrue(
            printFunction.printedMessages.contains("⚠️ Host is not valid: '' is not a valid host name and will be dropped.")
        )
        XCTAssertTrue(
            printFunction.printedMessages.contains("⚠️ Host is not valid: 'https://first-party.com' is an url and will be sanitized to: 'first-party.com'.")
        )
        XCTAssertTrue(
            printFunction.printedMessages.contains("⚠️ Host is not valid: 'https://192.168.0.1/api' is an url and will be sanitized to: '192.168.0.1'.")
        )
        XCTAssertTrue(
            printFunction.printedMessages.contains("⚠️ Host is not valid: 'http://api.first-party.com' is an url and will be sanitized to: 'api.first-party.com'.")
        )
        XCTAssertTrue(
            printFunction.printedMessages.contains("⚠️ Host is not valid: 'https://first-party.com/v2/api' is an url and will be sanitized to: 'first-party.com'.")
        )
        XCTAssertTrue(
            printFunction.printedMessages.contains("⚠️ Host is not valid: 'invalid_host_name' is not a valid host name and will be dropped.")
        )
        XCTAssertTrue(
            printFunction.printedMessages.contains("⚠️ Host is not valid: 'https://192.168.0.2' is an url and will be sanitized to: '192.168.0.2'.")
        )
        XCTAssertTrue(
            printFunction.printedMessages.contains("⚠️ Host is not valid: 'customprotocol://name' is an url and will be sanitized to: 'name'.")
        )
    }

    // MARK: - Wildcard pattern sanitization

    func testWildcardSanitizationAndWarningMessages() throws {
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

        let sanitizer = HostsSanitizer()
        let sanitized = sanitizer.sanitized(hostsWithTracingHeaderTypes: patterns, warningMessage: "Pattern not valid")

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

    func testWildcardPlainHostAsPattern_isAccepted() {
        let sanitizer = HostsSanitizer()
        let sanitized = sanitizer.sanitized(hostsWithTracingHeaderTypes: ["example.com": [.datadog]], warningMessage: "")
        XCTAssertEqual(sanitized["example.com"], [.datadog])
    }

    func testWildcardTrailingDotPattern_isDropped() {
        let sanitizer = HostsSanitizer()
        let sanitized = sanitizer.sanitized(hostsWithTracingHeaderTypes: ["*.": [.datadog]], warningMessage: "")
        XCTAssertNil(sanitized["*."])
        XCTAssertEqual(sanitized.count, 0)
    }

    func testWildcardBareWildcard_isDropped() {
        let printFunction = PrintFunctionSpy()
        consolePrint = printFunction.print
        defer { consolePrint = { message, _ in print(message) } }

        let sanitizer = HostsSanitizer()
        let sanitized = sanitizer.sanitized(hostsWithTracingHeaderTypes: ["*": [.datadog]], warningMessage: "Pattern not valid")

        XCTAssertNil(sanitized["*"])
        XCTAssertEqual(sanitized.count, 0)
        XCTAssertEqual(printFunction.printedMessages.count, 1)
        XCTAssertTrue(printFunction.printedMessages.contains(
            "⚠️ Pattern not valid: '*' is not a valid host pattern and will be dropped."
        ))
    }

    func testWildcardWithoutLabelBoundary_isDropped() {
        let printFunction = PrintFunctionSpy()
        consolePrint = printFunction.print
        defer { consolePrint = { message, _ in print(message) } }

        let sanitizer = HostsSanitizer()
        let sanitized = sanitizer.sanitized(
            hostsWithTracingHeaderTypes: ["*example.com": [.datadog]],
            warningMessage: "Pattern not valid"
        )

        XCTAssertNil(sanitized["*example.com"])
        XCTAssertEqual(sanitized.count, 0)
        XCTAssertEqual(printFunction.printedMessages.count, 1)
        XCTAssertTrue(printFunction.printedMessages.contains(
            "⚠️ Pattern not valid: '*example.com' is not a valid host pattern and will be dropped."
        ))
    }

    func testWildcardHosts_setOverload_isAccepted() {
        let sanitizer = HostsSanitizer()
        let sanitized = sanitizer.sanitized(hosts: ["*.example.com", "preview-*.shopist.io"], warningMessage: "")
        XCTAssertTrue(sanitized.contains("*.example.com"))
        XCTAssertTrue(sanitized.contains("preview-*.shopist.io"))
    }
}
