/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import TestUtilities
import DatadogInternal
@testable import DatadogCore

class FilesOrchestratorTests: XCTestCase {
    private let performance: PerformancePreset = .mockRandom()

    override func setUp() {
        super.setUp()
        CreateTemporaryDirectory()
    }

    override func tearDown() {
        DeleteTemporaryDirectory()
        super.tearDown()
    }

    /// Configures `FilesOrchestrator` under tests.
    private func configureOrchestrator(using dateProvider: DateProvider) -> FilesOrchestrator {
        return FilesOrchestrator(
            directory: .init(url: temporaryDirectory),
            performance: performance,
            dateProvider: dateProvider,
            telemetry: NOPTelemetry()
        )
    }

    // MARK: - Writable file tests

    func testWhenWritableFileIsObtainedFirstTime_itCreatesNewFile() throws {
        let dateProvider = RelativeDateProvider()
        let orchestrator = configureOrchestrator(using: dateProvider)

        _ = try orchestrator.getWritableFile(writeSize: 1)

        XCTAssertEqual(try orchestrator.directory.files().count, 1)
        XCTAssertNotNil(try orchestrator.directory.file(named: dateProvider.now.toFileName))
    }

    func testWhenWritableFileIsObtainedAnotherTime_itReusesSameFile() throws {
        let orchestrator = configureOrchestrator(using: RelativeDateProvider(advancingBySeconds: 0.001))
        let file1 = try orchestrator.getWritableFile(writeSize: 1)

        let file2 = try orchestrator.getWritableFile(writeSize: 1)

        XCTAssertEqual(try orchestrator.directory.files().count, 1)
        XCTAssertEqual(file1.name, file2.name)
    }

    func testWhenSameWritableFileWasUsedMaxNumberOfTimes_itCreatesNewFile() throws {
        let orchestrator = configureOrchestrator(using: RelativeDateProvider(advancingBySeconds: 0.001))
        var previousFile: WritableFile = try orchestrator.getWritableFile(writeSize: 1) // first use of a new file
        var nextFile: WritableFile

        for _ in (0..<5) {
            for _ in (0 ..< performance.maxObjectsInFile).dropLast() { // skip first use
                nextFile = try orchestrator.getWritableFile(writeSize: 1)
                XCTAssertEqual(nextFile.name, previousFile.name, "It should reuse the file \(performance.maxObjectsInFile) times")
                previousFile = nextFile
            }

            nextFile = try orchestrator.getWritableFile(writeSize: 1) // first use of a new file
            XCTAssertNotEqual(nextFile.name, previousFile.name, "It should create a new file when previous one is used \(performance.maxObjectsInFile) times")
            previousFile = nextFile
        }
    }

    func testWhenWritableFileHasNoEnoughSpaceLeft_itCreatesNewFile() throws {
        let orchestrator = configureOrchestrator(using: RelativeDateProvider(advancingBySeconds: 0.001))
        let chunkedData: [Data] = .mockChunksOf(
            totalSize: performance.maxFileSize,
            maxChunkSize: performance.maxObjectSize
        )

        let file1 = try orchestrator.getWritableFile(writeSize: performance.maxObjectSize)
        try chunkedData.forEach { chunk in try file1.append(data: chunk) }

        let file2 = try orchestrator.getWritableFile(writeSize: 1)
        XCTAssertNotEqual(file1.name, file2.name)
    }

    func testWhenWritableFileIsTooOld_itCreatesNewFile() throws {
        let dateProvider = RelativeDateProvider()
        let orchestrator = configureOrchestrator(using: dateProvider)
        let file1 = try orchestrator.getWritableFile(writeSize: 1)

        dateProvider.advance(bySeconds: 1 + performance.maxFileAgeForWrite)

        let file2 = try orchestrator.getWritableFile(writeSize: 1)
        XCTAssertNotEqual(file1.name, file2.name)
    }

    func testWhenWritableFileWasDeleted_itCreatesNewFile() throws {
        let orchestrator = configureOrchestrator(using: RelativeDateProvider(advancingBySeconds: 0.001))
        let file1 = try orchestrator.getWritableFile(writeSize: 1)

        try orchestrator.directory.files().forEach { try $0.delete() }

        let file2 = try orchestrator.getWritableFile(writeSize: 1)
        XCTAssertNotEqual(file1.name, file2.name)
    }

    /// This test makes sure that if SDK is used by multiple processes simultaneously, each `FileOrchestrator` works on a separate writable file.
    /// It is important when SDK is used by iOS App and iOS App Extension at the same time.
    func testWhenRequestedFirstTime_eachOrchestratorInstanceCreatesNewWritableFile() throws {
        let orchestrator1 = configureOrchestrator(using: RelativeDateProvider())
        let orchestrator2 = configureOrchestrator(
            using: RelativeDateProvider(startingFrom: Date().secondsAgo(0.01)) // simulate time difference
        )

        _ = try orchestrator1.getWritableFile(writeSize: 1)
        XCTAssertEqual(try orchestrator1.directory.files().count, 1)

        _ = try orchestrator2.getWritableFile(writeSize: 1)
        XCTAssertEqual(try orchestrator2.directory.files().count, 2)
    }

    func testWhenFilesDirectorySizeIsBig_itKeepsItUnderLimit_byRemovingOldestFilesFirst() throws {
        let oneMB = 1.MB.asUInt64()

        let orchestrator = FilesOrchestrator(
            directory: .init(url: temporaryDirectory),
            performance: StoragePerformanceMock(
                maxFileSize: oneMB, // 1MB
                maxDirectorySize: 3 * oneMB, // 3MB,
                maxFileAgeForWrite: .distantFuture,
                minFileAgeForRead: .mockAny(),
                maxFileAgeForRead: .mockAny(),
                maxObjectsInFile: 1, // create new file each time
                maxObjectSize: .max
            ),
            dateProvider: RelativeDateProvider(advancingBySeconds: 1),
            telemetry: NOPTelemetry()
        )

        // write 1MB to first file (1MB of directory size in total)
        let file1 = try orchestrator.getWritableFile(writeSize: oneMB)
        try file1.append(data: .mock(ofSize: oneMB))

        // write 1MB to second file (2MB of directory size in total)
        let file2 = try orchestrator.getWritableFile(writeSize: oneMB)
        try file2.append(data: .mock(ofSize: oneMB))

        // write 1MB to third file (3MB of directory size in total)
        let file3 = try orchestrator.getWritableFile(writeSize: oneMB + 1) // +1 byte to exceed the limit
        try file3.append(data: .mock(ofSize: oneMB + 1))

        XCTAssertEqual(try orchestrator.directory.files().count, 3)

        // At this point, directory reached its maximum size.
        // Asking for the next file should purge the oldest one.
        let file4 = try orchestrator.getWritableFile(writeSize: oneMB)
        XCTAssertEqual(try orchestrator.directory.files().count, 3)
        XCTAssertNil(try? orchestrator.directory.file(named: file1.name))
        try file4.append(data: .mock(ofSize: oneMB + 1))

        _ = try orchestrator.getWritableFile(writeSize: oneMB)
        XCTAssertEqual(try orchestrator.directory.files().count, 3)
        XCTAssertNil(try? orchestrator.directory.file(named: file2.name))
    }

    func testWhenNewWritableFileIsObtained_itAlwaysCreatesNewFile() throws {
        let orchestrator = configureOrchestrator(using: RelativeDateProvider(advancingBySeconds: 0.001))

        let file1 = try orchestrator.getNewWritableFile(writeSize: 1)
        let file2 = try orchestrator.getNewWritableFile(writeSize: 1)
        let file3 = try orchestrator.getNewWritableFile(writeSize: 1)

        XCTAssertEqual(try orchestrator.directory.files().count, 3)
        XCTAssertNotEqual(file1.name, file2.name)
        XCTAssertNotEqual(file2.name, file3.name)
        XCTAssertNotEqual(file3.name, file1.name)
    }

    // MARK: - Readable file tests

    func testGivenNoReadableFiles_whenObtainingFile_itReturnsNil() {
        let dateProvider = RelativeDateProvider()

        let orchestrator = configureOrchestrator(using: dateProvider)
        dateProvider.advance(bySeconds: 1 + performance.minFileAgeForRead)

        XCTAssertTrue(orchestrator.getReadableFiles().isEmpty)
    }

    func testWhenReadableFileIsOldEnough_itReturnsFile() throws {
        let dateProvider = RelativeDateProvider()
        let orchestrator = configureOrchestrator(using: dateProvider)
        let file = try orchestrator.directory.createFile(named: dateProvider.now.toFileName)

        dateProvider.advance(bySeconds: 1 + performance.minFileAgeForRead)

        XCTAssertEqual(orchestrator.getReadableFiles().first?.name, file.name)
    }

    func testWhenReadableFileIsNotOldEnough_itReturnsNil() throws {
        let dateProvider = RelativeDateProvider()
        let orchestrator = configureOrchestrator(using: dateProvider)
        _ = try orchestrator.directory.createFile(named: dateProvider.now.toFileName)

        dateProvider.advance(bySeconds: 0.5 * performance.minFileAgeForRead)

        XCTAssertTrue(orchestrator.getReadableFiles().isEmpty)
    }

    func testWhenThereAreMultipleReadableFiles_itReturnsOldestFile() throws {
        let dateProvider = RelativeDateProvider(advancingBySeconds: 1)
        let orchestrator = configureOrchestrator(using: dateProvider)

        let fileNames = (0..<4).map { _ in dateProvider.now.toFileName }
        try fileNames.forEach { fileName in _ = try orchestrator.directory.createFile(named: fileName) }

        dateProvider.advance(bySeconds: 1 + performance.minFileAgeForRead)
        XCTAssertEqual(orchestrator.getReadableFiles().first?.name, fileNames[0])
        try orchestrator.directory.file(named: fileNames[0]).delete()
        XCTAssertEqual(orchestrator.getReadableFiles().first?.name, fileNames[1])
        try orchestrator.directory.file(named: fileNames[1]).delete()
        XCTAssertEqual(orchestrator.getReadableFiles().first?.name, fileNames[2])
        try orchestrator.directory.file(named: fileNames[2]).delete()
        XCTAssertEqual(orchestrator.getReadableFiles().first?.name, fileNames[3])
        try orchestrator.directory.file(named: fileNames[3]).delete()
        XCTAssertTrue(orchestrator.getReadableFiles().isEmpty)
    }

    func testsWhenThereAreMultipleReadableFiles_itReturnsFileByExcludingCertainNames() throws {
        let dateProvider = RelativeDateProvider(advancingBySeconds: 1)
        let orchestrator = configureOrchestrator(using: dateProvider)

        let fileNames = (0..<4).map { _ in dateProvider.now.toFileName }
        try fileNames.forEach { fileName in _ = try orchestrator.directory.createFile(named: fileName) }

        dateProvider.advance(bySeconds: 1 + performance.minFileAgeForRead)
        XCTAssertEqual(
            orchestrator.getReadableFiles(excludingFilesNamed: Set(fileNames[0...2])).first?.name,
            fileNames[3]
        )
    }

    func testWhenReadableFileIsTooOld_itGetsDeleted() throws {
        let dateProvider = RelativeDateProvider()
        let orchestrator = configureOrchestrator(using: dateProvider)
        _ = try orchestrator.directory.createFile(named: dateProvider.now.toFileName)

        dateProvider.advance(bySeconds: 2 * performance.maxFileAgeForRead)

        XCTAssertNil(orchestrator.getReadableFiles())
        XCTAssertEqual(try orchestrator.directory.files().count, 0)
    }

    // MARK: - Deleting Files

    func testItDeletesReadableFile() throws {
        let dateProvider = RelativeDateProvider()
        let orchestrator = configureOrchestrator(using: dateProvider)
        _ = try orchestrator.directory.createFile(named: dateProvider.now.toFileName)

        dateProvider.advance(bySeconds: 1 + performance.minFileAgeForRead)

        let readableFile = try orchestrator.getReadableFiles().first.unwrapOrThrow()
        XCTAssertEqual(try orchestrator.directory.files().count, 1)
        orchestrator.delete(readableFile: readableFile)
        XCTAssertEqual(try orchestrator.directory.files().count, 0)
    }

    // MARK: - File names tests

    // swiftlint:disable number_separator
    func testItTurnsFileNameIntoFileCreationDate() {
        XCTAssertEqual(fileNameFrom(fileCreationDate: Date(timeIntervalSinceReferenceDate: 0)), "0")
        XCTAssertEqual(fileNameFrom(fileCreationDate: Date(timeIntervalSinceReferenceDate: 123456)), "123456000")
        XCTAssertEqual(fileNameFrom(fileCreationDate: Date(timeIntervalSinceReferenceDate: 123456.7)), "123456700")
        XCTAssertEqual(fileNameFrom(fileCreationDate: Date(timeIntervalSinceReferenceDate: 123456.78)), "123456780")
        XCTAssertEqual(fileNameFrom(fileCreationDate: Date(timeIntervalSinceReferenceDate: 123456.789)), "123456789")

        // microseconds rounding
        XCTAssertEqual(fileNameFrom(fileCreationDate: Date(timeIntervalSinceReferenceDate: 123456.1111)), "123456111")
        XCTAssertEqual(fileNameFrom(fileCreationDate: Date(timeIntervalSinceReferenceDate: 123456.1115)), "123456112")
        XCTAssertEqual(fileNameFrom(fileCreationDate: Date(timeIntervalSinceReferenceDate: 123456.1119)), "123456112")

        // overflows
        let maxDate = Date(timeIntervalSinceReferenceDate: TimeInterval.greatestFiniteMagnitude)
        let minDate = Date(timeIntervalSinceReferenceDate: -TimeInterval.greatestFiniteMagnitude)
        XCTAssertEqual(fileNameFrom(fileCreationDate: maxDate), "0")
        XCTAssertEqual(fileNameFrom(fileCreationDate: minDate), "0")
    }

    func testItTurnsFileCreationDateIntoFileName() {
        XCTAssertEqual(fileCreationDateFrom(fileName: "0"), Date(timeIntervalSinceReferenceDate: 0))
        XCTAssertEqual(fileCreationDateFrom(fileName: "123456000"), Date(timeIntervalSinceReferenceDate: 123456))
        XCTAssertEqual(fileCreationDateFrom(fileName: "123456700"), Date(timeIntervalSinceReferenceDate: 123456.7))
        XCTAssertEqual(fileCreationDateFrom(fileName: "123456780"), Date(timeIntervalSinceReferenceDate: 123456.78))
        XCTAssertEqual(fileCreationDateFrom(fileName: "123456789"), Date(timeIntervalSinceReferenceDate: 123456.789))

        // ignores invalid names
        let invalidFileName = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
        XCTAssertEqual(fileCreationDateFrom(fileName: invalidFileName), Date(timeIntervalSinceReferenceDate: 0))
    }
    // swiftlint:enable number_separator
}

extension FilesOrchestrator {
    func getReadableFiles(
        context: DatadogContext
    ) -> [ReadableFile] {
        getReadableFiles(excludingFilesNamed: [])
    }
}
