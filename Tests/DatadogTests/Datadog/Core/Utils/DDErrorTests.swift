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
        XCTAssertEqual(dderror.details, #"SwiftError(description: "error description")"#)
    }

    func testFormattingStringConvertibleSwiftError() {
        struct SwiftError: Error, CustomDebugStringConvertible {
            let debugDescription = "error description"
        }

        let error = SwiftError()
        let dderror = DDError(error: error)

        XCTAssertEqual(dderror.title, "SwiftError")
        XCTAssertEqual(dderror.message, "error description")
        XCTAssertEqual(dderror.details, "error description")
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

        let dderror1 = DDError(
            error: NSErrorSubclass(
                domain: "custom-domain",
                code: 10,
                userInfo: [NSLocalizedDescriptionKey: "error description"]
            )
        )

        XCTAssertEqual(dderror1.title, "custom-domain - 10")
        XCTAssertEqual(dderror1.message, "error description")
        XCTAssertEqual(
            dderror1.details,
            """
            Error Domain=custom-domain Code=10 "error description" UserInfo={NSLocalizedDescription=error description}
            """
        )

        let dderror2 = DDError(
            error: NSErrorSubclass(
                domain: "custom-domain",
                code: 10,
                userInfo: [:]
            )
        )

        XCTAssertEqual(dderror2.title, "NSErrorSubclass")
        XCTAssertEqual(
            dderror2.message,
            #"Error Domain=custom-domain Code=10 "(null)""#
        )
        XCTAssertEqual(
            dderror2.details,
            #"Error Domain=custom-domain Code=10 "(null)""#
        )
    }
}
