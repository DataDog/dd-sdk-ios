/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import XCTest
@testable import Datadog

class FileWriterTests: XCTestCase {
    private let queue = DispatchQueue(label: "dd-tests-write", target: .global(qos: .utility))

    override func setUp() {
        super.setUp()
        temporaryDirectory.create()
    }

    override func tearDown() {
        temporaryDirectory.delete()
        super.tearDown()
    }

    func testItWritesDataToSingleFile() throws {
        let expectation = self.expectation(description: "write completed")
        let writer = FileWriter(
            orchestrator: .mockWriteToSingleFile(in: temporaryDirectory),
            queue: queue,
            maxWriteSize: .max
        )

        writer.write(value: ["key1": "value1"])
        writer.write(value: ["key2": "value3"])
        writer.write(value: ["key3": "value3"])

        waitForWritesCompletion(on: queue, thenFulfill: expectation)
        waitForExpectations(timeout: 1, handler: nil)
        XCTAssertEqual(try temporaryDirectory.files().count, 1)
        XCTAssertEqual(
            try temporaryDirectory.files()[0].read(),
            #"{"key1":"value1"},{"key2":"value3"},{"key3":"value3"}"#.utf8Data
        )
    }

    func testItDropsData_whenItExceedsMaxWriteSize() throws {
        let expectation1 = self.expectation(description: "first write completed")
        let expectation2 = self.expectation(description: "second write completed")
        let writer = FileWriter(
            orchestrator: .mockWriteToSingleFile(in: temporaryDirectory),
            queue: queue,
            maxWriteSize: 17 // 17 bytes is enough to write {"key1":"value1"} JSON
        )

        writer.write(value: ["key1": "value1"]) // will be written

        waitForWritesCompletion(on: queue, thenFulfill: expectation1)
        wait(for: [expectation1], timeout: 1)
        XCTAssertEqual(try temporaryDirectory.files()[0].read(), #"{"key1":"value1"}"#.utf8Data)

        writer.write(value: ["key2": "value3 that makes it exceed 17 bytes"]) // will be dropped

        waitForWritesCompletion(on: queue, thenFulfill: expectation2)
        wait(for: [expectation2], timeout: 1)
        XCTAssertEqual(try temporaryDirectory.files()[0].read(), #"{"key1":"value1"}"#.utf8Data) // same content as before
    }

    func testGivenErrorVerbosity_whenLogCannotBeEncoded_itPrintsError() throws {
        let expectation = self.expectation(description: "write completed")
        let previousUserLogger = userLogger
        defer { userLogger = previousUserLogger }

        let output = LogOutputMock()
        userLogger = Logger(logOutput: output, identifier: "sdk-user")

        let writer = FileWriter(
            orchestrator: .mockWriteToSingleFile(in: temporaryDirectory),
            queue: queue,
            maxWriteSize: .max
        )

        writer.write(value: FailingEncodableMock(errorMessage: "failed to encode `FailingEncodable`."))

        waitForWritesCompletion(on: queue, thenFulfill: expectation)
        waitForExpectations(timeout: 1, handler: nil)

        XCTAssertEqual(output.recordedLog?.level, .error)
        XCTAssertEqual(output.recordedLog?.message, "🔥 Failed to write log: failed to encode `FailingEncodable`.")
    }

    private func waitForWritesCompletion(on queue: DispatchQueue, thenFulfill expectation: XCTestExpectation) {
        queue.async { expectation.fulfill() }
    }
}
