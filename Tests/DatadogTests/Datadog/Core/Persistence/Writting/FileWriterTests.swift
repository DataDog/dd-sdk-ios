/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import XCTest
@testable import Datadog

class FileWriterTests: XCTestCase {
    override func setUp() {
        super.setUp()
        temporaryDirectory.create()
    }

    override func tearDown() {
        temporaryDirectory.delete()
        super.tearDown()
    }

    func testItWritesDataToSingleFile() throws {
        let writer = FileWriter(
            dataFormat: DataFormat(prefix: "[", suffix: "]", separator: ","),
            orchestrator: FilesOrchestrator(
                directory: temporaryDirectory,
                performance: PerformancePreset(batchSize: .medium, uploadFrequency: .average, bundleType: .iOSApp),
                dateProvider: SystemDateProvider()
            )
        )

        writer.write(value: ["key1": "value1"])
        writer.write(value: ["key2": "value3"])
        writer.write(value: ["key3": "value3"])

        XCTAssertEqual(try temporaryDirectory.files().count, 1)
        XCTAssertEqual(
            try temporaryDirectory.files()[0].read(),
            #"{"key1":"value1"},{"key2":"value3"},{"key3":"value3"}"#.utf8Data
        )
    }

    func testGivenErrorVerbosity_whenIndividualDataExceedsMaxWriteSize_itDropsDataAndPrintsError() throws {
        let previousUserLogger = userLogger
        defer { userLogger = previousUserLogger }

        let output = LogOutputMock()
        userLogger = .mockWith(logOutput: output)

        let writer = FileWriter(
            dataFormat: .mockWith(prefix: "[", suffix: "]"),
            orchestrator: FilesOrchestrator(
                directory: temporaryDirectory,
                performance: StoragePerformanceMock(
                    maxFileSize: .max,
                    maxDirectorySize: .max,
                    maxFileAgeForWrite: .distantFuture,
                    minFileAgeForRead: .mockAny(),
                    maxFileAgeForRead: .mockAny(),
                    maxObjectsInFile: .max,
                    maxObjectSize: 17 // 17 bytes is enough to write {"key1":"value1"} JSON
                ),
                dateProvider: SystemDateProvider()
            )
        )

        writer.write(value: ["key1": "value1"]) // will be written

        XCTAssertEqual(try temporaryDirectory.files()[0].read(), #"{"key1":"value1"}"#.utf8Data)

        writer.write(value: ["key2": "value3 that makes it exceed 17 bytes"]) // will be dropped

        XCTAssertEqual(try temporaryDirectory.files()[0].read(), #"{"key1":"value1"}"#.utf8Data) // same content as before
        XCTAssertEqual(output.recordedLog?.status, .error)
        XCTAssertEqual(output.recordedLog?.message, "🔥 Failed to write log: data exceeds the maximum size of 17 bytes.")
    }

    func testGivenErrorVerbosity_whenDataCannotBeEncoded_itPrintsError() throws {
        let previousUserLogger = userLogger
        defer { userLogger = previousUserLogger }

        let output = LogOutputMock()
        userLogger = .mockWith(logOutput: output)

        let writer = FileWriter(
            dataFormat: .mockAny(),
            orchestrator: FilesOrchestrator(
                directory: temporaryDirectory,
                performance: PerformancePreset(batchSize: .medium, uploadFrequency: .average, bundleType: .iOSApp),
                dateProvider: SystemDateProvider()
            )
        )

        writer.write(value: FailingEncodableMock(errorMessage: "failed to encode `FailingEncodable`."))

        XCTAssertEqual(output.recordedLog?.status, .error)
        XCTAssertEqual(output.recordedLog?.message, "🔥 Failed to write log: failed to encode `FailingEncodable`.")
    }

    func testGivenErrorVerbosity_whenIOExceptionIsThrown_itPrintsError() throws {
        let previousUserLogger = userLogger
        defer { userLogger = previousUserLogger }

        let output = LogOutputMock()
        userLogger = .mockWith(logOutput: output)

        let writer = FileWriter(
            dataFormat: .mockAny(),
            orchestrator: FilesOrchestrator(
                directory: temporaryDirectory,
                performance: PerformancePreset(batchSize: .medium, uploadFrequency: .average, bundleType: .iOSApp),
                dateProvider: SystemDateProvider()
            )
        )

        writer.write(value: ["ok"]) // will create the file
        try? temporaryDirectory.files()[0].makeReadonly()
        writer.write(value: ["won't be written"])
        try? temporaryDirectory.files()[0].makeReadWrite()

        XCTAssertEqual(output.recordedLog?.status, .error)
        XCTAssertNotNil(output.recordedLog?.message)
        XCTAssertTrue(output.recordedLog!.message.contains("You don’t have permission"))
    }

    /// NOTE: Test added after incident-4797
    func testWhenIOExceptionsHappenRandomly_theFileIsNeverMalformed() throws {
        let writer = FileWriter(
            dataFormat: DataFormat(prefix: "[", suffix: "]", separator: ","),
            orchestrator: FilesOrchestrator(
                directory: temporaryDirectory,
                performance: StoragePerformanceMock(
                    maxFileSize: .max,
                    maxDirectorySize: .max,
                    maxFileAgeForWrite: .distantFuture, // write to single file
                    minFileAgeForRead: .distantFuture,
                    maxFileAgeForRead: .distantFuture,
                    maxObjectsInFile: .max, // write to single file
                    maxObjectSize: .max
                ),
                dateProvider: SystemDateProvider()
            )
        )

        let ioInterruptionQueue = DispatchQueue(label: "com.datadohq.file-writer-random-io")

        func randomlyInterruptIO(for file: File?) {
            ioInterruptionQueue.async { try? file?.makeReadonly() }
            ioInterruptionQueue.async { try? file?.makeReadWrite() }
        }

        struct Foo: Codable {
            var foo = "bar"
        }

        // Write 300 of `Foo`s and interrupt writes randomly
        (0..<300).forEach { _ in
            writer.write(value: Foo())
            randomlyInterruptIO(for: try? temporaryDirectory.files().first)
        }

        ioInterruptionQueue.sync { }

        XCTAssertEqual(try temporaryDirectory.files().count, 1)

        let fileData = try temporaryDirectory.files()[0].read()
        let jsonDecoder = JSONDecoder()

        // Assert that data written is not malformed
        let writtenData = try jsonDecoder.decode([Foo].self, from: "[".utf8Data + fileData + "]".utf8Data)
        // Assert that some (including all) `Foo`s were written
        XCTAssertGreaterThan(writtenData.count, 0)
        XCTAssertLessThanOrEqual(writtenData.count, 300)
    }
}
