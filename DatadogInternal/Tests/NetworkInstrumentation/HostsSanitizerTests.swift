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
        let printFunction = PrintFunctionMock()
        consolePrint = printFunction.print
        defer { consolePrint = { print($0) } }

        // When
        let hosts: Set<String> = [
            "https://first-party.com", // sanitize to → "first-party.com"
            "http://api.first-party.com", // sanitize to → "api.first-party.com"
            "https://first-party.com/v2/api", // sanitize to → "first-party.com"
            "https://192.168.0.1/api", // sanitize to → "192.168.0.1"
            "https://192.168.0.2", // sanitize to → "192.168.0.2"
            "invalid-host-name", // drop
            "192.168.0.3:8080", // drop
            "", // drop
            "localhost", // accept
            "192.168.0.4", // accept
            "valid-host-name.com", // accept
        ]

        // Then
        let sanitizer = HostsSanitizer()
        let sanitizedHosts = sanitizer.sanitized(hosts: hosts, warningMessage: "Host is not valid")

        XCTAssertEqual(
            sanitizedHosts,
            [
                "first-party.com",
                "api.first-party.com",
                "localhost",
                "192.168.0.1",
                "192.168.0.2",
                "localhost",
                "192.168.0.4",
                "valid-host-name.com"
            ]
        )

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
            printFunction.printedMessages.contains("⚠️ Host is not valid: 'invalid-host-name' is not a valid host name and will be dropped.")
        )
        XCTAssertTrue(
            printFunction.printedMessages.contains("⚠️ Host is not valid: 'https://192.168.0.2' is an url and will be sanitized to: '192.168.0.2'.")
        )
        XCTAssertEqual(printFunction.printedMessages.count, 8)
    }
}
