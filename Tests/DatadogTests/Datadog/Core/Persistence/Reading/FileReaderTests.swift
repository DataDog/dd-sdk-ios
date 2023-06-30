/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
@testable import Datadog

class FileReaderTests: XCTestCase {
    override func setUp() {
        super.setUp()
        temporaryDirectory.create()
    }

    override func tearDown() {
        temporaryDirectory.delete()
        super.tearDown()
    }

    func testItReadsSingleBatch() throws {
        let reader = FileReader(
            orchestrator: FilesOrchestrator(
                directory: temporaryDirectory,
                performance: StoragePerformanceMock.readAllFiles,
                dateProvider: SystemDateProvider()
            )
        )
        let dataBlocks = [
            DataBlock(type: .eventMetadata, data: "EFGH".utf8Data),
            DataBlock(type: .event, data: "ABCD".utf8Data)
        ]
        let data = try dataBlocks
            .map { try $0.serialize() }
            .reduce(.init(), +)
        _ = try temporaryDirectory
            .createFile(named: Date.mockAny().toFileName)
            .append(data: data)

        XCTAssertEqual(try temporaryDirectory.files().count, 1)
        let batch = reader.readNextBatch()

        let expected = [
            Event(data: "ABCD".utf8Data, metadata: "EFGH".utf8Data)
        ]
        XCTAssertEqual(batch?.events, expected)
    }

    func testItReadsSingleEncryptedBatch() throws {
        // Given
        let dataBlocks = [
            DataBlock(type: .eventMetadata, data: "foo".utf8Data),
            DataBlock(type: .event, data: "foo".utf8Data),
            DataBlock(type: .event, data: "foo".utf8Data),
            DataBlock(type: .eventMetadata, data: "foo".utf8Data),
            DataBlock(type: .event, data: "foo".utf8Data)
        ]
        let data = try dataBlocks
            .map { Data(try $0.serialize()) }
            .reduce(.init(), +)

        _ = try temporaryDirectory
            .createFile(named: Date.mockAny().toFileName)
            .append(data: data)

        let reader = FileReader(
            orchestrator: FilesOrchestrator(
                directory: temporaryDirectory,
                performance: StoragePerformanceMock.readAllFiles,
                dateProvider: SystemDateProvider()
            ),
            encryption: DataEncryptionMock(
                decrypt: { _ in "bar".utf8Data }
            )
        )

        // When
        let batch = reader.readNextBatch()

        // Then
        let expected = [
            Event(data: "bar".utf8Data, metadata: "bar".utf8Data),
            Event(data: "bar".utf8Data, metadata: nil),
            Event(data: "bar".utf8Data, metadata: "bar".utf8Data)
        ]
        XCTAssertEqual(batch?.events, expected)
    }

    func testItMarksBatchesAsRead() throws {
        let dateProvider = RelativeDateProvider(advancingBySeconds: 60)
        let reader = FileReader(
            orchestrator: FilesOrchestrator(
                directory: temporaryDirectory,
                performance: StoragePerformanceMock.readAllFiles,
                dateProvider: dateProvider
            )
        )
        let file1 = try temporaryDirectory.createFile(named: dateProvider.now.toFileName)
        try file1.append(data: DataBlock(type: .eventMetadata, data: "2".utf8Data).serialize())
        try file1.append(data: DataBlock(type: .event, data: "1".utf8Data).serialize())

        let file2 = try temporaryDirectory.createFile(named: dateProvider.now.toFileName)
        try file2.append(data: DataBlock(type: .event, data: "2".utf8Data).serialize())

        let file3 = try temporaryDirectory.createFile(named: dateProvider.now.toFileName)
        try file3.append(data: DataBlock(type: .eventMetadata, data: "4".utf8Data).serialize())
        try file3.append(data: DataBlock(type: .event, data: "3".utf8Data).serialize())

        let expected = [
            Event(data: "1".utf8Data, metadata: "2".utf8Data),
            Event(data: "2".utf8Data, metadata: nil),
            Event(data: "3".utf8Data, metadata: "4".utf8Data)
        ]

        var batch: Batch
        batch = try reader.readNextBatch().unwrapOrThrow()
        XCTAssertEqual(batch.events.first, expected[0])
        reader.markBatchAsRead(batch)

        batch = try reader.readNextBatch().unwrapOrThrow()
        XCTAssertEqual(batch.events.first, expected[1])
        reader.markBatchAsRead(batch)

        batch = try reader.readNextBatch().unwrapOrThrow()
        XCTAssertEqual(batch.events.first, expected[2])
        reader.markBatchAsRead(batch)

        XCTAssertNil(reader.readNextBatch())
        XCTAssertEqual(try temporaryDirectory.files().count, 0)
    }
}
