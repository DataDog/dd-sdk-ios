/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
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
            orchestrator: FilesOrchestrator(
                directory: temporaryDirectory,
                performance: PerformancePreset.mockAny(),
                dateProvider: SystemDateProvider()
            )
        )

        writer.write(value: ["key1": "value1"])
        writer.write(value: ["key2": "value2"])
        writer.write(value: ["key3": "value3"])

        XCTAssertEqual(try temporaryDirectory.files().count, 1)

        let dataBlocks = try temporaryDirectory.files()[0].readDataBlocks()
        XCTAssertEqual(dataBlocks.count, 3)
        XCTAssertEqual(dataBlocks[0].type, .event)
        XCTAssertEqual(dataBlocks[0].data, #"{"key1":"value1"}"#.utf8Data)
        XCTAssertEqual(dataBlocks[1].type, .event)
        XCTAssertEqual(dataBlocks[1].data, #"{"key2":"value2"}"#.utf8Data)
        XCTAssertEqual(dataBlocks[2].type, .event)
        XCTAssertEqual(dataBlocks[2].data, #"{"key3":"value3"}"#.utf8Data)
    }

    func testWhenForceNewBatchIsSet_itWritesDataToSeparateFiles() throws {
        let writer = FileWriter(
            orchestrator: FilesOrchestrator(
                directory: temporaryDirectory,
                performance: PerformancePreset.mockAny(),
                dateProvider: RelativeDateProvider(advancingBySeconds: 1)
            )
        )

        writer.write(value: ["key1": "value1"], forceNewBatch: true)
        writer.write(value: ["key2": "value2"], forceNewBatch: true)
        writer.write(value: ["key3": "value3"], forceNewBatch: true)

        XCTAssertEqual(try temporaryDirectory.files().count, 3)

        let dataBlocks = try temporaryDirectory.files()
            .sorted { $0.name < $1.name } // read files in their creation order
            .map { try $0.readDataBlocks() }

        XCTAssertEqual(dataBlocks[0].count, 1)
        XCTAssertEqual(dataBlocks[0][0].type, .event)
        XCTAssertEqual(dataBlocks[0][0].data, #"{"key1":"value1"}"#.utf8Data)

        XCTAssertEqual(dataBlocks[1].count, 1)
        XCTAssertEqual(dataBlocks[1][0].type, .event)
        XCTAssertEqual(dataBlocks[1][0].data, #"{"key2":"value2"}"#.utf8Data)

        XCTAssertEqual(dataBlocks[2].count, 1)
        XCTAssertEqual(dataBlocks[2][0].type, .event)
        XCTAssertEqual(dataBlocks[2][0].data, #"{"key3":"value3"}"#.utf8Data)
    }

    func testGivenErrorVerbosity_whenIndividualDataExceedsMaxWriteSize_itDropsDataAndPrintsError() throws {
        let dd = DD.mockWith(logger: CoreLoggerMock())
        defer { dd.reset() }

        // Given
        let writer = FileWriter(
            orchestrator: FilesOrchestrator(
                directory: temporaryDirectory,
                performance: StoragePerformanceMock(
                    maxFileSize: .max,
                    maxDirectorySize: .max,
                    maxFileAgeForWrite: .distantFuture,
                    minFileAgeForRead: .mockAny(),
                    maxFileAgeForRead: .mockAny(),
                    maxObjectsInFile: .max,
                    maxObjectSize: 23 // 23 bytes is enough for TLV with {"key1":"value1"} JSON
                ),
                dateProvider: SystemDateProvider()
            )
        )

        writer.write(value: ["key1": "value1"]) // will be written

        XCTAssertEqual(try temporaryDirectory.files().count, 1)
        let dataBlocks1 = try temporaryDirectory.files()[0].readDataBlocks()
        XCTAssertEqual(dataBlocks1.count, 1)
        XCTAssertEqual(dataBlocks1[0].type, .event)
        XCTAssertEqual(dataBlocks1[0].data, #"{"key1":"value1"}"#.utf8Data)

        // When
        writer.write(value: ["key2": "value3 that makes it exceed 23 bytes"]) // will be dropped

        // Then
        XCTAssertEqual(try temporaryDirectory.files().count, 1)
        let dataBlocks2 = try temporaryDirectory.files()[0].readDataBlocks()
        XCTAssertEqual(dataBlocks2.count, dataBlocks1.count) // same content as before (nothing new was written)
        XCTAssertEqual(dataBlocks2[0].type, dataBlocks1[0].type)
        XCTAssertEqual(dataBlocks2[0].data, dataBlocks1[0].data)

        XCTAssertEqual(dd.logger.errorLog?.message, "Failed to write data")
        XCTAssertEqual(dd.logger.errorLog?.error?.message, "data exceeds the maximum size of 23 bytes.")
    }

    func testGivenErrorVerbosity_whenDataCannotBeEncoded_itPrintsError() throws {
        let dd = DD.mockWith(logger: CoreLoggerMock())
        defer { dd.reset() }

        let writer = FileWriter(
            orchestrator: FilesOrchestrator(
                directory: temporaryDirectory,
                performance: PerformancePreset.mockAny(),
                dateProvider: SystemDateProvider()
            )
        )

        writer.write(value: FailingEncodableMock(errorMessage: "failed to encode `FailingEncodable`."))

        XCTAssertEqual(dd.logger.errorLog?.message, "Failed to write data")
        XCTAssertEqual(dd.logger.errorLog?.error?.message, "failed to encode `FailingEncodable`.")
    }

    func testGivenErrorVerbosity_whenIOExceptionIsThrown_itPrintsError() throws {
        let dd = DD.mockWith(logger: CoreLoggerMock())
        defer { dd.reset() }

        let writer = FileWriter(
            orchestrator: FilesOrchestrator(
                directory: temporaryDirectory,
                performance: PerformancePreset.mockAny(),
                dateProvider: SystemDateProvider()
            )
        )

        writer.write(value: ["ok"]) // will create the file
        try? temporaryDirectory.files()[0].makeReadonly()
        writer.write(value: ["won't be written"])
        try? temporaryDirectory.files()[0].makeReadWrite()

        XCTAssertEqual(dd.logger.errorLog?.message, "Failed to write data")
        XCTAssertTrue(dd.logger.errorLog!.error!.message.contains("You don’t have permission"))
    }

    /// NOTE: Test added after incident-4797
    func testWhenIOExceptionsHappenRandomly_theFileIsNeverMalformed() throws {
        let writer = FileWriter(
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
        let dataBlocks = try temporaryDirectory.files()[0].readDataBlocks()

        // Assert that data written is not malformed
        let jsonDecoder = JSONDecoder()
        let events = try dataBlocks.map { try jsonDecoder.decode(Foo.self, from: $0.data) }

        // Assert that some (including all) `Foo`s were written
        XCTAssertGreaterThan(events.count, 0)
        XCTAssertLessThanOrEqual(events.count, 300)
    }

    func testItWritesEncryptedDataToSingleFile() throws {
        // Given 
        let writer = FileWriter(
            orchestrator: FilesOrchestrator(
                directory: temporaryDirectory,
                performance: PerformancePreset.mockAny(),
                dateProvider: SystemDateProvider()
            ),
            encryption: DataEncryptionMock(
                encrypt: { _ in "foo".utf8Data }
            )
        )

        // When
        writer.write(value: ["key1": "value1"])
        writer.write(value: ["key2": "value3"])
        writer.write(value: ["key3": "value3"])

        // Then
        XCTAssertEqual(try temporaryDirectory.files().count, 1)
        let dataBlocks = try temporaryDirectory.files()[0].readDataBlocks()
        XCTAssertEqual(dataBlocks.count, 3)
        XCTAssertEqual(dataBlocks[0].type, .event)
        XCTAssertEqual(dataBlocks[0].data, "foo".utf8Data)
        XCTAssertEqual(dataBlocks[1].type, .event)
        XCTAssertEqual(dataBlocks[1].data, "foo".utf8Data)
        XCTAssertEqual(dataBlocks[2].type, .event)
        XCTAssertEqual(dataBlocks[2].data, "foo".utf8Data)
    }
}

// MARK: - Convenience

private extension File {
    func readDataBlocks() throws -> [DataBlock] {
        let reader = DataBlockReader(data: try read())
        return try reader.all()
    }
}
