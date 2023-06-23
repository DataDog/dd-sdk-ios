/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import Git
import Files
@testable import SRSnapshotsCore

// swiftlint:disable colon
class PushSnapshotsCommandTests: XCTestCase {
    func testGivenFilesInLocalRepo_whenRan_itCopiesLocalFilesToRemoteRepo() throws {
        // Given
        let localRepo = LocalRepo(
            localFilesDirectory: InMemoryDirectory([
                "/1":               "CONTENT of 1",
                "/foo/2":           "CONTENT of 2",
                "/foo/bar/3.ext":   "CONTENT of 3",
            ]),
            pointersDirectory: InMemoryDirectory([:]),
            pointersHashing: HashingMock([
                "CONTENT of 1": "HASH of 1",
                "CONTENT of 2": "HASH of 2",
                "CONTENT of 3": "HASH of 3",
            ])
        )
        let remoteRepo = RemoteRepo(
            git: NOPGitClient(),
            remoteFilesDirectory: InMemoryDirectory([:])
        )

        // When
        try pushSnapshots(from: localRepo, to: remoteRepo)

        // Then
        XCTAssertEqual(
            try remoteRepo.remoteFilesDirectory.readAllFiles(),
            [
                "/H/HASH of 1":     "CONTENT of 1",
                "/H/HASH of 2":     "CONTENT of 2",
                "/H/HASH of 3.ext": "CONTENT of 3",
            ],
            "It should should copy local files to remote repository"
        )
        XCTAssertEqual(
            try localRepo.pointersDirectory.readAllFiles(),
            [
                "/1.json":              #"{"hash":"HASH of 1"}"#,
                "/foo/2.json":          #"{"hash":"HASH of 2"}"#,
                "/foo/bar/3.ext.json":  #"{"hash":"HASH of 3"}"#,
            ],
            "It should write new pointer files"
        )
    }

    func testGivenFilesInLocalAndRemoteRepoButNoPointers_whenRan_itRecreatesPointers() throws {
        // Given
        let localRepo = LocalRepo(
            localFilesDirectory: InMemoryDirectory([
                "/1":               "CONTENT of 1",
                "/foo/2":           "CONTENT of 2",
            ]),
            pointersDirectory: InMemoryDirectory([:]),
            pointersHashing: HashingMock([
                "CONTENT of 1": "HASH of 1",
                "CONTENT of 2": "HASH of 2",
            ])
        )
        let remoteRepo = RemoteRepo(
            git: NOPGitClient(),
            remoteFilesDirectory: InMemoryDirectory([
                "/H/HASH of 1": "CONTENT of 1",
                "/H/HASH of 2": "CONTENT of 2",
            ])
        )
        XCTAssertEqual(try localRepo.pointersDirectory.numberOfFiles(), 0)

        // When
        try pushSnapshots(from: localRepo, to: remoteRepo)

        // Then
        XCTAssertEqual(
            try localRepo.pointersDirectory.readAllFiles(),
            [
                "/1.json":              #"{"hash":"HASH of 1"}"#,
                "/foo/2.json":          #"{"hash":"HASH of 2"}"#,
            ],
            "It should recreate pointer files"
        )
    }

    func testGivenFilesPushedToRemoteRepo_whenFileIsRemovedInLocalRepo_itRemovesItsPointer() throws {
        // Given
        let localRepo = LocalRepo(
            localFilesDirectory: InMemoryDirectory([
                "/1":               "CONTENT of 1",
                "/foo/2":           "CONTENT of 2",
            ]),
            pointersDirectory: InMemoryDirectory([:]),
            pointersHashing: HashingMock([
                "CONTENT of 1": "HASH of 1",
                "CONTENT of 2": "HASH of 2",
            ])
        )
        let remoteRepo = RemoteRepo(
            git: NOPGitClient(),
            remoteFilesDirectory: InMemoryDirectory([:])
        )
        try pushSnapshots(from: localRepo, to: remoteRepo)
        XCTAssertEqual(try localRepo.pointersDirectory.numberOfFiles(), 2)

        // When
        try localRepo.localFilesDirectory.deleteFile(at: "/foo/2")
        try pushSnapshots(from: localRepo, to: remoteRepo)

        // Then
        XCTAssertEqual(try localRepo.pointersDirectory.numberOfFiles(), 1)
        XCTAssertEqual(
            try localRepo.pointersDirectory.readAllFiles(),
            [
                "/1.json":              #"{"hash":"HASH of 1"}"#,
            ],
            "It should remove pointer to deleted file"
        )
    }
}
// swiftlint:enable colon
