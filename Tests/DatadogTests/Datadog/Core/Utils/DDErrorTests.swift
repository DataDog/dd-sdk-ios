/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import XCTest
@testable import Datadog

class DDErrorTests: XCTestCase {
    func testFormattingBasicSwiftError() {
        struct SwiftError: Error {
            let description = "error description"
        }

        let error = SwiftError()
        let dderror = DDError(error: error)

        XCTAssertEqual(dderror.title, "SwiftError")
        XCTAssertEqual(dderror.message, #"SwiftError(description: "error description")"#)
        XCTAssertEqual(dderror.details, #"description: error description"#)
    }

    func testFormattingStringConvertibleSwiftError() {
        struct SwiftError: Error, CustomDebugStringConvertible {
            let debugDescription = "error description"
        }

        let error = SwiftError()
        let dderror = DDError(error: error)

        XCTAssertEqual(dderror.title, "SwiftError")
        XCTAssertEqual(dderror.message, "error description")
        XCTAssertEqual(dderror.details, "debugDescription: error description")
    }

    // NOTE: RUMM-817 When nested in method,
    // ddError.title contains "unknown context at $110014ea8"
    class SwiftErrorClass: Error {
        let someProperty = "some value"
    }
    func testFormattingErrorClass() {
        let error = SwiftErrorClass()
        let dderror = DDError(error: error)

        XCTAssertEqual(dderror.title, "SwiftErrorClass")
        XCTAssertEqual(dderror.message, "DatadogTests.DDErrorTests.SwiftErrorClass")
        XCTAssertEqual(dderror.details, "someProperty: some value")
    }

    func testFormattingNSError() {
        let error = NSError(
            domain: "custom-domain",
            code: 10,
            userInfo: [
                NSLocalizedDescriptionKey: "error description"
            ]
        )
        let dderror = DDError(error: error)

        XCTAssertEqual(dderror.title, "custom-domain - 10")
        XCTAssertEqual(dderror.message, "error description")
        XCTAssertEqual(
            dderror.details,
            """
            Error Domain=custom-domain Code=10 "error description" UserInfo={NSLocalizedDescription=error description}
            """
        )
    }

    func testFormattingNSErrorSubclass() {
        class NSErrorSubclass: NSError {}

        let dderrorWithDescription = DDError(
            error: NSErrorSubclass(
                domain: "custom-domain",
                code: 10,
                userInfo: [NSLocalizedDescriptionKey: "localized description"]
            )
        )

        XCTAssertEqual(dderrorWithDescription.title, "custom-domain - 10")
        XCTAssertEqual(dderrorWithDescription.message, "localized description")
        XCTAssertEqual(
            dderrorWithDescription.details,
            """
            Error Domain=custom-domain Code=10 "localized description" UserInfo={NSLocalizedDescription=localized description}
            """
        )

        let dderrorNoDescription = DDError(
            error: NSErrorSubclass(
                domain: "custom-domain",
                code: 10,
                userInfo: [:]
            )
        )

        XCTAssertEqual(dderrorNoDescription.title, "custom-domain - 10")
        XCTAssertEqual(
            dderrorNoDescription.message,
            #"Error Domain=custom-domain Code=10 "(null)""#
        )
        XCTAssertEqual(
            dderrorNoDescription.details,
            #"Error Domain=custom-domain Code=10 "(null)""#
        )
    }
}
