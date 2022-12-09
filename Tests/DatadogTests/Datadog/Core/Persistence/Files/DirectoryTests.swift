/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
@testable import Datadog

class DirectoryTests: XCTestCase {
    private let fileManager = FileManager.default

    // MARK: - Directory creation

    func testItObtainsCacheDirectory() throws {
        let directory = try Directory.cache()
        XCTAssertTrue(fileManager.fileExists(atPath: directory.url.path))
    }

    func testGivenSubdirectoryName_itCreatesIt() throws {
        let directory = try Directory.cache().createSubdirectory(path: uniqueSubdirectoryName())
        defer { directory.delete() }

        XCTAssertTrue(fileManager.fileExists(atPath: directory.url.path))
    }

    func testGivenSubdirectoryPath_itCreatesIt() throws {
        let path = uniqueSubdirectoryName() + "/subdirectory/another-subdirectory"
        let directory = try Directory.cache().createSubdirectory(path: path)
        defer { directory.delete() }

        XCTAssertTrue(fileManager.fileExists(atPath: directory.url.path))
    }

    func testWhenDirectoryExists_itDoesNothing() throws {
        let path = uniqueSubdirectoryName() + "/subdirectory/another-subdirectory"
        let originalDirectory = try Directory.cache().createSubdirectory(path: path)
        defer { originalDirectory.delete() }
        _ = try originalDirectory.createFile(named: "abcd")

        // Try again when directory exists
        let retrievedDirectory = try Directory.cache().createSubdirectory(path: path)

        XCTAssertEqual(retrievedDirectory.url, originalDirectory.url)
        XCTAssertTrue(fileManager.fileExists(atPath: retrievedDirectory.url.appendingPathComponent("abcd").path))
    }

    func testItReturnsSubdirectoryAtPathWhenItExists() throws {
        let directory = temporaryDirectory
        directory.create()
        defer { directory.delete() }

        let uniqueName = uniqueSubdirectoryName()
        let expectedDirectory = try directory.createSubdirectory(path: uniqueName)
        let actualDirectory = try directory.subdirectory(path: uniqueName)

        XCTAssertEqual(expectedDirectory.url, actualDirectory.url)
    }

    func testItThrowsWhenAskedForSubdirectoryWhichDoesNotExist() throws {
        let directory = temporaryDirectory
        directory.create()
        defer { directory.delete() }

        XCTAssertThrowsError(try directory.subdirectory(path: "abc")) { error in
            XCTAssertTrue(error is InternalError, "It should throw as directory at given path doesn't exist")
        }

        _ = try directory.createFile(named: "file-instead-of-directory")
        XCTAssertThrowsError(try directory.subdirectory(path: "file-instead-of-directory")) { error in
            XCTAssertTrue(error is InternalError, "It should throw as given path is a file, not directory")
        }
    }

    // MARK: - Files manipulation

    func testItCreatesFile() throws {
        let path = uniqueSubdirectoryName() + "/subdirectory/another-subdirectory"
        let directory = try Directory(withSubdirectoryPath: path)
        defer { directory.delete() }

        let file = try directory.createFile(named: "abcd")

        XCTAssertEqual(file.url, directory.url.appendingPathComponent("abcd"))
        XCTAssertTrue(fileManager.fileExists(atPath: file.url.path))
    }

    func testItChecksIfFileExists() throws {
        let directory = try Directory(withSubdirectoryPath: uniqueSubdirectoryName())
        defer { directory.delete() }

        XCTAssertFalse(directory.hasFile(named: "foo"))
        _ = try directory.createFile(named: "foo")
        XCTAssertTrue(directory.hasFile(named: "foo"))
    }

    func testWhenFileExists_ItCanBeRetrieved() throws {
        let directory = try Directory(withSubdirectoryPath: uniqueSubdirectoryName())
        defer { directory.delete() }

        // When
        _ = try directory.createFile(named: "abcd")

        // Then
        let file = try directory.file(named: "abcd")
        XCTAssertEqual(file.url, directory.url.appendingPathComponent("abcd"))
        XCTAssertTrue(fileManager.fileExists(atPath: file.url.path))
    }

    func testWhenFileDoesNotExist_ItThrowsErrorWhenRetrieving() throws {
        let directory = try Directory(withSubdirectoryPath: uniqueSubdirectoryName())
        defer { directory.delete() }

        // When
        XCTAssertFalse(directory.hasFile(named: "foo"))

        // Then
        XCTAssertThrowsError(try directory.file(named: "foo"))
    }

    func testItRetrievesAllFiles() throws {
        let directory = try Directory(withSubdirectoryPath: uniqueSubdirectoryName())
        defer { directory.delete() }
        _ = try directory.createFile(named: "f1")
        _ = try directory.createFile(named: "f2")
        _ = try directory.createFile(named: "f3")

        let files = try directory.files()
        XCTAssertEqual(files.count, 3)
        files.forEach { file in XCTAssertTrue(file.url.relativePath.contains(directory.url.relativePath)) }
        files.forEach { file in XCTAssertTrue(fileManager.fileExists(atPath: file.url.path)) }
    }

    func testItDeletesAllFiles() throws {
        let directory = try Directory(withSubdirectoryPath: uniqueSubdirectoryName())
        defer { directory.delete() }
        _ = try directory.createFile(named: "f1")
        _ = try directory.createFile(named: "f2")
        _ = try directory.createFile(named: "f3")

        XCTAssertEqual(try directory.files().count, 3)

        try directory.deleteAllFiles()

        XCTAssertTrue(fileManager.fileExists(atPath: directory.url.path))
        XCTAssertEqual(try directory.files().count, 0)
    }

    func testItMovesAllFiles() throws {
        let sourceDirectory = try Directory(withSubdirectoryPath: uniqueSubdirectoryName())
        defer { sourceDirectory.delete() }
        _ = try sourceDirectory.createFile(named: "f1")
        _ = try sourceDirectory.createFile(named: "f2")
        _ = try sourceDirectory.createFile(named: "f3")

        let destinationDirectory = try Directory(withSubdirectoryPath: uniqueSubdirectoryName())
        defer { destinationDirectory.delete() }

        XCTAssertEqual(try sourceDirectory.files().count, 3)
        XCTAssertEqual(try destinationDirectory.files().count, 0)

        try sourceDirectory.moveAllFiles(to: destinationDirectory)

        XCTAssertEqual(try sourceDirectory.files().count, 0)
        XCTAssertEqual(try destinationDirectory.files().count, 3)
        XCTAssertNoThrow(try destinationDirectory.file(named: "f1"))
        XCTAssertNoThrow(try destinationDirectory.file(named: "f2"))
        XCTAssertNoThrow(try destinationDirectory.file(named: "f3"))
    }

    // MARK: - Helpers

    private func uniqueSubdirectoryName() -> String {
        return UUID().uuidString
    }
}
