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
            queue: queue
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

    /// NOTE: Test added after incident-4797
    func testGivenFileContainingData_whenNextDataFails_itDoesNotMalformTheEndOfTheFile() throws {
        let previousObjcExceptionHandler = objcExceptionHandler
        defer { objcExceptionHandler = previousObjcExceptionHandler }

        let expectation = self.expectation(description: "write completed")
        let writer = FileWriter(
            orchestrator: .mockWriteToSingleFile(in: temporaryDirectory),
            queue: queue
        )

        objcExceptionHandler = ObjcExceptionHandlerDeferredMock(
            throwingError: ErrorMock("I/O exception"),
            /*
                Following the logic in `FileWriter` and `File`, the 3 comes from:
                - succeed on `fileHandle.seekToEndOfFile()` to prepare the file for the first write
                - succeed on `fileHandle.write(_:)` for `writer.write(value: ["key1": "value1"])`
                - succeed on `fileHandle.seekToEndOfFile()` to prepare the file for the second `writer.write(value:)`
                - throw an `I/O exception` for `fileHandle.write(_:)` for the second write
             */
            afterSucceedingCallsCounts: 3
        )

        writer.write(value: ["key1": "value1"]) // first write (2 calls to `ObjcExceptionHandler`)
        writer.write(value: ["key2": "value2"]) // second write (2 calls to `ObjcExceptionHandler`, where the latter fails)

        waitForWritesCompletion(on: queue, thenFulfill: expectation)
        waitForExpectations(timeout: 1, handler: nil)
        XCTAssertEqual(try temporaryDirectory.files().count, 1)

        XCTAssertEqual(
            try temporaryDirectory.files()[0].read().utf8String,
            #"{"key1":"value1"}"# // second write should be ignored due to `I/O exception`
        )
    }

    /// NOTE: Test added after incident-4797
    func testWhenIOExceptionsHappenRandomly_theFileIsNeverMalformed() throws {
        let previousObjcExceptionHandler = objcExceptionHandler
        defer { objcExceptionHandler = previousObjcExceptionHandler }

        let expectation = self.expectation(description: "write completed")
        let writer = FileWriter(
            orchestrator: .mockWriteToSingleFile(in: temporaryDirectory),
            queue: queue
        )

        objcExceptionHandler = ObjcExceptionHandlerNonDeterministicMock(
            throwingError: ErrorMock("I/O exception"),
            withProbability: 0.2
        )

        struct Foo: Codable {
            let foo = "bar"
        }

        (0...500).forEach { _ in writer.write(value: Foo()) }

        waitForWritesCompletion(on: queue, thenFulfill: expectation)
        waitForExpectations(timeout: 5, handler: nil)
        XCTAssertEqual(try temporaryDirectory.files().count, 1)

        let fileData = try temporaryDirectory.files()[0].read()
        let jsonDecoder = JSONDecoder()

        XCTAssertNoThrow(try jsonDecoder.decode([Foo].self, from: "[".utf8Data + fileData + "]".utf8Data))
    }

    func testGivenErrorVerbosity_whenIndividualDataExceedsMaxWriteSize_itDropsDataAndPrintsError() throws {
        let expectation1 = self.expectation(description: "write completed")
        let expectation2 = self.expectation(description: "second write completed")
        let previousUserLogger = userLogger
        defer { userLogger = previousUserLogger }

        let output = LogOutputMock()
        userLogger = Logger(logOutput: output, identifier: "sdk-user")

        let writer = FileWriter(
            orchestrator: FilesOrchestrator(
                directory: temporaryDirectory,
                writeConditions: WritableFileConditions(
                    performance: .mockWith(
                        maxBatchSize: .max,
                        maxSizeOfLogsDirectory: .max,
                        maxFileAgeForWrite: .distantFuture,
                        maxLogsPerBatch: .max,
                        maxLogSize: 17 // 17 bytes is enough to write {"key1":"value1"} JSON
                    )
                ),
                readConditions: .mockReadAllFiles(),
                dateProvider: SystemDateProvider()
            ),
            queue: queue
        )

        writer.write(value: ["key1": "value1"]) // will be written

        waitForWritesCompletion(on: queue, thenFulfill: expectation1)
        wait(for: [expectation1], timeout: 1)
        XCTAssertEqual(try temporaryDirectory.files()[0].read(), #"{"key1":"value1"}"#.utf8Data)

        writer.write(value: ["key2": "value3 that makes it exceed 17 bytes"]) // will be dropped

        waitForWritesCompletion(on: queue, thenFulfill: expectation2)
        wait(for: [expectation2], timeout: 1)
        XCTAssertEqual(try temporaryDirectory.files()[0].read(), #"{"key1":"value1"}"#.utf8Data) // same content as before
        XCTAssertEqual(output.recordedLog?.level, .error)
        XCTAssertEqual(output.recordedLog?.message, "🔥 Failed to write log: data exceeds the maximum size of 17 bytes.")
    }

    func testGivenErrorVerbosity_whenDataCannotBeEncoded_itPrintsError() throws {
        let expectation = self.expectation(description: "write completed")
        let previousUserLogger = userLogger
        defer { userLogger = previousUserLogger }

        let output = LogOutputMock()
        userLogger = Logger(logOutput: output, identifier: "sdk-user")

        let writer = FileWriter(
            orchestrator: .mockWriteToSingleFile(in: temporaryDirectory),
            queue: queue
        )

        writer.write(value: FailingEncodableMock(errorMessage: "failed to encode `FailingEncodable`."))

        waitForWritesCompletion(on: queue, thenFulfill: expectation)
        waitForExpectations(timeout: 1, handler: nil)

        XCTAssertEqual(output.recordedLog?.level, .error)
        XCTAssertEqual(output.recordedLog?.message, "🔥 Failed to write log: failed to encode `FailingEncodable`.")
    }

    func testGivenErrorVerbosity_whenIOExceptionIsThrown_itPrintsError() throws {
        let expectation = self.expectation(description: "write completed")
        let previousUserLogger = userLogger
        defer { userLogger = previousUserLogger }
        let previousObjcExceptionHandler = objcExceptionHandler
        defer { objcExceptionHandler = previousObjcExceptionHandler }

        let output = LogOutputMock()
        userLogger = Logger(logOutput: output, identifier: "sdk-user")
        objcExceptionHandler = ObjcExceptionHandlerMock(throwingError: ErrorMock("I/O exception"))

        let writer = FileWriter(
            orchestrator: .mockWriteToSingleFile(in: temporaryDirectory),
            queue: queue
        )

        writer.write(value: ["whatever"])

        waitForWritesCompletion(on: queue, thenFulfill: expectation)
        waitForExpectations(timeout: 1, handler: nil)

        XCTAssertEqual(output.recordedLog?.level, .error)
        XCTAssertEqual(output.recordedLog?.message, "🔥 Failed to write log: I/O exception")
    }

    private func waitForWritesCompletion(on queue: DispatchQueue, thenFulfill expectation: XCTestExpectation) {
        queue.async { expectation.fulfill() }
    }
}
