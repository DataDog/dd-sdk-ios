/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
@testable import Files

class DirectoryTests: XCTestCase {
    private var directory: Directory! // swiftlint:disable:this implicitly_unwrapped_optional

    override func setUpWithError() throws {
        let temporaryURL = uniqueTemporaryDirectoryURL()
        self.directory = try Directory(url: temporaryURL)
    }

    override func tearDownWithError() throws {
        try self.directory.delete()
    }

    func testWritingAndReadingFiles() throws {
        // When
        try directory.writeFile(at: "foo.ext", data: "foo data".utf8Data)
        try directory.writeFile(at: "foo/bar.ext", data: "bar data".utf8Data)
        try directory.writeFile(at: "foo/bar/fizz.ext", data: "fizz data".utf8Data)
        try directory.writeFile(at: "/buzz", data: "buzz data".utf8Data)

        // Then
        XCTAssertEqual(try directory.readFile(at: "foo.ext").utf8String, "foo data")
        XCTAssertEqual(try directory.readFile(at: "foo/bar.ext").utf8String, "bar data")
        XCTAssertEqual(try directory.readFile(at: "foo/bar/fizz.ext").utf8String, "fizz data")
        XCTAssertEqual(try directory.readFile(at: "/buzz").utf8String, "buzz data")
        XCTAssertEqual(try directory.readFile(at: "buzz").utf8String, "buzz data", "It should use sanitized path")
    }

    func testFileExistence() throws {
        // Given
        let data = "some data".utf8Data
        try directory.writeFile(at: "foo.ext", data: data)
        try directory.writeFile(at: "foo/bar.ext", data: data)

        // When & Then
        XCTAssertTrue(directory.fileExists(at: "foo.ext"))
        XCTAssertTrue(directory.fileExists(at: "/foo.ext"))
        XCTAssertTrue(directory.fileExists(at: "foo"))
        XCTAssertTrue(directory.fileExists(at: "/foo"))
        XCTAssertTrue(directory.fileExists(at: "foo/bar.ext"))
        XCTAssertTrue(directory.fileExists(at: "/foo/bar.ext"))
        XCTAssertFalse(directory.fileExists(at: "/fizz.ext"))
        XCTAssertFalse(directory.fileExists(at: "/foo/buzz.ext"))
    }

    func testFindingAllFiles() throws {
        // Given
        let data = "some data".utf8Data
        try directory.writeFile(at: "foo.ext", data: data)
        try directory.writeFile(at: "/foo/bar.ext", data: data)
        try directory.writeFile(at: ".hidden", data: data)

        // When
        let allFilePaths = try directory.findAllFiles()

        // Then
        XCTAssertTrue(allFilePaths.contains("foo.ext"))
        XCTAssertTrue(allFilePaths.contains("foo/bar.ext"), "It should sanitize file path")
        XCTAssertFalse(allFilePaths.contains(".hidden"), "It should ignore hidden files")
        XCTAssertEqual(allFilePaths.count, 2)
    }

    func testCopyingFileToAnotherDirectory() throws {
        // Given
        let data = "some data".utf8Data
        try directory.writeFile(at: "foo.ext", data: data)
        try directory.writeFile(at: "/foo/bar.ext", data: data)

        // When
        let anotherDirectory = try Directory(url: uniqueTemporaryDirectoryURL())
        try directory.copyFile(at: "foo.ext", to: anotherDirectory, at: "foo.ext")
        try directory.copyFile(at: "foo.ext", to: anotherDirectory, at: "foo.ext") // when file exists
        try directory.copyFile(at: "foo/bar.ext", to: anotherDirectory, at: "foo/bar.ext")

        // Then
        XCTAssertEqual(try directory.findAllFiles(), try anotherDirectory.findAllFiles())
    }

    func testDeletingAllFiles() throws {
        // Given
        let data = "some data".utf8Data
        try directory.writeFile(at: "foo.ext", data: data)
        try directory.writeFile(at: "/foo/bar.ext", data: data)
        XCTAssertEqual(try directory.numberOfFiles(), 2)

        // When & Then
        try directory.deleteAllFiles()
        XCTAssertEqual(try directory.numberOfFiles(), 0)
    }

    func testDeletingFile() throws {
        // Given
        let data = "some data".utf8Data
        try directory.writeFile(at: "foo.ext", data: data)
        try directory.writeFile(at: "/foo/bar.ext", data: data)
        XCTAssertEqual(try directory.numberOfFiles(), 2)

        // When & Then
        try directory.deleteFile(at: "foo.ext")
        XCTAssertEqual(try directory.numberOfFiles(), 1)
        try directory.deleteFile(at: "/foo/bar.ext")
        XCTAssertEqual(try directory.numberOfFiles(), 0)
    }
}

private extension Data {
    var utf8String: String { String(data: self, encoding: .utf8)! }
}

private extension String {
    var utf8Data: Data { self.data(using: .utf8)! }
}
