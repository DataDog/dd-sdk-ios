/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import TestUtilities
import DatadogInternal
@testable import DatadogCore

class FileReaderTests: XCTestCase {
    lazy var directory = Directory(url: temporaryDirectory)

    override func setUp() {
        super.setUp()
        CreateTemporaryDirectory()
    }

    override func tearDown() {
        DeleteTemporaryDirectory()
        super.tearDown()
    }

    func testItReadsBatches() throws {
        let reader = FileReader(
            orchestrator: FilesOrchestrator(
                directory: directory,
                performance: StoragePerformanceMock.readAllFiles,
                dateProvider: SystemDateProvider(),
                telemetry: NOPTelemetry()
            ),
            encryption: nil,
            telemetry: NOPTelemetry()
        )
        let dataProvider = RelativeDateProvider()
        let dataBlocks = [
            BatchDataBlock(type: .eventMetadata, data: "EFGH".utf8Data),
            BatchDataBlock(type: .event, data: "ABCD".utf8Data)
        ]
        let data = try dataBlocks
            .map { try $0.serialize() }
            .reduce(.init(), +)
        _ = try directory
            .createFile(named: dataProvider.now.toFileName)
            .append(data: data)

        XCTAssertEqual(try directory.files().count, 1)
        XCTAssertEqual(reader.readNextBatches(.max).count, 1)
        let batch = reader.readNextBatches(1).first

        let expected = [
            Event(data: "ABCD".utf8Data, metadata: "EFGH".utf8Data)
        ]
        XCTAssertEqual(batch?.events, expected)

        dataProvider.advance(bySeconds: .mockRandom())
        _ = try directory
            .createFile(named: dataProvider.now.toFileName)
            .append(data: data)

        XCTAssertEqual(try directory.files().count, 2)
        XCTAssertEqual(reader.readNextBatches(2).count, 2)
        XCTAssertEqual(reader.readNextBatches(.max).count, 2)
    }

    func testItReadsEncryptedBatches() throws {
        let dataBlocks = [
            BatchDataBlock(type: .eventMetadata, data: "foo".utf8Data),
            BatchDataBlock(type: .event, data: "foo".utf8Data),
            BatchDataBlock(type: .event, data: "foo".utf8Data),
            BatchDataBlock(type: .eventMetadata, data: "foo".utf8Data),
            BatchDataBlock(type: .event, data: "foo".utf8Data)
        ]
        let data = try dataBlocks
            .map { Data(try $0.serialize()) }
            .reduce(.init(), +)

        let dataProvider = RelativeDateProvider()

        _ = try directory
            .createFile(named: dataProvider.now.toFileName)
            .append(data: data)

        let reader = FileReader(
            orchestrator: FilesOrchestrator(
                directory: directory,
                performance: StoragePerformanceMock.readAllFiles,
                dateProvider: SystemDateProvider(),
                telemetry: NOPTelemetry()
            ),
            encryption: DataEncryptionMock(
                decrypt: { _ in "bar".utf8Data }
            ),
            telemetry: NOPTelemetry()
        )

        XCTAssertEqual(reader.readNextBatches(.max).count, 1)
        let batch = reader.readNextBatches(1).first

        let expected = [
            Event(data: "bar".utf8Data, metadata: "bar".utf8Data),
            Event(data: "bar".utf8Data, metadata: nil),
            Event(data: "bar".utf8Data, metadata: "bar".utf8Data)
        ]
        XCTAssertEqual(batch?.events, expected)

        dataProvider.advance(bySeconds: .mockRandom())
        _ = try directory
            .createFile(named: dataProvider.now.toFileName)
            .append(data: data)

        XCTAssertEqual(reader.readNextBatches(2).count, 2)
        XCTAssertEqual(reader.readNextBatches(.max).count, 2)
    }

    func testItMarksBatchesAsRead() throws {
        let dateProvider = RelativeDateProvider(advancingBySeconds: 60)
        let reader = FileReader(
            orchestrator: FilesOrchestrator(
                directory: directory,
                performance: StoragePerformanceMock.readAllFiles,
                dateProvider: dateProvider,
                telemetry: NOPTelemetry()
            ),
            encryption: nil,
            telemetry: NOPTelemetry()
        )
        let file1 = try directory.createFile(named: dateProvider.now.toFileName)
        try file1.append(data: BatchDataBlock(type: .eventMetadata, data: "2".utf8Data).serialize())
        try file1.append(data: BatchDataBlock(type: .event, data: "1".utf8Data).serialize())

        let file2 = try directory.createFile(named: dateProvider.now.toFileName)
        try file2.append(data: BatchDataBlock(type: .event, data: "2".utf8Data).serialize())

        let file3 = try directory.createFile(named: dateProvider.now.toFileName)
        try file3.append(data: BatchDataBlock(type: .eventMetadata, data: "4".utf8Data).serialize())
        try file3.append(data: BatchDataBlock(type: .event, data: "3".utf8Data).serialize())

        let expected = [
            Event(data: "1".utf8Data, metadata: "2".utf8Data),
            Event(data: "2".utf8Data, metadata: nil),
            Event(data: "3".utf8Data, metadata: "4".utf8Data)
        ]

        let batch: Batch
        batch = try reader.readNextBatches(1).first.unwrapOrThrow()
        XCTAssertEqual(batch.events.first, expected[0])
        reader.markFileAsRead(batch.file)

        let batches = reader.readNextBatches(2)
        XCTAssertEqual(batches[0].events.first, expected[1])
        XCTAssertEqual(batches[1].events.first, expected[2])
        batches.forEach { reader.markFileAsRead($0.file) }

        XCTAssertTrue(reader.readNextBatches(1).isEmpty)
        XCTAssertEqual(try directory.files().count, 0)
    }

    // MARK: - Batches holding no event

    func testGivenEmptyFile_whenReadingBatch_itDropsTheFile() throws {
        let telemetry = TelemetryMock()
        let reader = makeReader(telemetry: telemetry)
        let file = try directory.createFile(named: Date().toFileName)

        XCTAssertNil(reader.readBatch(from: file))
        XCTAssertEqual(try directory.files().count, 0, "The file should be deleted, not read again")
        XCTAssertEqual(telemetry.messages.firstError()?.message, "(rum) Dropping batch with no event")

        let metric = try XCTUnwrap(telemetry.messages.firstMetric(named: "Batch Deleted"))
        XCTAssertEqual(metric.attributes["batch_removal_reason"] as? String, "invalid")
    }

    func testGivenFileWithoutEventBlock_whenReadingBatch_itDropsTheFile() throws {
        let reader = makeReader()
        let file = try directory.createFile(named: Date().toFileName)
        try file.append(data: BatchDataBlock(type: .eventMetadata, data: "EFGH".utf8Data).serialize())

        XCTAssertNil(reader.readBatch(from: file))
        XCTAssertEqual(try directory.files().count, 0, "The file should be deleted, not read again")
    }

    func testGivenFileWithTruncatedBlock_whenReadingBatch_itKeepsTheFile() throws {
        let telemetry = TelemetryMock()
        let reader = makeReader(telemetry: telemetry)
        let file = try directory.createFile(named: Date().toFileName)
        let block = try BatchDataBlock(type: .event, data: "ABCD".utf8Data).serialize()
        try file.append(data: block.dropLast()) // truncated mid-block

        XCTAssertNil(reader.readBatch(from: file))
        XCTAssertEqual(try directory.files().count, 1, "A short read should not delete the file")
        XCTAssertTrue(telemetry.messages.firstError()?.message.contains("expected 4 bytes but got 3") == true)
    }

    func testGivenFileWithOversizedBlock_whenReadingBatch_itDropsTheFile() throws {
        let reader = makeReader(
            performance: StoragePerformanceMock(
                maxFileSize: .max,
                maxDirectorySize: .max,
                maxFileAgeForWrite: .distantFuture,
                minFileAgeForRead: .mockAny(),
                maxFileAgeForRead: .distantFuture,
                maxObjectsInFile: .max,
                maxObjectSize: 2 // smaller than the 4-byte event below
            )
        )
        let file = try directory.createFile(named: Date().toFileName)
        try file.append(data: BatchDataBlock(type: .event, data: "ABCD".utf8Data).serialize())

        XCTAssertNil(reader.readBatch(from: file))
        XCTAssertEqual(try directory.files().count, 0, "The file should be deleted, not read again")
    }

    func testGivenFileWhoseBlocksCannotBeDecrypted_whenReadingBatch_itDropsTheFile() throws {
        let dd = DD.mockWith(logger: CoreLoggerMock())
        defer { dd.reset() }
        let telemetry = TelemetryMock()
        let reader = makeReader(
            encryption: DataEncryptionMock(decrypt: { _ in throw ErrorMock("sensitive customer data") }),
            telemetry: telemetry
        )
        let file = try directory.createFile(named: Date().toFileName)
        try file.append(data: BatchDataBlock(type: .event, data: "ABCD".utf8Data).serialize())

        XCTAssertNil(reader.readBatch(from: file))
        XCTAssertEqual(try directory.files().count, 0, "The file should not block newer batches")

        let error = try XCTUnwrap(telemetry.messages.firstError())
        XCTAssertEqual(error.message, "(rum) Failed to decrypt data")
        XCTAssertEqual(dd.logger.errorLog?.message, "(rum) Failed to decrypt data")
        XCTAssertNil(dd.logger.errorLog?.error)
        let metric = try XCTUnwrap(telemetry.messages.firstMetric(named: "Batch Deleted"))
        XCTAssertEqual(metric.attributes["batch_removal_reason"] as? String, "invalid")
    }

    func testGivenUndecryptableMetadata_whenReadingBatch_itKeepsTheEvent() throws {
        let reader = makeReader(encryption: DataEncryptionMock(decrypt: { data in
            if data == "metadata".utf8Data {
                throw ErrorMock("decryption key unavailable")
            }
            return data
        }))
        let file = try directory.createFile(named: Date().toFileName)
        try file.append(data: BatchDataBlock(type: .eventMetadata, data: "metadata".utf8Data).serialize())
        try file.append(data: BatchDataBlock(type: .event, data: "event".utf8Data).serialize())

        let batch = try XCTUnwrap(reader.readBatch(from: file))
        XCTAssertEqual(batch.events, [Event(data: "event".utf8Data, metadata: nil)])
        XCTAssertEqual(try directory.files().count, 1)
    }

    func testGivenUndecryptableOldFiles_whenReadingBatches_itSelectsNewerFile() throws {
        let reader = makeReader(encryption: DataEncryptionMock(decrypt: { data in
            if data != "new".utf8Data {
                throw ErrorMock("decryption key unavailable")
            }
            return data
        }))
        let now = Date()
        let firstOldFile = try directory.createFile(named: now.addingTimeInterval(-3).toFileName)
        let secondOldFile = try directory.createFile(named: now.addingTimeInterval(-2).toFileName)
        let newFile = try directory.createFile(named: now.addingTimeInterval(-1).toFileName)
        try firstOldFile.append(data: BatchDataBlock(type: .event, data: "old-1".utf8Data).serialize())
        try secondOldFile.append(data: BatchDataBlock(type: .event, data: "old-2".utf8Data).serialize())
        try newFile.append(data: BatchDataBlock(type: .event, data: "new".utf8Data).serialize())

        XCTAssertTrue(reader.readNextBatches(2).isEmpty)
        XCTAssertEqual(try directory.files().map(\.name), [newFile.name])
        XCTAssertEqual(reader.readNextBatches(2).flatMap(\.events), [Event(data: "new".utf8Data)])
    }

    // MARK: - Helpers

    private func makeReader(
        performance: StoragePerformancePreset = StoragePerformanceMock.readAllFiles,
        encryption: DataEncryption? = nil,
        telemetry: Telemetry = NOPTelemetry()
    ) -> FileReader {
        FileReader(
            orchestrator: FilesOrchestrator(
                directory: directory,
                performance: performance,
                dateProvider: SystemDateProvider(),
                telemetry: telemetry,
                metricsData: .init(
                    trackName: "rum",
                    consentLabel: .mockAny(),
                    uploaderPerformance: UploadPerformanceMock.noOp,
                    backgroundTasksEnabled: .mockAny()
                )
            ),
            encryption: encryption,
            telemetry: telemetry
        )
    }
}

extension Reader {
    func readNextBatches(_ limit: Int = .max) -> [Batch] {
        return readFiles(limit: limit).compactMap { readBatch(from: $0) }
    }
}
