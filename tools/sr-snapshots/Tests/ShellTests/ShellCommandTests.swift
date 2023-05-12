/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
@testable import Shell

class ShellCommandTests: XCTestCase {
    func testWhenCommandExitsWithCode0_itReturnsOutput() throws {
        let output = try shell("echo 'foo bar' && exit 0")
        XCTAssertEqual(output, "foo bar")
    }

    func testWhenCommandExitsWithCodeOtherThan0_itThrowsErrorAndReturnsOutput() throws {
        XCTAssertThrowsError(try shell("echo 'foo bar' && exit 1")) { error in
            // swiftlint:disable trailing_whitespace
            XCTAssertEqual(
                (error as? ShellError)?.description,
                """
                status: 1
                output: foo bar
                error: 
                """
            )
            // swiftlint:enable trailing_whitespace
        }
    }
}
