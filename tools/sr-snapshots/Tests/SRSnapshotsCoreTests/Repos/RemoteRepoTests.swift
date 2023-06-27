/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import Git
import Files
@testable import SRSnapshotsCore

class RemoteRepoTests: XCTestCase {
    func testObtainingRemoteFileLocation() {
        // Given
        let repo = RemoteRepo(
            git: NOPGitClient(),
            remoteFilesDirectory: InMemoryDirectory([:])
        )

        let pointer1 = Pointer(localFilePath: mockRandomPath(extension: nil), contentHash: "abcdefg")
        let pointer2 = Pointer(localFilePath: mockRandomPath(extension: nil), contentHash: "bcdefgh")
        let pointer3 = Pointer(localFilePath: mockRandomPath(extension: nil), contentHash: "cdefghi")
        let pointer4 = Pointer(localFilePath: mockRandomPath(extension: "ext"), contentHash: "cdefghi")

        // When
        let file1 = repo.remoteFileLocation(for: pointer1)
        let file2 = repo.remoteFileLocation(for: pointer2)
        let file3 = repo.remoteFileLocation(for: pointer3)
        let file4 = repo.remoteFileLocation(for: pointer4)

        // Then
        XCTAssertEqual(file1.path, "/a/abcdefg", "It should group files in folders denoted by the first letter of hash")
        XCTAssertIdentical(file1.directory as! InMemoryDirectory, repo.remoteFilesDirectory as! InMemoryDirectory)

        XCTAssertEqual(file2.path, "/b/bcdefgh")
        XCTAssertIdentical(file2.directory as! InMemoryDirectory, repo.remoteFilesDirectory as! InMemoryDirectory)

        XCTAssertEqual(file3.path, "/c/cdefghi")
        XCTAssertIdentical(file3.directory as! InMemoryDirectory, repo.remoteFilesDirectory as! InMemoryDirectory)

        XCTAssertEqual(file4.path, "/c/cdefghi.ext", "It should use the extension of local file")
        XCTAssertIdentical(file4.directory as! InMemoryDirectory, repo.remoteFilesDirectory as! InMemoryDirectory)
    }
}
