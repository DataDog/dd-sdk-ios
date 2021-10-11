/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import XCTest
@testable import Datadog

class LogBuilderTests: XCTestCase {
    func testItBuildsBasicLog() throws {
        let builder: LogEventBuilder = .mockWith(
            applicationVersion: "1.2.3",
            serviceName: "test-service-name",
            loggerName: "test-logger-name"
        )
        let error = DDError(error: ErrorMock("description"))
        let log = builder.createLogWith(
            level: .debug,
            message: "debug message",
            error: error,
            date: .mockDecember15th2019At10AMUTC(),
            attributes: .mockWith(userAttributes: ["attribute": "value"]),
            tags: ["tag"]
        )

        XCTAssertEqual(log?.date, .mockDecember15th2019At10AMUTC())
        XCTAssertEqual(log?.applicationVersion, "1.2.3")
        XCTAssertEqual(log?.status, .debug)
        XCTAssertEqual(log?.message, "debug message")
        XCTAssertEqual(log?.error?.message, "description")
        XCTAssertEqual(log?.serviceName, "test-service-name")
        XCTAssertEqual(log?.loggerName, "test-logger-name")
        XCTAssertEqual(log?.tags, ["tag"])
        XCTAssertEqual(log?.attributes.userAttributes as? [String: String], ["attribute": "value"])

        XCTAssertEqual(
            builder.createLogWith(level: .info, message: "", error: nil, date: .mockAny(), attributes: .mockAny(), tags: [])?.status, .info
        )
        XCTAssertEqual(
            builder.createLogWith(level: .notice, message: "", error: nil, date: .mockAny(), attributes: .mockAny(), tags: [])?.status, .notice
        )
        XCTAssertEqual(
            builder.createLogWith(level: .warn, message: "", error: nil, date: .mockAny(), attributes: .mockAny(), tags: [])?.status, .warn
        )
        XCTAssertEqual(
            builder.createLogWith(level: .error, message: "", error: nil, date: .mockAny(), attributes: .mockAny(), tags: [])?.status, .error
        )
        XCTAssertEqual(
            builder.createLogWith(level: .critical, message: "", error: nil, date: .mockAny(), attributes: .mockAny(), tags: [])?.status, .critical
        )
    }

    func testItSetsThreadNameAttribute() {
        let builder: LogEventBuilder = .mockAny()
        let expectation = self.expectation(description: "create all logs")
        expectation.expectedFulfillmentCount = 3

        DispatchQueue.main.async {
            let log = builder.createLogWith(level: .debug, message: "", error: nil, date: .mockAny(), attributes: .mockAny(), tags: [])
            XCTAssertEqual(log?.threadName, "main")
            expectation.fulfill()
        }

        DispatchQueue.global(qos: .default).async {
            let log = builder.createLogWith(level: .debug, message: "", error: nil, date: .mockAny(), attributes: .mockAny(), tags: [])
            XCTAssertEqual(log?.threadName, "background")
            expectation.fulfill()
        }

        DispatchQueue(label: "custom-queue").async {
            let previousName = Thread.current.name
            defer { Thread.current.name = previousName } // reset it as this thread might be picked by `.global(qos: .default)`

            Thread.current.name = "custom-thread-name"
            let log = builder.createLogWith(level: .debug, message: "", error: nil, date: .mockAny(), attributes: .mockAny(), tags: [])
            XCTAssertEqual(log?.threadName, "custom-thread-name")
            expectation.fulfill()
        }

        waitForExpectations(timeout: 1, handler: nil)
    }

    func testGivenBuilderWithEventMapper_whenEventIsModified_itBuildsModifiedEvent() throws {
        let builder: LogEventBuilder = .mockWith(
            logEventMapper: { log in
                var mutableLog = log
                mutableLog.message = "modified log message"
                mutableLog.tags = .mockRandom()
                return mutableLog
            }
        )

        let log = try XCTUnwrap(
            builder.createLogWith(
                level: .critical,
                message: "original log message",
                error: nil,
                date: .mockAny(),
                attributes: .mockAny(),
                tags: []
            )
        )

        XCTAssertEqual(log.message, "modified log message")
        XCTAssertGreaterThan(log.tags!.count, 0)
    }

    func testGivenBuilderWithEventMapper_whenEventIsDropped_itReturnsNil() throws {
        let builder: LogEventBuilder = .mockWith(
            logEventMapper: { _ in
                return nil
            }
        )

        let log = builder.createLogWith(
            level: .critical,
            message: "original log message",
            error: nil,
            date: .mockAny(),
            attributes: .mockAny(),
            tags: []
        )

        XCTAssertNil(log)
    }
}
