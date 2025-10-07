/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import TestUtilities
import DatadogInternal
@testable import DatadogCore

class InternalLoggerTests: XCTestCase {
    private let mock = PrintFunctionSpy()

    func testItPrintsMessageWithExpectedFormat() {
        // Given
        let logger = InternalLogger(
            dateProvider: RelativeDateProvider(
                using: .mockDecember15th2019At10AMUTC(addingTimeInterval: 4.2)
            ),
            timeZone: .UTC,
            printFunction: mock.print(message:level:),
            verbosityLevel: { .debug }
        )

        // When
        logger.debug("Debug message")
        logger.warn("Warn message")
        logger.error("Error message")
        logger.critical("Critical message")

        // Then
        XCTAssertEqual(mock.printedMessages.count, 4)
        XCTAssertEqual(mock.printedMessages[0], "[DATADOG SDK] 🐶 → 10:00:04.200 Debug message")
        XCTAssertEqual(mock.printedMessages[1], "[DATADOG SDK] 🐶 → 10:00:04.200 ⚠️ Warn message")
        XCTAssertEqual(mock.printedMessages[2], "[DATADOG SDK] 🐶 → 10:00:04.200 🔥 Error message")
        XCTAssertEqual(mock.printedMessages[3], "[DATADOG SDK] 🐶 → 10:00:04.200 ⛔️ Critical message")
    }

    func testItPrintsErrorWithExpectedFormat() {
        // Given
        let logger = InternalLogger(
            dateProvider: RelativeDateProvider(
                using: .mockDecember15th2019At10AMUTC()
            ),
            timeZone: .UTC,
            printFunction: mock.print(message:level:),
            verbosityLevel: { .debug }
        )

        let error = NSError(
            domain: "The error domain",
            code: 42,
            userInfo: [NSLocalizedDescriptionKey: "A localized description of the error"]
        )

        // When
        logger.debug("Message", error: error)
        logger.warn("Message", error: error)
        logger.error("Message", error: error)
        logger.critical("Message", error: error)

        // Then
        let expectedMessages = ["", "⚠️ ", "🔥 ", "⛔️ "].map { emoji in
            """
            [DATADOG SDK] 🐶 → 10:00:00.000 \(emoji)Message

            Error details:
            → type: The error domain - 42
            → message: A localized description of the error
            → stack: Error Domain=The error domain Code=42 "A localized description of the error" UserInfo={NSLocalizedDescription=A localized description of the error}
            """
        }
        zip(expectedMessages, mock.printedMessages).forEach { expected, actual in
            XCTAssertEqual(expected, actual)
        }
        XCTAssertEqual(mock.printedMessages.count, 4)
    }

    func testItPrintsMessagesAboveGivenVerbosityLevel() {
        var verbosityLevel: CoreLoggerLevel? = nil

        // Given
        let logger = InternalLogger(
            dateProvider: RelativeDateProvider(
                using: .mockDecember15th2019At10AMUTC()
            ),
            timeZone: .UTC,
            printFunction: mock.print(message:level:),
            verbosityLevel: { verbosityLevel }
        )

        func logMessageUsingAllLevels() {
            CoreLoggerLevel.allCases.forEach { level in
                logger.log(level, message: .mockRandom(), error: nil)
            }
        }

        // When & Then
        verbosityLevel = nil
        mock.reset()
        logMessageUsingAllLevels()
        XCTAssertEqual(mock.printedMessages.count, 0)

        verbosityLevel = .debug
        mock.reset()
        logMessageUsingAllLevels()
        XCTAssertEqual(mock.printedMessages.count, 4)

        verbosityLevel = .warn
        mock.reset()
        logMessageUsingAllLevels()
        XCTAssertEqual(mock.printedMessages.count, 3)

        verbosityLevel = .error
        mock.reset()
        logMessageUsingAllLevels()
        XCTAssertEqual(mock.printedMessages.count, 2)

        verbosityLevel = .critical
        mock.reset()
        logMessageUsingAllLevels()
        XCTAssertEqual(mock.printedMessages.count, 1)
    }

    func testItEvaluatesMessageOnlyWhenItWillBePrinted() {
        var verbosityLevel: CoreLoggerLevel? = nil

        // Given
        let logger = InternalLogger(
            dateProvider: SystemDateProvider(),
            timeZone: .UTC,
            printFunction: mock.print(message:level:),
            verbosityLevel: { verbosityLevel }
        )

        // When
        var evaluatedMessage1 = false
        var evaluatedMessage2 = false

        verbosityLevel = nil
        logger.debug({ evaluatedMessage1 = true; return "message 1" }())

        verbosityLevel = .debug
        logger.debug({ evaluatedMessage2 = true; return "message 2" }())

        // Then
        XCTAssertFalse(
            evaluatedMessage1,
            "It souldn't evaluate autoclosure for 'message 1' as the message was not printed"
        )
        XCTAssertTrue(
            evaluatedMessage2,
            "It souldn evaluate autoclosure for 'message 2' as the message was printed"
        )
    }

    // MARK: - Thread Safety Tests

    func testConcurrentLoggerReplacementDoesNotCrash() {
        // Ensures DD.logger can be safely replaced while being accessed from multiple threads
        let expectation = self.expectation(description: "Concurrent operations complete")
        expectation.expectedFulfillmentCount = 10

        // Simulate multiple threads reading DD.logger
        for threadId in 0..<8 {
            DispatchQueue.global(qos: .userInitiated).async {
                for i in 0..<1_000 {
                    DD.logger.debug("Thread \(threadId) message \(i)")
                    DD.logger.error("Thread \(threadId) error \(i)")
                }
                expectation.fulfill()
            }
        }

        // Simulate threads replacing DD.logger (like during SDK initialization)
        for _ in 0..<2 {
            DispatchQueue.global(qos: .userInitiated).async {
                for _ in 0..<200 {
                    DD.logger = InternalLogger(
                        dateProvider: SystemDateProvider(),
                        timeZone: .current,
                        printFunction: { _, _ in /* no-op */ },
                        verbosityLevel: { .debug }
                    )
                    Thread.sleep(forTimeInterval: 0.00001)
                }
                expectation.fulfill()
            }
        }

        waitForExpectations(timeout: 60)
    }
}
