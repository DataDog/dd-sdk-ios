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
                "pointers/foo.png.json": "{\"hash\":\"1cd9f12712e76720fca45a6e1f2c962c8e4a60f1801db7b6b72eb32a5f4e5184\"}",
                "pointers/bar/bizz.png.json": "{\"hash\":\"d5fe96c85344c29c75ae78f913636208e40a59cabb420f3616005b5c1f43ccbd\"}",
            ]
        )
        XCTAssertEqual(
            try remoteRepo.readAllFiles(),
            [
                "ios/1/1cd9f12712e76720fca45a6e1f2c962c8e4a60f1801db7b6b72eb32a5f4e5184.png": "CONTENT of foo",
                "ios/d/d5fe96c85344c29c75ae78f913636208e40a59cabb420f3616005b5c1f43ccbd.png": "CONTENT of bizz",
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
                "pointers/foo.png.json": "{\"hash\":\"86aae0a03f5e0b79eba0bbd6ac4987cc76befe46c677ab256a9d1f3f6d047d7b\"}",
            ]
        )
        XCTAssertEqual(
            try remoteRepo.readAllFiles(),
            [
                "ios/1/1ee6380aa771c83b7a1ea3d9858497d4899bea9af19d0197036b6d5264a70b12.png": "VERSION 1",
                "ios/1/1f9de9774b246abace727157a600b4aa49689e1ab78060da3c2468b16b383ccd.png": "VERSION 2",
                "ios/8/86aae0a03f5e0b79eba0bbd6ac4987cc76befe46c677ab256a9d1f3f6d047d7b.png": "VERSION 3",
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
                "pointers/foo.png.json": "{\"hash\":\"65f23e22a9bfedda96929b3cfcb8b6d2fdd34a2e877ddb81f45d79ab05710e12\"}",
                "pointers/bar/bizz.png.json": "{\"hash\":\"65f23e22a9bfedda96929b3cfcb8b6d2fdd34a2e877ddb81f45d79ab05710e12\"}",
                "pointers/bar/bizz/buzz.png.json": "{\"hash\":\"65f23e22a9bfedda96929b3cfcb8b6d2fdd34a2e877ddb81f45d79ab05710e12\"}"
            ]
        )
        XCTAssertEqual(
            try remoteRepo.readAllFiles(),
            [
                "ios/6/65f23e22a9bfedda96929b3cfcb8b6d2fdd34a2e877ddb81f45d79ab05710e12.png": "CONTENT"
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
                "pointers/foo.png.json": "{\"hash\":\"1cd9f12712e76720fca45a6e1f2c962c8e4a60f1801db7b6b72eb32a5f4e5184\"}"
            ],
            "There should be no pointer for hidden file"
        )
        XCTAssertEqual(
            try remoteRepo.readAllFiles(),
            [
                "ios/1/1cd9f12712e76720fca45a6e1f2c962c8e4a60f1801db7b6b72eb32a5f4e5184.png": "CONTENT of foo"
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
