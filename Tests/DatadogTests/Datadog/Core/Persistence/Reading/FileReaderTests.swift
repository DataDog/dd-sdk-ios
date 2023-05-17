/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import TestUtilities
import DatadogInternal
@testable import Datadog

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

    func testItReadsSingleBatch() throws {
        let reader = FileReader(
            orchestrator: FilesOrchestrator(
                directory: directory,
                performance: StoragePerformanceMock.readAllFiles,
                dateProvider: SystemDateProvider()
            )
        )
        _ = try directory
            .createFile(named: Date.mockAny().toFileName)
            .append(data: DataBlock(type: .event, data: "ABCD".utf8Data).serialize())

        XCTAssertEqual(try directory.files().count, 1)
        let batch = reader.readNextBatch()
        XCTAssertEqual(batch?.events, ["ABCD".utf8Data])
    }

    func testItReadsSingleEncryptedBatch() throws {
        // Given
        let data = try Array(repeating: "foo".utf8Data, count: 3)
            .map { try DataBlock(type: .event, data: $0).serialize() }
            .reduce(.init(), +)

        _ = try directory
            .createFile(named: Date.mockAny().toFileName)
            .append(data: data)

        let reader = FileReader(
            orchestrator: FilesOrchestrator(
                directory: directory,
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
        XCTAssertEqual(batch?.events, ["bar","bar","bar"].map { $0.utf8Data })
    }

    func testItMarksBatchesAsRead() throws {
        let dateProvider = RelativeDateProvider(advancingBySeconds: 60)
        let reader = FileReader(
            orchestrator: FilesOrchestrator(
                directory: directory,
                performance: StoragePerformanceMock.readAllFiles,
                dateProvider: dateProvider
            )
        )
        let file1 = try directory.createFile(named: dateProvider.now.toFileName)
        try file1.append(data: DataBlock(type: .event, data: "1".utf8Data).serialize())

        let file2 = try directory.createFile(named: dateProvider.now.toFileName)
        try file2.append(data: DataBlock(type: .event, data: "2".utf8Data).serialize())

        let file3 = try directory.createFile(named: dateProvider.now.toFileName)
        try file3.append(data: DataBlock(type: .event, data: "3".utf8Data).serialize())

        var batch: Batch
        batch = try reader.readNextBatch().unwrapOrThrow()
        XCTAssertEqual(batch.events.first, "1".utf8Data)
        reader.markBatchAsRead(batch)

        batch = try reader.readNextBatch().unwrapOrThrow()
        XCTAssertEqual(batch.events.first, "2".utf8Data)
        reader.markBatchAsRead(batch)

        batch = try reader.readNextBatch().unwrapOrThrow()
        XCTAssertEqual(batch.events.first, "3".utf8Data)
        reader.markBatchAsRead(batch)

        XCTAssertNil(reader.readNextBatch())
        XCTAssertEqual(try directory.files().count, 0)
    }
}
