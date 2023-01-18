/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
@testable import Datadog

class ConsoleLoggerTests: XCTestCase {
    private let mock = PrintFunctionMock()

    func testItPrintsMessageWithExpectedFormat() {
        let randomPrefix: String = .mockRandom(length: 10)

        // Given
        let logger = ConsoleLogger(
            configuration: .init(
                timeZone: .UTC,
                format: .shortWith(prefix: randomPrefix)
            ),
            dateProvider: RelativeDateProvider(
                using: .mockDecember15th2019At10AMUTC()
            ),
            printFunction: mock.print
        )

        // When
        logger.debug("Debug message")
        logger.info("Info message")
        logger.notice("Notice message")
        logger.warn("Warn message")
        logger.error("Error message")
        logger.critical("Critical message")

        // Then
        XCTAssertEqual(mock.printedMessages.count, 6)
        XCTAssertEqual(mock.printedMessages[0], "\(randomPrefix) 10:00:00.000 [DEBUG] Debug message")
        XCTAssertEqual(mock.printedMessages[1], "\(randomPrefix) 10:00:00.000 [INFO] Info message")
        XCTAssertEqual(mock.printedMessages[2], "\(randomPrefix) 10:00:00.000 [NOTICE] Notice message")
        XCTAssertEqual(mock.printedMessages[3], "\(randomPrefix) 10:00:00.000 [WARN] Warn message")
        XCTAssertEqual(mock.printedMessages[4], "\(randomPrefix) 10:00:00.000 [ERROR] Error message")
        XCTAssertEqual(mock.printedMessages[5], "\(randomPrefix) 10:00:00.000 [CRITICAL] Critical message")
    }

    func testItPrintsErrorWithExpectedFormat() {
        // Given
        let logger = ConsoleLogger(
            configuration: .init(
                timeZone: .UTC,
                format: .short
            ),
            dateProvider: RelativeDateProvider(
                using: .mockDecember15th2019At10AMUTC()
            ),
            printFunction: mock.print
        )

        let error = NSError(
            domain: "The error domain",
            code: 42,
            userInfo: [NSLocalizedDescriptionKey: "A localized description of the error"]
        )

        // When
        logger.debug("Message", error: error)
        logger.info("Message", error: error)
        logger.notice("Message", error: error)
        logger.warn("Message", error: error)
        logger.error("Message", error: error)
        logger.critical("Message", error: error)

        // Then
        let expectedMessages = ["[DEBUG]", "[INFO]", "[NOTICE]", "[WARN]", "[ERROR]", "[CRITICAL]"].map { status in
            """
            10:00:00.000 \(status) Message

            Error details:
            → type: The error domain - 42
            → message: A localized description of the error
            → stack: Error Domain=The error domain Code=42 "A localized description of the error" UserInfo={NSLocalizedDescription=A localized description of the error}
            """
        }
        zip(expectedMessages, mock.printedMessages).forEach { expected, actual in
            XCTAssertEqual(expected, actual)
        }
        XCTAssertEqual(mock.printedMessages.count, 6)
    }

    func testItPrintsErrorStringsWithExpectedFormat() {
        // Given
        let logger = ConsoleLogger(
            configuration: .init(
                timeZone: .UTC,
                format: .short
            ),
            dateProvider: RelativeDateProvider(
                using: .mockDecember15th2019At10AMUTC()
            ),
            printFunction: mock.print
        )

        let message = String.mockRandom()
        let errorKind = String.mockRandom()
        let errorMessage = String.mockRandom()
        let stackTrace = String.mockRandom()

        logger.log(
            level: .info,
            message: message,
            errorKind: errorKind,
            errorMessage: errorMessage,
            stackTrace: stackTrace,
            attributes: nil
        )

        // Then
        let expectedMessage = """
            10:00:00.000 [INFO] \(message)

            Error details:
            → type: \(errorKind)
            → message: \(errorMessage)
            → stack: \(stackTrace)
            """
        XCTAssertEqual(mock.printedMessages.first, expectedMessage)
        XCTAssertEqual(mock.printedMessages.count, 1)
    }
}
