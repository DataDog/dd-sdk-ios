/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import XCTest
@testable import Datadog

class RUMCommandTests: XCTestCase {
    func testWhenRUMAddCurrentViewErrorCommand_isBuildWithErrorObject() {
        struct SwiftError: Error, CustomDebugStringConvertible {
            let debugDescription = "error description"
        }
        var command = RUMAddCurrentViewErrorCommand(time: .mockAny(), error: SwiftError(), source: .source, attributes: [:])

        XCTAssertEqual(command.type, "SwiftError")
        XCTAssertEqual(command.message, "error description")
        XCTAssertEqual(command.stack, "error description")

        enum SwiftEnumeratedError: Error {
            case errorLabel
        }
        command = RUMAddCurrentViewErrorCommand(time: .mockAny(), error: SwiftEnumeratedError.errorLabel, source: .source, attributes: [:])

        XCTAssertEqual(command.type, "SwiftEnumeratedError")
        XCTAssertEqual(command.message, "errorLabel")
        XCTAssertEqual(command.stack, "errorLabel")

        let nsError = NSError(
            domain: "custom-domain",
            code: 10,
            userInfo: [NSLocalizedDescriptionKey: "error description"]
        )
        command = RUMAddCurrentViewErrorCommand(time: .mockAny(), error: nsError, source: .source, attributes: [:])

        XCTAssertEqual(command.type, "custom-domain - 10")
        XCTAssertEqual(command.message, "error description")
        XCTAssertEqual(
            command.stack,
            """
            Error Domain=custom-domain Code=10 "error description" UserInfo={NSLocalizedDescription=error description}
            """
        )
    }
}
