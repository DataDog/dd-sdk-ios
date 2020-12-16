/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import XCTest
@testable import Datadog

class MoveDataMigratorTests: XCTestCase {
    private var sourceDirectory: Directory! // swiftlint:disable:this implicitly_unwrapped_optional
    private var destinationDirectory: Directory! // swiftlint:disable:this implicitly_unwrapped_optional

    override func setUpWithError() throws {
        try super.setUpWithError()
        sourceDirectory = try Directory(withSubdirectoryPath: UUID().uuidString)
        destinationDirectory = try Directory(withSubdirectoryPath: UUID().uuidString)
    }

    override func tearDown() {
        sourceDirectory.delete()
        destinationDirectory.delete()
        super.tearDown()
    }

    func testGivenEmptySourceAndEmptyDestination_whenRunningMigrator_itKeepsDirectoriesEmpty() throws {
        // Given
        XCTAssertEqual(try sourceDirectory.files().count, 0)
        XCTAssertEqual(try destinationDirectory.files().count, 0)

        // When
        let migrator = MoveDataMigrator(sourceDirectory: sourceDirectory, destinationDirectory: destinationDirectory)
        migrator.migrate()

        // Then
        XCTAssertEqual(try sourceDirectory.files().count, 0)
        XCTAssertEqual(try destinationDirectory.files().count, 0)
    }

    func testGivenEmptySourceAndNonEmptyDestination_whenRunningMigrator_itKeepsDestinationContents() throws {
        // Given
        XCTAssertEqual(try sourceDirectory.files().count, 0)
        _ = try destinationDirectory.createFile(named: "destination1")
        _ = try destinationDirectory.createFile(named: "destination2")
        _ = try destinationDirectory.createFile(named: "destination3")
        XCTAssertEqual(try destinationDirectory.files().count, 3)

        // When
        let migrator = MoveDataMigrator(sourceDirectory: sourceDirectory, destinationDirectory: destinationDirectory)
        migrator.migrate()

        // Then
        XCTAssertEqual(try sourceDirectory.files().count, 0)
        XCTAssertEqual(try destinationDirectory.files().count, 3)
    }

    func testGivenNonEmptySourceAndEmptyDestination_whenRunningMigrator_itMovesSourceFiles() throws {
        // Given
        _ = try sourceDirectory.createFile(named: "source1")
        _ = try sourceDirectory.createFile(named: "source2")
        _ = try sourceDirectory.createFile(named: "source3")
        XCTAssertEqual(try sourceDirectory.files().count, 3)
        XCTAssertEqual(try destinationDirectory.files().count, 0)

        // When
        let migrator = MoveDataMigrator(sourceDirectory: sourceDirectory, destinationDirectory: destinationDirectory)
        migrator.migrate()

        // Then
        XCTAssertEqual(try sourceDirectory.files().count, 0)
        XCTAssertEqual(try destinationDirectory.files().count, 3)
        XCTAssertNoThrow(try destinationDirectory.file(named: "source1"))
        XCTAssertNoThrow(try destinationDirectory.file(named: "source2"))
        XCTAssertNoThrow(try destinationDirectory.file(named: "source3"))
    }

    func testGivenNonEmptySourceAndNonEmptyDestination_whenRunningMigrator_itMovesSourceFilesAndKeepsDestinationContents() throws {
        // Given
        _ = try sourceDirectory.createFile(named: "source1")
        _ = try sourceDirectory.createFile(named: "source2")
        _ = try sourceDirectory.createFile(named: "source3")
        _ = try destinationDirectory.createFile(named: "destination1")
        _ = try destinationDirectory.createFile(named: "destination2")
        _ = try destinationDirectory.createFile(named: "destination3")
        XCTAssertEqual(try sourceDirectory.files().count, 3)
        XCTAssertEqual(try destinationDirectory.files().count, 3)

        // When
        let migrator = MoveDataMigrator(sourceDirectory: sourceDirectory, destinationDirectory: destinationDirectory)
        migrator.migrate()

        // Then
        XCTAssertEqual(try sourceDirectory.files().count, 0)
        XCTAssertEqual(try destinationDirectory.files().count, 6)
        XCTAssertNoThrow(try destinationDirectory.file(named: "source1"))
        XCTAssertNoThrow(try destinationDirectory.file(named: "source2"))
        XCTAssertNoThrow(try destinationDirectory.file(named: "source3"))
        XCTAssertNoThrow(try destinationDirectory.file(named: "destination1"))
        XCTAssertNoThrow(try destinationDirectory.file(named: "destination2"))
        XCTAssertNoThrow(try destinationDirectory.file(named: "destination3"))
    }

    func testGivenFilesToMigrate_whenMigrationFailsForSomeFiles_itContinuesMigratingAllOthers() throws {
        let numberOfFiles = 10
        let numberOfFailedMigrations = 4

        // Given
        try (0..<numberOfFiles).forEach { index in
            _ = try sourceDirectory.createFile(named: "file\(index)")
        }
        XCTAssertEqual(try sourceDirectory.files().count, numberOfFiles)
        XCTAssertEqual(try destinationDirectory.files().count, 0)

        // When
        let allSourceFiles = try sourceDirectory.files().shuffled()
        let skippedFiles = allSourceFiles[..<numberOfFailedMigrations]
        let expectedSourceFileNames = skippedFiles.map { $0.name }
        let expectedDestinationFileNames = allSourceFiles[numberOfFailedMigrations...].map { $0.name }

        try skippedFiles.forEach { try $0.makeReadonly() } // read-only files will raise exception on migration

        let migrator = MoveDataMigrator(sourceDirectory: sourceDirectory, destinationDirectory: destinationDirectory)
        migrator.migrate()

        // Then
        XCTAssertEqual(try sourceDirectory.files().count, numberOfFailedMigrations)
        XCTAssertEqual(try destinationDirectory.files().count, (numberOfFiles - numberOfFailedMigrations))
        try expectedSourceFileNames.forEach { fileName in
            XCTAssertNoThrow(try sourceDirectory.file(named: fileName))
        }
        try expectedDestinationFileNames.forEach { fileName in
            XCTAssertNoThrow(try destinationDirectory.file(named: fileName))
        }

        try skippedFiles.forEach { try $0.makeReadWrite() }
    }
}
