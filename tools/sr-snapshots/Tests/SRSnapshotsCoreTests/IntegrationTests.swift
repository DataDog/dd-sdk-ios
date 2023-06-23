/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import Files
import SRSnapshotsCore

class IntegrationTests: XCTestCase {
    private var localRepo: Directory! // swiftlint:disable:this implicitly_unwrapped_optional
    private var remoteRepo: Directory! // swiftlint:disable:this implicitly_unwrapped_optional

    override func setUpWithError() throws {
        localRepo = try Directory(url: uniqueTemporaryDirectoryURL())
        remoteRepo = try Directory(url: uniqueTemporaryDirectoryURL())
    }

    override func tearDownWithError() throws {
        try localRepo.delete()
        try remoteRepo.delete()
    }

    func getArgs() -> [String] {
        return [
            "--local-folder", localRepo.url.path(),
            "--remote-folder", remoteRepo.url.path(),
            "--dry-run", // to skip git operations
        ]
    }

    func createPushCommand() throws -> PushSnapshotsCommand { try .parse(getArgs()) }
    func createPullCommand() throws -> PullSnapshotsCommand { try .parse(getArgs()) }

    func testPushAndPullFiles() throws {
        // Given
        let pngsFolder = try localRepo.subdirectory("png")
        try pngsFolder.writeFile(at: "/foo.png", data: "CONTENT of foo".utf8Data)
        try pngsFolder.writeFile(at: "/bar/bizz.png", data: "CONTENT of bizz".utf8Data)
        XCTAssertEqual(try pngsFolder.numberOfFiles(), 2, "There should be 2 PNG files in local repo")

        // When
        let push = try createPushCommand()
        try push.run()

        try pngsFolder.deleteAllFiles()
        XCTAssertEqual(try pngsFolder.numberOfFiles(), 0, "There should be no PNG files in local repo")

        let pull = try createPullCommand()
        try pull.run()

        // Then
        XCTAssertEqual(
            try localRepo.readAllFiles(),
            [
                "png/foo.png": "CONTENT of foo",
                "png/bar/bizz.png": "CONTENT of bizz",
                "pointers/foo.png.json": "{\"hash\":\"4bfd4ab833e2e2e6818ace821ee3921b9caa3036\"}",
                "pointers/bar/bizz.png.json": "{\"hash\":\"1b3e3142c225f7f0001ace8ee6e950187fcd560d\"}",
            ]
        )
        XCTAssertEqual(
            try remoteRepo.readAllFiles(),
            [
                "ios/4/4bfd4ab833e2e2e6818ace821ee3921b9caa3036.png": "CONTENT of foo",
                "ios/1/1b3e3142c225f7f0001ace8ee6e950187fcd560d.png": "CONTENT of bizz",
            ]
        )
    }

    func testPushingMultipleVersionsOfTheSameFile() throws {
        // Given
        let pngsFolder = try localRepo.subdirectory("png")
        let push = try createPushCommand()

        // When
        try pngsFolder.writeFile(at: "/foo.png", data: "VERSION 1".utf8Data)
        try push.run()

        try pngsFolder.writeFile(at: "/foo.png", data: "VERSION 2".utf8Data)
        try push.run()

        try pngsFolder.writeFile(at: "/foo.png", data: "VERSION 3".utf8Data)
        try push.run()

        // Then
        XCTAssertEqual(
            try localRepo.readAllFiles(),
            [
                "png/foo.png": "VERSION 3",
                "pointers/foo.png.json": "{\"hash\":\"1babd56893ba8fb84fe964b2f89e87cd6862f36c\"}",
            ]
        )
        XCTAssertEqual(
            try remoteRepo.readAllFiles(),
            [
                "ios/2/28840a4f78f852c22493dff33c039d29bbeaa416.png": "VERSION 1",
                "ios/c/ca5aa979ddab92828b268371803232267b5629d7.png": "VERSION 2",
                "ios/1/1babd56893ba8fb84fe964b2f89e87cd6862f36c.png": "VERSION 3",
            ]
        )
    }

    func testReferencingTheSameFileMultipleTimes() throws {
        // Given
        let pngsFolder = try localRepo.subdirectory("png")
        let content = "CONTENT"
        try pngsFolder.writeFile(at: "/foo.png", data: content.utf8Data)
        try pngsFolder.writeFile(at: "/bar/bizz.png", data: content.utf8Data)
        try pngsFolder.writeFile(at: "/bar/bizz/buzz.png", data: content.utf8Data)

        // When
        let push = try createPushCommand()
        try push.run()

        // Then
        XCTAssertEqual(
            try localRepo.readAllFiles(),
            [
                "png/foo.png": "CONTENT",
                "png/bar/bizz.png": "CONTENT",
                "png/bar/bizz/buzz.png": "CONTENT",
                "pointers/foo.png.json": "{\"hash\":\"238a131a3e8eb98d1fc5b27d882ca40b7618fd2a\"}",
                "pointers/bar/bizz.png.json": "{\"hash\":\"238a131a3e8eb98d1fc5b27d882ca40b7618fd2a\"}",
                "pointers/bar/bizz/buzz.png.json": "{\"hash\":\"238a131a3e8eb98d1fc5b27d882ca40b7618fd2a\"}"
            ]
        )
        XCTAssertEqual(
            try remoteRepo.readAllFiles(),
            [
                "ios/2/238a131a3e8eb98d1fc5b27d882ca40b7618fd2a.png": "CONTENT"
            ],
            "There should be only one copy of all 3 files in remote repo, because they are all the same"
        )
    }

    func testIgnoringHiddenFiles() throws {
        // Given
        let pngsFolder = try localRepo.subdirectory("png")
        try pngsFolder.writeFile(at: "/.hidden", data: "any".utf8Data)
        try pngsFolder.writeFile(at: "/foo.png", data: "CONTENT of foo".utf8Data)

        // When
        let push = try createPushCommand()
        try push.run()

        // Then
        XCTAssertEqual(
            try localRepo.readAllFiles(),
            [
                "png/foo.png": "CONTENT of foo",
                "pointers/foo.png.json": "{\"hash\":\"4bfd4ab833e2e2e6818ace821ee3921b9caa3036\"}"
            ],
            "There should be no pointer for hidden file"
        )
        XCTAssertEqual(
            try remoteRepo.readAllFiles(),
            [
                "ios/4/4bfd4ab833e2e2e6818ace821ee3921b9caa3036.png": "CONTENT of foo"
            ],
            "Hidden file should not be backed up"
        )
    }
}

internal extension Directory {
    func subdirectory(_ name: String) throws -> Directory {
        try Directory(url: url.appending(path: name, directoryHint: .isDirectory))
    }
}
