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
class PullSnapshotsCommandTests: XCTestCase {
    func testGivenExistingPointersInLocalRepo_whenRan_itCopiesRemoteFilesToLocalRepo() throws {
        // Given
        let localRepo = LocalRepo(
            localFilesDirectory: InMemoryDirectory([:]),
            pointersDirectory: InMemoryDirectory([
                "/1.json":              #"{ "hash" : "HASH of 1" }"#,
                "/foo/2.json":          #"{ "hash" : "HASH of 2" }"#,
                "/foo/bar/3.ext.json":  #"{ "hash" : "HASH of 3" }"#,
            ]),
            pointersHashing: HashingMock([
                "CONTENT of 1":     "HASH of 1",
                "CONTENT of 2":     "HASH of 2",
                "CONTENT of 3":     "HASH of 3",
            ])
        )
        let remoteRepo = RemoteRepo(
            git: NOPGitClient(),
            remoteFilesDirectory: InMemoryDirectory([
                "/H/HASH of 1":     "CONTENT of 1",
                "/H/HASH of 2":     "CONTENT of 2",
                "/H/HASH of 3.ext": "CONTENT of 3",
            ])
        )

        // When
        try pullSnapshots(to: localRepo, from: remoteRepo)

        // Then
        XCTAssertEqual(
            try localRepo.localFilesDirectory.readAllFiles(),
            [
                "/1":               "CONTENT of 1",
                "/foo/2":           "CONTENT of 2",
                "/foo/bar/3.ext":   "CONTENT of 3",
            ],
            "It should should copy remote files to local repository"
        )
    }
}
// swiftlint:enable colon
