/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import XCTest
@testable import Datadog

class RUMCommandTests: XCTestCase {
    struct SwiftError: Error, CustomDebugStringConvertible {
        let debugDescription = "error description"
    }

    enum SwiftEnumeratedError: Error {
        case errorLabel
    }

    let nsError = NSError(
        domain: "custom-domain",
        code: 10,
        userInfo: [NSLocalizedDescriptionKey: "error description"]
    )

    func testWhenRUMAddCurrentViewErrorCommand_isBuildWithErrorObject() {
        var command = RUMAddCurrentViewErrorCommand(time: .mockAny(), error: SwiftError(), source: .source, attributes: [:])

        XCTAssertEqual(command.type, "SwiftError")
        XCTAssertEqual(command.message, "error description")
        XCTAssertEqual(command.stack, "error description")

        command = RUMAddCurrentViewErrorCommand(time: .mockAny(), error: SwiftEnumeratedError.errorLabel, source: .source, attributes: [:])

        XCTAssertEqual(command.type, "SwiftEnumeratedError")
        XCTAssertEqual(command.message, "errorLabel")
        XCTAssertEqual(command.stack, "errorLabel")

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

    func testWhenRUMAddCurrentViewErrorCommand_isPassedErrorSourceTypeAttribute() {
        let command1 = RUMAddCurrentViewErrorCommand(time: .mockAny(), error: SwiftError(), source: .source, attributes: [RUMAttribute.internalErrorSourceType: "react-native"])

        XCTAssertEqual(command1.errorSourceType, .reactNative)
        XCTAssertTrue(command1.attributes.isEmpty)

        let command2 = RUMAddCurrentViewErrorCommand(time: .mockAny(), message: .mockAny(), type: .mockAny(), stack: .mockAny(), source: .source, attributes: [RUMAttribute.internalErrorSourceType: "react-native"])

        XCTAssertEqual(command2.errorSourceType, .reactNative)
        XCTAssertTrue(command2.attributes.isEmpty)

        let defaultCommand = RUMAddCurrentViewErrorCommand(time: .mockAny(), message: .mockAny(), type: .mockAny(), stack: .mockAny(), source: .source, attributes: [:])

        XCTAssertEqual(defaultCommand.errorSourceType, .ios)
    }

    func testWhenRUMStopResourceWithErrorCommand_isPassedErrorSourceTypeAttribute() {
        let command1 = RUMStopResourceWithErrorCommand(resourceKey: .mockAny(), time: .mockAny(), error: SwiftError(), source: .source, httpStatusCode: .mockAny(), attributes: [RUMAttribute.internalErrorSourceType: "react-native"])

        XCTAssertEqual(command1.errorSourceType, .reactNative)
        XCTAssertTrue(command1.attributes.isEmpty)

        let command2 = RUMStopResourceWithErrorCommand(resourceKey: .mockAny(), time: .mockAny(), message: .mockAny(), type: .mockAny(), source: .source, httpStatusCode: .mockAny(), attributes: [RUMAttribute.internalErrorSourceType: "react-native"])

        XCTAssertEqual(command2.errorSourceType, .reactNative)
        XCTAssertTrue(command2.attributes.isEmpty)

        let defaultCommand = RUMStopResourceWithErrorCommand(resourceKey: .mockAny(), time: .mockAny(), message: .mockAny(), type: .mockAny(), source: .source, httpStatusCode: .mockAny(), attributes: [:])

        XCTAssertEqual(defaultCommand.errorSourceType, .ios)
    }
}
