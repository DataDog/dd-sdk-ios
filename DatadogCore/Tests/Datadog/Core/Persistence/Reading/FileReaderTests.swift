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

    func testItReadsBatches() async throws {
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
        let batchCount1 = await reader.readNextBatches(.max).count
        XCTAssertEqual(batchCount1, 1)
        let batch = await reader.readNextBatches(1).first

        let expected = [
            Event(data: "ABCD".utf8Data, metadata: "EFGH".utf8Data)
        ]
        XCTAssertEqual(batch?.events, expected)

        dataProvider.advance(bySeconds: .mockRandom())
        _ = try directory
            .createFile(named: dataProvider.now.toFileName)
            .append(data: data)

        XCTAssertEqual(try directory.files().count, 2)
        let batchCount2 = await reader.readNextBatches(2).count
        XCTAssertEqual(batchCount2, 2)
        let batchCount3 = await reader.readNextBatches(.max).count
        XCTAssertEqual(batchCount3, 2)
    }

    func testItReadsEncryptedBatches() async throws {
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

        let encBatchCount1 = await reader.readNextBatches(.max).count
        XCTAssertEqual(encBatchCount1, 1)
        let batch = await reader.readNextBatches(1).first

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

        let encBatchCount2 = await reader.readNextBatches(2).count
        XCTAssertEqual(encBatchCount2, 2)
        let encBatchCount3 = await reader.readNextBatches(.max).count
        XCTAssertEqual(encBatchCount3, 2)
    }

    func testItMarksBatchesAsRead() async throws {
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
        batch = try await reader.readNextBatches(1).first.unwrapOrThrow()
        XCTAssertEqual(batch.events.first, expected[0])
        await reader.markBatchAsRead(batch)

        let batches = await reader.readNextBatches(2)
        XCTAssertEqual(batches[0].events.first, expected[1])
        XCTAssertEqual(batches[1].events.first, expected[2])
        for b in batches {
            await reader.markBatchAsRead(b)
        }

        let remainingBatches = await reader.readNextBatches(1)
        XCTAssertTrue(remainingBatches.isEmpty)
        XCTAssertEqual(try directory.files().count, 0)
    }
}

extension Reader {
    func readNextBatches(_ limit: Int = .max) async -> [Batch] {
        return await readFiles(limit: limit).compactMap { readBatch(from: $0) }
    }
}
