/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import XCTest
@testable import Datadog

class FileTests: XCTestCase {
    private let fileManager = FileManager.default

    override func setUp() {
        super.setUp()
        temporaryDirectory.create()
    }

    override func tearDown() {
        temporaryDirectory.delete()
        super.tearDown()
    }

    func testItAppendsDataToFile() throws {
        let file = try temporaryDirectory.createFile(named: "file")

        try file.append(data: Data([0x41, 0x41, 0x41, 0x41, 0x41])) // 5 bytes

        XCTAssertEqual(
            try Data(contentsOf: file.url),
            Data([0x41, 0x41, 0x41, 0x41, 0x41])
        )

        try file.append(data: Data([0x42, 0x42, 0x42, 0x42, 0x42])) // 5 bytes
        try file.append(data: Data([0x41, 0x41, 0x41, 0x41, 0x41])) // 5 bytes

        XCTAssertEqual(
            try Data(contentsOf: file.url),
            Data(
                [
                0x41, 0x41, 0x41, 0x41, 0x41,
                0x42, 0x42, 0x42, 0x42, 0x42,
                0x41, 0x41, 0x41, 0x41, 0x41,
                ]
            )
        )
    }

    func testItReadsDataFromFile() throws {
        let file = try temporaryDirectory.createFile(named: "file")
        try file.append(data: "Hello 👋".utf8Data)

        XCTAssertEqual(try file.read().utf8String, "Hello 👋")
    }

    func testItDeletesFile() throws {
        let file = try temporaryDirectory.createFile(named: "file")
        XCTAssertTrue(fileManager.fileExists(atPath: file.url.path))

        try file.delete()

        XCTAssertFalse(fileManager.fileExists(atPath: file.url.path))
    }

    func testItReturnsFileSize() throws {
        let file = try temporaryDirectory.createFile(named: "file")

        try file.append(data: .mock(ofSize: 5))
        XCTAssertEqual(try file.size(), 5)

        try file.append(data: .mock(ofSize: 10))
        XCTAssertEqual(try file.size(), 15)
    }

    func testWhenIOExceptionHappens_itThrowsWhenWritting() throws {
        let file = try temporaryDirectory.createFile(named: "file")
        try file.delete()

        XCTAssertThrowsError(try file.append(data: .mock(ofSize: 5))) { error in
            XCTAssertEqual((error as NSError).localizedDescription, "The file “file” doesn’t exist.")
        }
    }

    func testWhenIOExceptionHappens_itThrowsWhenReading() throws {
        let file = try temporaryDirectory.createFile(named: "file")
        try file.append(data: .mock(ofSize: 5))
        try file.delete()

        XCTAssertThrowsError(try file.read()) { error in
            XCTAssertEqual((error as NSError).localizedDescription, "The file “file” doesn’t exist.")
        }
    }
}
