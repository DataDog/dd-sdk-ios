/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import TestUtilities
import DatadogInternal

@testable import DatadogCore

class FileWriterTests: XCTestCase {
    lazy var directory = Directory(url: temporaryDirectory)

    override func setUp() {
        super.setUp()
        CreateTemporaryDirectory()
    }

    override func tearDown() {
        DeleteTemporaryDirectory()
        super.tearDown()
    }

    func testItWritesDataWithMetadataToSingleFileInTLVFormat() throws {
        let writer = FileWriter(
            orchestrator: FilesOrchestrator(
                directory: directory,
                performance: PerformancePreset.mockAny(),
                dateProvider: SystemDateProvider(),
                telemetry: NOPTelemetry()
            ),
            encryption: nil,
            telemetry: NOPTelemetry()
        )

        writer.write(value: ["key1": "value1"], metadata: ["meta1": "metaValue1"])
        writer.write(value: ["key2": "value2"]) // skipped metadata here
        writer.write(value: ["key3": "value3"], metadata: ["meta3": "metaValue3"])

        XCTAssertEqual(try directory.files().count, 1)
        let stream = try directory.files()[0].stream()

        let reader = DataBlockReader(input: stream)
        var block = try reader.next()
        XCTAssertEqual(block?.type, .eventMetadata)
        XCTAssertEqual(block?.data, #"{"meta1":"metaValue1"}"#.utf8Data)
        block = try reader.next()
        XCTAssertEqual(block?.type, .event)
        XCTAssertEqual(block?.data, #"{"key1":"value1"}"#.utf8Data)
        block = try reader.next()
        XCTAssertEqual(block?.type, .event)
        XCTAssertEqual(block?.data, #"{"key2":"value2"}"#.utf8Data)
        block = try reader.next()
        XCTAssertEqual(block?.type, .eventMetadata)
        XCTAssertEqual(block?.data, #"{"meta3":"metaValue3"}"#.utf8Data)
        block = try reader.next()
        XCTAssertEqual(block?.type, .event)
        XCTAssertEqual(block?.data, #"{"key3":"value3"}"#.utf8Data)
    }

    func testItWritesEncryptedDataWithMetadataToSingleFileInTLVFormat() throws {
        let writer = FileWriter(
            orchestrator: FilesOrchestrator(
                directory: directory,
                performance: PerformancePreset.mockAny(),
                dateProvider: SystemDateProvider(),
                telemetry: NOPTelemetry()
            ),
            encryption: DataEncryptionMock(
                encrypt: { data in
                    "encrypted".utf8Data + data + "encrypted".utf8Data
                }
            ),
            telemetry: NOPTelemetry()
        )

        writer.write(value: ["key1": "value1"], metadata: ["meta1": "metaValue1"])
        writer.write(value: ["key2": "value2"]) // skipped metadata here
        writer.write(value: ["key3": "value3"], metadata: ["meta3": "metaValue3"])

        XCTAssertEqual(try directory.files().count, 1)
        let stream = try directory.files()[0].stream()

        let reader = DataBlockReader(input: stream)
        var block = try reader.next()
        XCTAssertEqual(block?.type, .eventMetadata)
        XCTAssertEqual(block?.data, #"encrypted{"meta1":"metaValue1"}encrypted"#.utf8Data)
        block = try reader.next()
        XCTAssertEqual(block?.type, .event)
        XCTAssertEqual(block?.data, #"encrypted{"key1":"value1"}encrypted"#.utf8Data)
        block = try reader.next()
        XCTAssertEqual(block?.type, .event)
        XCTAssertEqual(block?.data, #"encrypted{"key2":"value2"}encrypted"#.utf8Data)
        block = try reader.next()
        XCTAssertEqual(block?.type, .eventMetadata)
        XCTAssertEqual(block?.data, #"encrypted{"meta3":"metaValue3"}encrypted"#.utf8Data)
        block = try reader.next()
        XCTAssertEqual(block?.type, .event)
        XCTAssertEqual(block?.data, #"encrypted{"key3":"value3"}encrypted"#.utf8Data)
    }

    func testItWritesDataToSingleFileInTLVFormat() throws {
        let writer = FileWriter(
            orchestrator: FilesOrchestrator(
                directory: directory,
                performance: PerformancePreset.mockAny(),
                dateProvider: SystemDateProvider(),
                telemetry: NOPTelemetry()
            ),
            encryption: nil,
            telemetry: NOPTelemetry()
        )

        writer.write(value: ["key1": "value1"])
        writer.write(value: ["key2": "value2"])
        writer.write(value: ["key3": "value3"])

        XCTAssertEqual(try directory.files().count, 1)
        let stream = try directory.files()[0].stream()

        let reader = DataBlockReader(input: stream)
        var block = try reader.next()
        XCTAssertEqual(block?.type, .event)
        XCTAssertEqual(block?.data, #"{"key1":"value1"}"#.utf8Data)
        block = try reader.next()
        XCTAssertEqual(block?.type, .event)
        XCTAssertEqual(block?.data, #"{"key2":"value2"}"#.utf8Data)
        block = try reader.next()
        XCTAssertEqual(block?.type, .event)
        XCTAssertEqual(block?.data, #"{"key3":"value3"}"#.utf8Data)
    }

    func testGivenErrorVerbosity_whenIndividualDataExceedsMaxWriteSize_itDropsDataAndPrintsError() throws {
        let dd = DD.mockWith(logger: CoreLoggerMock())
        defer { dd.reset() }

        let writer = FileWriter(
            orchestrator: FilesOrchestrator(
                directory: directory,
                performance: StoragePerformanceMock(
                    maxFileSize: .max,
                    maxDirectorySize: .max,
                    maxFileAgeForWrite: .distantFuture,
                    minFileAgeForRead: .mockAny(),
                    maxFileAgeForRead: .mockAny(),
                    maxObjectsInFile: .max,
                    maxObjectSize: 23 // 23 bytes is enough for TLV with {"key1":"value1"} JSON
                ),
                dateProvider: SystemDateProvider(),
                telemetry: NOPTelemetry()
            ),
            encryption: nil,
            telemetry: NOPTelemetry()
        )

        writer.write(value: ["key1": "value1"]) // will be written

        XCTAssertEqual(try directory.files().count, 1)
        var reader = try DataBlockReader(input: directory.files()[0].stream())
        var blocks = try XCTUnwrap(reader.all())
        XCTAssertEqual(blocks.count, 1)
        XCTAssertEqual(blocks[0].data, #"{"key1":"value1"}"#.utf8Data)

        writer.write(value: ["key2": "value3 that makes it exceed 23 bytes"]) // will be dropped

        reader = try DataBlockReader(input: directory.files()[0].stream())
        blocks = try XCTUnwrap(reader.all())
        XCTAssertEqual(blocks.count, 1) // same content as before
        XCTAssertEqual(dd.logger.errorLog?.message, "Failed to write data")
        XCTAssertEqual(dd.logger.errorLog?.error?.message, "DataBlock length exceeds limit of 23 bytes")
    }

    func testGivenErrorVerbosity_whenDataCannotBeEncoded_itPrintsError() throws {
        let dd = DD.mockWith(logger: CoreLoggerMock())
        defer { dd.reset() }

        let writer = FileWriter(
            orchestrator: FilesOrchestrator(
                directory: directory,
                performance: PerformancePreset.mockAny(),
                dateProvider: SystemDateProvider(),
                telemetry: NOPTelemetry()
            ),
            encryption: nil,
            telemetry: NOPTelemetry()
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
                directory: directory,
                performance: PerformancePreset.mockAny(),
                dateProvider: SystemDateProvider(),
                telemetry: NOPTelemetry()
            ),
            encryption: nil,
            telemetry: NOPTelemetry()
        )

        writer.write(value: ["ok"]) // will create the file
        try? directory.files()[0].makeReadonly()
        writer.write(value: ["won't be written"])
        try? directory.files()[0].makeReadWrite()

        XCTAssertEqual(dd.logger.errorLog?.message, "Failed to write data")
        XCTAssertTrue(dd.logger.errorLog!.error!.message.contains("You don’t have permission"))
    }

    /// NOTE: Test added after incident-4797
    func testWhenIOExceptionsHappenRandomly_theFileIsNeverMalformed() throws {
        let writer = FileWriter(
            orchestrator: FilesOrchestrator(
                directory: directory,
                performance: StoragePerformanceMock(
                    maxFileSize: .max,
                    maxDirectorySize: .max,
                    maxFileAgeForWrite: .distantFuture, // write to single file
                    minFileAgeForRead: .distantFuture,
                    maxFileAgeForRead: .distantFuture,
                    maxObjectsInFile: .max, // write to single file
                    maxObjectSize: .max
                ),
                dateProvider: SystemDateProvider(),
                telemetry: NOPTelemetry()
            ),
            encryption: nil,
            telemetry: NOPTelemetry()
        )

        let ioInterruptionQueue = DispatchQueue(label: "com.datadohq.file-writer-random-io")

        func randomlyInterruptIO(for file: File?) {
            ioInterruptionQueue.async { try? file?.makeReadonly() }
            ioInterruptionQueue.async { try? file?.makeReadWrite() }
        }

        struct Foo: Codable, Equatable {
            var foo = "bar"
        }

        struct Metadata: Codable, Equatable {
            var meta = "data"
        }

        let foo = Foo()
        let metadata = Metadata()

        // Write 300 of `Foo`s and interrupt writes randomly
        (0..<300).forEach { _ in
            writer.write(value: foo, metadata: metadata)
            randomlyInterruptIO(for: try? directory.files().first)
        }

        ioInterruptionQueue.sync { }

        XCTAssertEqual(try directory.files().count, 1)

        let stream = try directory.files()[0].stream()
        let blocks = try DataBlockReader(input: stream).all()

        // Assert that data written is not malformed
        let jsonDecoder = JSONDecoder()
        let eventGenerator = EventGenerator(dataBlocks: blocks)
        let events = eventGenerator.map { $0 }

        // Assert that some (including all) `Foo`s were written
        XCTAssertGreaterThan(events.count, 0)
        XCTAssertLessThanOrEqual(events.count, 300)
        for event in events {
            let actualFoo = try jsonDecoder.decode(Foo.self, from: event.data)
            XCTAssertEqual(actualFoo, foo)

            XCTAssertNotNil(event.metadata)
            let actualMetadata = try jsonDecoder.decode(Metadata.self, from: event.metadata!)
            XCTAssertEqual(actualMetadata, metadata)
        }
    }

    func testItWritesEncryptedDataToSingleFile() throws {
        // Given
        let writer = FileWriter(
            orchestrator: FilesOrchestrator(
                directory: directory,
                performance: PerformancePreset.mockAny(),
                dateProvider: SystemDateProvider(),
                telemetry: NOPTelemetry()
            ),
            encryption: DataEncryptionMock(
                encrypt: { _ in "foo".utf8Data }
            ),
            telemetry: NOPTelemetry()
        )

        // When
        writer.write(value: ["key1": "value1"], metadata: ["meta1": "metaValue1"])
        writer.write(value: ["key2": "value3"])
        writer.write(value: ["key3": "value3"], metadata: ["meta3": "metaValue3"])

        // Then
        XCTAssertEqual(try directory.files().count, 1)
        let stream = try directory.files()[0].stream()

        let reader = DataBlockReader(input: stream)

        var block = try reader.next()
        XCTAssertEqual(block?.type, .eventMetadata)
        XCTAssertEqual(block?.data, "foo".utf8Data)

        block = try reader.next()
        XCTAssertEqual(block?.type, .event)
        XCTAssertEqual(block?.data, "foo".utf8Data)

        block = try reader.next()
        XCTAssertEqual(block?.type, .event)
        XCTAssertEqual(block?.data, "foo".utf8Data)

        block = try reader.next()
        XCTAssertEqual(block?.type, .eventMetadata)
        XCTAssertEqual(block?.data, "foo".utf8Data)

        block = try reader.next()
        XCTAssertEqual(block?.type, .event)
        XCTAssertEqual(block?.data, "foo".utf8Data)
    }
}
