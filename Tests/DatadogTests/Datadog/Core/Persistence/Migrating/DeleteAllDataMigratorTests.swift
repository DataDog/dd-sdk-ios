/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import XCTest
@testable import Datadog

class DeleteAllDataMigratorTests: XCTestCase {
    private var directory: Directory! // swiftlint:disable:this implicitly_unwrapped_optional

    override func setUpWithError() throws {
        try super.setUpWithError()
        directory = try Directory(withSubdirectoryPath: UUID().uuidString)
    }

    override func tearDown() {
        directory.delete()
        super.tearDown()
    }

    func testGivenEmptyDirectory_whenRunningMigrator_itKeepsTheDirectoryEmpty() throws {
        // Given
        XCTAssertEqual(try directory.files().count, 0)

        // When
        let migrator = DeleteAllDataMigrator(directory: directory)
        migrator.migrate()

        // Then
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.url.path))
        XCTAssertEqual(try directory.files().count, 0)
    }

    func testGivenNonEmptyDirectory_whenRunningMigrator_itDeletesAllFiles() throws {
        // Given
        let filesCount = 50
        try (0..<filesCount).forEach { iteration in _ = try directory.createFile(named: "file\(iteration)") }
        XCTAssertEqual(try directory.files().count, filesCount)

        // When
        let migrator = DeleteAllDataMigrator(directory: directory)
        migrator.migrate()

        // Then
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.url.path))
        XCTAssertEqual(try directory.files().count, 0)
    }
}
