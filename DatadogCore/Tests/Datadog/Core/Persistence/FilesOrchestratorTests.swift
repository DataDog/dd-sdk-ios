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
        let dateProvider = DateProviderMock()
        let orchestrator = configureOrchestrator(using: dateProvider)
        var previousFile: WritableFile = try orchestrator.getWritableFile(writeSize: 1) // first use of a new file
        var nextFile: WritableFile

        for _ in (0..<5) {
            for _ in (0 ..< performance.maxObjectsInFile).dropLast() { // skip first use
                dateProvider.now.addTimeInterval(0.001)
                nextFile = try orchestrator.getWritableFile(writeSize: 1)
                XCTAssertEqual(nextFile.name, previousFile.name, "It should reuse the file \(performance.maxObjectsInFile) times")
                previousFile = nextFile
            }

            dateProvider.now.addTimeInterval(0.001)
            nextFile = try orchestrator.getWritableFile(writeSize: 1) // first use of a new file
            XCTAssertNotEqual(nextFile.name, previousFile.name, "It should create a new file when previous one is used \(performance.maxObjectsInFile) times")
            previousFile = nextFile
        }
    }

    func testWhenWritableFileHasNoEnoughSpaceLeft_itCreatesNewFile() throws {
        let orchestrator = configureOrchestrator(using: RelativeDateProvider(advancingBySeconds: 0.001))
        let chunkedData: [Data] = .mockChunksOf(
            totalSize: performance.maxFileSize.asUInt64(),
            maxChunkSize: performance.maxObjectSize.asUInt64()
        )

        let file1 = try orchestrator.getWritableFile(writeSize: performance.maxObjectSize.asUInt64())
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
                maxFileSize: oneMB.asUInt32(), // 1MB
                maxDirectorySize: (3 * oneMB).asUInt32(), // 3MB,
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

    func testWhenFileAlreadyExists_itWaitsAndCreatesFileWithNextName() throws {
        let date: Date = .mockDecember15th2019At10AMUTC()
        let dateProvider = RelativeDateProvider(
            startingFrom: date,
            advancingBySeconds: FilesOrchestrator.Constants.fileNamePrecision
        )

        // Given: A file with the current time already exists
        let orchestrator = configureOrchestrator(using: dateProvider)
        let existingFile = try orchestrator.directory.createFile(named: fileNameFrom(fileCreationDate: date))

        // When: The orchestrator attempts to create a new file with the next available name
        let nextFile = try orchestrator.getWritableFile(writeSize: 1)

        // Then
        let existingFileDate = fileCreationDateFrom(fileName: existingFile.name)
        let nextFileDate = fileCreationDateFrom(fileName: nextFile.name)
        XCTAssertNotEqual(existingFile.name, nextFile.name, "The new file should have a different name than the existing file")
        XCTAssertGreaterThanOrEqual(
            nextFileDate.timeIntervalSince(existingFileDate),
            FilesOrchestrator.Constants.fileNamePrecision,
            "The timestamp of the new file should be at least `fileNamePrecision` later than the existing file"
        )
    }

    // MARK: - Readable file tests

    func testGivenNoReadableFiles_whenObtainingFiles_itReturnsEmpty() {
        let dateProvider = RelativeDateProvider()

        let orchestrator = configureOrchestrator(using: dateProvider)
        dateProvider.advance(bySeconds: 1 + performance.minFileAgeForRead)

        XCTAssertTrue(orchestrator.getReadableFiles().isEmpty)
    }

    func testWhenReadableFileIsOldEnough_itReturnsFiles() throws {
        let dateProvider = RelativeDateProvider()
        let orchestrator = configureOrchestrator(using: dateProvider)
        _ = try orchestrator.directory.createFile(named: dateProvider.now.toFileName)

        dateProvider.advance(bySeconds: 1 + performance.minFileAgeForRead)

        XCTAssertGreaterThan(orchestrator.getReadableFiles().count, 0)
    }

    func testWhenReadableFilesAreNotOldEnough_itReturnsEmpty() throws {
        let dateProvider = RelativeDateProvider()
        let orchestrator = configureOrchestrator(using: dateProvider)
        _ = try orchestrator.directory.createFile(named: dateProvider.now.toFileName)

        dateProvider.advance(bySeconds: 0.5 * performance.minFileAgeForRead)

        XCTAssertTrue(orchestrator.getReadableFiles().isEmpty)
    }

    func testWhenThereAreMultipleReadableFiles_itReturnsSortedFromOldestFile() throws {
        let dateProvider = RelativeDateProvider(advancingBySeconds: 1)
        let orchestrator = configureOrchestrator(using: dateProvider)

        let fileNames = (0..<4).map { _ in dateProvider.now.toFileName }
        try fileNames.forEach { fileName in _ = try orchestrator.directory.createFile(named: fileName) }

        dateProvider.advance(bySeconds: 1 + performance.minFileAgeForRead)
        let readableFiles = orchestrator.getReadableFiles()
        XCTAssertEqual(readableFiles[0].name, fileNames[0])
        XCTAssertEqual(readableFiles[1].name, fileNames[1])
        XCTAssertEqual(readableFiles[2].name, fileNames[2])
        XCTAssertEqual(readableFiles[3].name, fileNames[3])
    }

    func testsWhenThereAreMultipleReadableFiles_itReturnsFilesByExcludingCertainNames() throws {
        let dateProvider = RelativeDateProvider(advancingBySeconds: 1)
        let orchestrator = configureOrchestrator(using: dateProvider)

        let fileNames = (0..<4).map { _ in dateProvider.now.toFileName }
        try fileNames.forEach { fileName in _ = try orchestrator.directory.createFile(named: fileName) }

        dateProvider.advance(bySeconds: 1 + performance.minFileAgeForRead)
        let readableFiles = orchestrator.getReadableFiles(excludingFilesNamed: Set(fileNames[0...2]))
        XCTAssertEqual(readableFiles.count, 1)
        XCTAssertEqual(readableFiles.first?.name, fileNames.last)
    }

    func testWhenReadableFilesAreTooOld_theyGetDeleted() throws {
        let dateProvider = RelativeDateProvider()
        let orchestrator = configureOrchestrator(using: dateProvider)
        _ = try orchestrator.directory.createFile(named: dateProvider.now.toFileName)

        dateProvider.advance(bySeconds: 2 * performance.maxFileAgeForRead)

        XCTAssertTrue(orchestrator.getReadableFiles().isEmpty)
        XCTAssertEqual(try orchestrator.directory.files().count, 0)
    }

    func testWhenThereAreMultipleReadableFiles_itRespectsTheLimit() throws {
        let dateProvider = RelativeDateProvider(advancingBySeconds: 1)
        let orchestrator = configureOrchestrator(using: dateProvider)

        let fileNames = (0..<4).map { _ in dateProvider.now.toFileName }
        try fileNames.forEach { fileName in _ = try orchestrator.directory.createFile(named: fileName) }

        dateProvider.advance(bySeconds: 1 + performance.minFileAgeForRead)
        let limit = 2
        let readableFiles = orchestrator.getReadableFiles(limit: limit)

        XCTAssertEqual(readableFiles.count, limit)
        XCTAssertEqual(readableFiles[0].name, fileNames[0])
        XCTAssertEqual(readableFiles[1].name, fileNames[1])
    }

    // MARK: - Deleting Files

    func testItDeletesReadableFiles() throws {
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
