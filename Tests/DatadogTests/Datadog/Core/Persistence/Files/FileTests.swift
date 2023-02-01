/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
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
        let data = "Hello 👋".utf8Data
        try file.append(data: data)

        let stream = try file.stream()
        stream.open()
        defer { stream.close() }

        var bytes = [UInt8](repeating: 0, count: data.count)
        XCTAssertEqual(stream.read(&bytes, maxLength: data.count), data.count)

        XCTAssertEqual(String(bytes: bytes, encoding: .utf8), "Hello 👋")
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

    func testWhenIOExceptionHappens_itThrowsWhenWriting() throws {
        let file = try temporaryDirectory.createFile(named: "file")
        try file.delete()

        XCTAssertThrowsError(try file.append(data: .mock(ofSize: 5))) { error in
            XCTAssertEqual((error as NSError).localizedDescription, "The file “file” doesn’t exist.")
        }
    }
}
