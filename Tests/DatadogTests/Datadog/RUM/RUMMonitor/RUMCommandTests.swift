/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import XCTest
@testable import Datadog

class RUMCommandTests: XCTestCase {
    // NOTE: RUMM-817 When nested in method,
    // ddError.title contains "unknown context at $110014ea8"
    class SwiftClassError: Error {
        let someProperty = "some value"
    }

    func testWhenRUMAddCurrentViewErrorCommand_isBuildWithErrorObject() {
        struct SwiftError: Error, CustomDebugStringConvertible {
            let debugDescription = "error description"
        }
        var command = RUMAddCurrentViewErrorCommand(time: .mockAny(), error: SwiftError(), source: .source, attributes: [:])

        XCTAssertEqual(command.message, "SwiftError - error description")
        XCTAssertEqual(command.stack, "debugDescription: error description")

        enum SwiftEnumeratedError: Error {
            case errorLabel
        }
        let enumError = SwiftEnumeratedError.errorLabel
        command = RUMAddCurrentViewErrorCommand(time: .mockAny(), error: enumError, source: .source, attributes: [:])

        XCTAssertEqual(command.message, "SwiftEnumeratedError - errorLabel")
        XCTAssertNil(command.stack)

        command = RUMAddCurrentViewErrorCommand(time: .mockAny(), error: SwiftClassError(), source: .source, attributes: [:])

        XCTAssertEqual(command.message, "SwiftClassError - DatadogTests.RUMCommandTests.SwiftClassError")
        XCTAssertEqual(command.stack, "someProperty: some value")

        let nsError = NSError(
            domain: "custom-domain",
            code: 10,
            userInfo: [NSLocalizedDescriptionKey: "error description"]
        )
        command = RUMAddCurrentViewErrorCommand(time: .mockAny(), error: nsError, source: .source, attributes: [:])

        XCTAssertEqual(command.message, "custom-domain - 10 - error description")
        XCTAssertEqual(
            command.stack,
            """
            Error Domain=custom-domain Code=10 "error description" UserInfo={NSLocalizedDescription=error description}
            """
        )
    }
}
