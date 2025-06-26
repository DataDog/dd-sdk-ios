/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import DatadogInternal
@testable import DatadogRUM
@testable import TestUtilities

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
        var command = RUMAddCurrentViewErrorCommand(
            time: .mockAny(),
            error: SwiftError(),
            source: .source,
            globalAttributes: [:],
            attributes: [:]
        )

        XCTAssertEqual(command.type, "SwiftError")
        XCTAssertEqual(command.message, "error description")
        XCTAssertEqual(command.stack, "error description")

        command = RUMAddCurrentViewErrorCommand(
            time: .mockAny(),
            error: SwiftEnumeratedError.errorLabel,
            source: .source,
            globalAttributes: [:],
            attributes: [:]
        )

        XCTAssertEqual(command.type, "SwiftEnumeratedError")
        XCTAssertEqual(command.message, "errorLabel")
        XCTAssertEqual(command.stack, "errorLabel")

        command = RUMAddCurrentViewErrorCommand(
            time: .mockAny(),
            error: nsError,
            source: .source,
            globalAttributes: [:],
            attributes: [:]
        )

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
        let command1: RUMAddCurrentViewErrorCommand = .mockWithErrorObject(attributes: [CrossPlatformAttributes.errorSourceType: "react-native"])

        XCTAssertEqual(command1.errorSourceType, .reactNative)
        XCTAssertTrue(command1.attributes.isEmpty)

        let command2: RUMAddCurrentViewErrorCommand = .mockWithErrorMessage(attributes: [CrossPlatformAttributes.errorSourceType: "react-native"])

        XCTAssertEqual(command2.errorSourceType, .reactNative)
        XCTAssertTrue(command2.attributes.isEmpty)

        let defaultCommand1: RUMAddCurrentViewErrorCommand = .mockWithErrorObject(attributes: [:])
        let defaultCommand2: RUMAddCurrentViewErrorCommand = .mockWithErrorMessage(attributes: [:])

        XCTAssertEqual(defaultCommand1.errorSourceType, .ios)
        XCTAssertEqual(defaultCommand2.errorSourceType, .ios)
    }

    func testWhenRUMAddCurrentViewErrorCommand_isPassedErrorIsCrashAttribute() {
        let command1: RUMAddCurrentViewErrorCommand = .mockWithErrorObject(attributes: [CrossPlatformAttributes.errorIsCrash: true])

        XCTAssertTrue(command1.isCrash ?? false)
        XCTAssertTrue(command1.attributes.isEmpty)

        let command2: RUMAddCurrentViewErrorCommand = .mockWithErrorMessage(attributes: [CrossPlatformAttributes.errorIsCrash: false])

        XCTAssertFalse(command2.isCrash ?? true)
        XCTAssertTrue(command2.attributes.isEmpty)

        let defaultCommand1: RUMAddCurrentViewErrorCommand = .mockWithErrorObject(attributes: [:])
        let defaultCommand2: RUMAddCurrentViewErrorCommand = .mockWithErrorMessage(attributes: [:])

        XCTAssertNil(defaultCommand1.isCrash)
        XCTAssertNil(defaultCommand2.isCrash)
    }

    func testWhenRUMStopResourceWithErrorCommand_isPassedErrorSourceTypeAttribute() {
        let command1: RUMStopResourceWithErrorCommand = .mockWithErrorObject(attributes: [CrossPlatformAttributes.errorSourceType: "react-native"])

        XCTAssertEqual(command1.errorSourceType, .reactNative)
        XCTAssertTrue(command1.attributes.isEmpty)

        let command2: RUMStopResourceWithErrorCommand = .mockWithErrorMessage(attributes: [CrossPlatformAttributes.errorSourceType: "react-native"])

        XCTAssertEqual(command2.errorSourceType, .reactNative)
        XCTAssertTrue(command2.attributes.isEmpty)

        let defaultCommand1: RUMStopResourceWithErrorCommand = .mockWithErrorObject(attributes: [:])
        let defaultCommand2: RUMStopResourceWithErrorCommand = .mockWithErrorMessage(attributes: [:])

        XCTAssertEqual(defaultCommand1.errorSourceType, .ios)
        XCTAssertEqual(defaultCommand2.errorSourceType, .ios)
    }

    func testResourceWithErrorCommand_forDifferentErrorCategories() {
        let command1: RUMStopResourceWithErrorCommand = .mockWithErrorObject(error: ErrorMock(), source: .network)

        XCTAssertEqual(command1.isNetworkError, false)
        XCTAssertEqual(command1.errorSource, .network)

        let networkError = NSError(domain: NSURLErrorDomain, code: -1_001, userInfo: [:])
        let command2: RUMStopResourceWithErrorCommand = .mockWithErrorObject(error: networkError, source: .network)

        XCTAssertEqual(command2.isNetworkError, true)
        XCTAssertEqual(command2.errorSource, .network)
    }
}
