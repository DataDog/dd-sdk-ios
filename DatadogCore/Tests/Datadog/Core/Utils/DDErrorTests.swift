/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import DatadogInternal
@testable import DatadogCore

class DDErrorTests: XCTestCase {
    func testFormattingBasicSwiftError() {
        struct SwiftError: Error {
            let description = "error description"
        }

        let error = SwiftError()
        let dderror = DDError(error: error)

        XCTAssertEqual(dderror.type, "SwiftError")
        XCTAssertEqual(dderror.message, #"SwiftError(description: "error description")"#)
        XCTAssertEqual(dderror.stack, #"SwiftError(description: "error description")"#)
    }

    func testFormattingStringConvertibleSwiftError() {
        struct SwiftError: Error, CustomDebugStringConvertible {
            let debugDescription = "error description"
        }

        let error = SwiftError()
        let dderror = DDError(error: error)

        XCTAssertEqual(dderror.type, "SwiftError")
        XCTAssertEqual(dderror.message, "error description")
        XCTAssertEqual(dderror.stack, "error description")
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

        XCTAssertEqual(dderror.type, "custom-domain - 10")
        XCTAssertEqual(dderror.message, "error description")
        XCTAssertEqual(
            dderror.stack,
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

        XCTAssertEqual(dderrorWithDescription.type, "custom-domain - 10")
        XCTAssertEqual(dderrorWithDescription.message, "localized description")
        XCTAssertEqual(
            dderrorWithDescription.stack,
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

        XCTAssertEqual(dderrorNoDescription.type, "custom-domain - 10")
        XCTAssertEqual(
            dderrorNoDescription.message,
            #"Error Domain=custom-domain Code=10 "(null)""#
        )
        XCTAssertEqual(
            dderrorNoDescription.stack,
            #"Error Domain=custom-domain Code=10 "(null)""#
        )
    }
}
