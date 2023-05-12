/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import Files
@testable import SRSnapshotsCore

// swiftlint:disable colon
class PointerTests: XCTestCase {
    func testCalculatingPointers() throws {
        // Given
        let directory = InMemoryDirectory([
            "/foo.png":         "CONTENT of foo.png",
            "/bar/bizz":        "CONTENT of bizz",
            "/bar/bizz.txt":    "CONTENT of bizz.txt",
            "/bar/.bizz":       "CONTENT of .bizz",
            "/bar/.bizz.png":   "CONTENT of .bizz.png",
        ])
        let hashing = HashingMock([
            "CONTENT of foo.png":   "HASH of foo.png",
            "CONTENT of bizz":      "HASH of bizz",
            "CONTENT of bizz.txt":  "HASH of bizz.txt",
            "CONTENT of .bizz":     "HASH of .bizz",
            "CONTENT of .bizz.png": "HASH of .bizz.png",
        ])
        let file1 = FileLocation(directory: directory, path: "/foo.png")
        let file2 = FileLocation(directory: directory, path: "/bar/bizz")
        let file3 = FileLocation(directory: directory, path: "/bar/bizz.txt")
        let file4 = FileLocation(directory: directory, path: "/bar/.bizz")
        let file5 = FileLocation(directory: directory, path: "/bar/.bizz.png")

        // When
        let pointer1 = try Pointer(localFile: file1, hashing: hashing)
        let pointer2 = try Pointer(localFile: file2, hashing: hashing)
        let pointer3 = try Pointer(localFile: file3, hashing: hashing)
        let pointer4 = try Pointer(localFile: file4, hashing: hashing)
        let pointer5 = try Pointer(localFile: file5, hashing: hashing)

        // Then
        XCTAssertEqual(pointer1.localFilePath, "/foo.png")
        XCTAssertEqual(pointer1.localFileExtension, "png")
        XCTAssertEqual(pointer1.contentHash, "HASH of foo.png")

        XCTAssertEqual(pointer2.localFilePath, "/bar/bizz")
        XCTAssertNil(pointer2.localFileExtension)
        XCTAssertEqual(pointer2.contentHash, "HASH of bizz")

        XCTAssertEqual(pointer3.localFilePath, "/bar/bizz.txt")
        XCTAssertEqual(pointer3.localFileExtension, "txt")
        XCTAssertEqual(pointer3.contentHash, "HASH of bizz.txt")

        XCTAssertEqual(pointer4.localFilePath, "/bar/.bizz")
        XCTAssertNil(pointer4.localFileExtension)
        XCTAssertEqual(pointer4.contentHash, "HASH of .bizz")

        XCTAssertEqual(pointer5.localFilePath, "/bar/.bizz.png")
        XCTAssertEqual(pointer5.localFileExtension, "png")
        XCTAssertEqual(pointer5.contentHash, "HASH of .bizz.png")
    }
}
// swiftlint:enable colon
