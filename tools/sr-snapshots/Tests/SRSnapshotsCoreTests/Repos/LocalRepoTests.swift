/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import Files
@testable import SRSnapshotsCore

// swiftlint:disable colon
class LocalRepoTests: XCTestCase {
    func testCreatingPointersForLocalFiles() throws {
        // Given
        let repo = LocalRepo(
            localFilesDirectory: InMemoryDirectory([
                "/1":               "CONTENT of 1",
                "/foo/2":           "CONTENT of 2",
                "/foo/bar/3.ext":   "CONTENT of 3.ext",
            ]),
            pointersDirectory: InMemoryDirectory(mockRandomFiles(count: 10)),
            pointersHashing: HashingMock([
                "CONTENT of 1":     "HASH of 1",
                "CONTENT of 2":     "HASH of 2",
                "CONTENT of 3.ext": "HASH of 3.ext",
            ])
        )

        // When
        let pointers = try repo.createPointers()

        // Then
        let expectedPointers = [
            Pointer(localFilePath: "/1", contentHash: "HASH of 1"),
            Pointer(localFilePath: "/foo/2", contentHash: "HASH of 2"),
            Pointer(localFilePath: "/foo/bar/3.ext", contentHash: "HASH of 3.ext"),
        ]

        XCTAssertEqual(Set(pointers), Set(expectedPointers))
    }

    func testReadingPointersFromPointerFiles() throws {
        // Given
        let repo = LocalRepo(
            localFilesDirectory: InMemoryDirectory([:]),
            pointersDirectory: InMemoryDirectory([
                "/1.json":              #"{ "hash" : "HASH of 1" }"#,
                "/foo/2.json":          #"{ "hash" : "HASH of 2" }"#,
                "/foo/bar/3.ext.json":  #"{ "hash" : "HASH of 3.ext" }"#,
            ]),
            pointersHashing: HashingMock([:])
        )

        // When
        let pointers = try repo.readPointers()

        // Then
        let expectedPointers = [
            Pointer(localFilePath: "/1", contentHash: "HASH of 1"),
            Pointer(localFilePath: "/foo/2", contentHash: "HASH of 2"),
            Pointer(localFilePath: "/foo/bar/3.ext", contentHash: "HASH of 3.ext"),
        ]
        XCTAssertEqual(Set(pointers), Set(expectedPointers))
    }

    func testWritingPointerFiles() throws {
        // Given
        let repo = LocalRepo(
            localFilesDirectory: InMemoryDirectory([:]),
            pointersDirectory: InMemoryDirectory(mockRandomFiles(count: 5)),
            pointersHashing: HashingMock([:])
        )

        // When
        try repo.write(pointers: [
            Pointer(localFilePath: "/1", contentHash: "HASH of 1"),
            Pointer(localFilePath: "/foo/2", contentHash: "HASH of 2"),
            Pointer(localFilePath: "/foo/bar/3.ext", contentHash: "HASH of 3.ext"),
        ])

        // Then
        XCTAssertEqual(
            try repo.pointersDirectory.readAllFiles(),
            [
                "/1.json":              #"{"hash":"HASH of 1"}"#,
                "/foo/2.json":          #"{"hash":"HASH of 2"}"#,
                "/foo/bar/3.ext.json":  #"{"hash":"HASH of 3.ext"}"#
            ],
            "It should delete previous pointer files and create new one"
        )
    }

    func testObtainingLocalFileLocation() {
        // Given
        let repo = LocalRepo(
            localFilesDirectory: InMemoryDirectory([
                "/1":               "CONTENT of 1",
                "/foo/2":           "CONTENT of 2",
                "/foo/bar/3.ext":   "CONTENT of 3.ext",
            ]),
            pointersDirectory: InMemoryDirectory([:]),
            pointersHashing: HashingMock([:])
        )

        // When
        let file1 = repo.localFileLocation(for: Pointer(localFilePath: "/1", contentHash: "any"))
        let file2 = repo.localFileLocation(for: Pointer(localFilePath: "/foo/2", contentHash: "any"))
        let file3 = repo.localFileLocation(for: Pointer(localFilePath: "/foo/bar/3.ext", contentHash: "any"))

        // Then
        XCTAssertEqual(file1.path, "/1")
        XCTAssertEqual(file2.path, "/foo/2")
        XCTAssertEqual(file3.path, "/foo/bar/3.ext")
    }

    func testDeletingLocalFiles() throws {
        // Given
        let repo = LocalRepo(
            localFilesDirectory: InMemoryDirectory(mockRandomFiles(count: 10)),
            pointersDirectory: InMemoryDirectory(mockRandomFiles(count: 10)),
            pointersHashing: HashingMock([:])
        )

        // When
        try repo.deleteLocalFiles()

        // Then
        XCTAssertEqual(try repo.localFilesDirectory.numberOfFiles(), 0)
        XCTAssertEqual(try repo.pointersDirectory.numberOfFiles(), 10)
    }
}
// swiftlint:enable colon
