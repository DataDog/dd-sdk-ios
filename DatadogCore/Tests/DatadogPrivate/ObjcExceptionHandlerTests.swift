/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import DatadogCore

class ObjcExceptionHandlerTests: XCTestCase {
    private let exceptionHandler = __dd_private_ObjcExceptionHandler()

    func testGivenNonThrowingCode_itDoesNotThrow() throws {
        var counter = 0
        try exceptionHandler.rethrowToSwift { counter += 1 }
        XCTAssertEqual(counter, 1)
    }

    func testGivenThrowingCode_itThrowsNSErrorToSwift() {
        let nsException = NSException(
            name: NSExceptionName(rawValue: "name"),
            reason: "reason",
            userInfo: ["user-info": "some"]
        )

        XCTAssertThrowsError(try exceptionHandler.rethrowToSwift { nsException.raise() }) { error in
            XCTAssertEqual((error as NSError).domain, "name")
            XCTAssertEqual((error as NSError).code, 0)
            XCTAssertEqual((error as NSError).userInfo as? [String: String], ["user-info": "some"])
        }
    }
}
