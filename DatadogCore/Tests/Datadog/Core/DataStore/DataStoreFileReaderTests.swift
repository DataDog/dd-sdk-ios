/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import TestUtilities
import DatadogInternal
@testable import DatadogCore

class DataStoreFileReaderTests: XCTestCase {
    private var reader: DataStoreFileReader! // swiftlint:disable:this implicitly_unwrapped_optional

    override func setUpWithError() throws {
        CreateTemporaryDirectory()
        reader = DataStoreFileReader(
            file: try Directory(url: temporaryDirectory).createFile(named: "file")
        )
    }

    override func tearDown() {
        DeleteTemporaryDirectory()
    }

    private let okVersionBytes: [UInt8] = [
        /* T: */ 0x00, 0x00, /* L: */ 0x02, 0x00, 0x00, 0x00, /* V: (3) */ 0x03, 0x00
    ]
    private let okDataBytes: [UInt8] = [
        /* T: */ 0x01, 0x00, /* L: */ 0x0A, 0x00, 0x00, 0x00, /* V: ("value data") */ 0x76, 0x61, 0x6C, 0x75, 0x65, 0x20, 0x64, 0x61, 0x74, 0x61
    ]

    func testReadingVersionAndData() throws {
        // Given
        try reader.file.write(data: Data(okVersionBytes + okDataBytes))

        // When
        let (data, version) = try reader.read()

        // Then
        XCTAssertEqual(version, 3)
        XCTAssertEqual(data.utf8String, "value data")
    }

    func testReadingInsufficientVersionBytes() throws {
        // When
        let insufficientVersionBytes: [UInt8] = [
            /* T: */ 0x00, 0x00, /* L: (1 byte but `DataStoreKeyVersion` needs 2) */ 0x01, 0x00, 0x00, 0x00, /* V: */ 0x00
        ]
        try reader.file.write(data: Data(insufficientVersionBytes + okDataBytes))

        // Then
        DDAssertThrowsError(try reader.read()) { (error: DataStoreFileReadingError) in
            DDAssertReflectionEqual(error, .insufficientVersionBytes)
        }
    }

    func testReadingOverflowingVersionBytes() throws {
        // When
        let overflowingVersionBytes: [UInt8] = [
            /* T: */ 0x00, 0x00, /* L: (3 bytes, but `DataStoreKeyVersion` uses 2) */ 0x03, 0x00, 0x00, 0x00, /* V: */ 0xff, 0xff, 0xff
        ]
        try reader.file.write(data: Data(overflowingVersionBytes + okDataBytes))

        // Then
        let (_, version) = try reader.read()
        XCTAssertEqual(version, .max, "It should not overflow")
    }

    func testReadingMissingVersionBytes() throws {
        // When
        try reader.file.write(data: Data([/* missing version */] + okDataBytes))

        // Then
        DDAssertThrowsError(try reader.read()) { (error: DataStoreFileReadingError) in
            DDAssertReflectionEqual(error, .unexpectedBlocks([.data]))
        }
    }

    func testReadingEmptyDataBytes() throws {
        // When (empty)
        let emptyDataBytes = [UInt8](try DataStoreBlock(type: .data, data: Data()).serialize())
        try reader.file.write(data: Data(okVersionBytes + emptyDataBytes))

        // Then
        let (data, _) = try reader.read()
        XCTAssertEqual(data, Data())
    }

    func testReadingOverflowingDataBytes() throws {
        // Given
        let maxBlockLength = MAX_DATA_LENGTH
        // When
        let overflowingLength = maxBlockLength + 1
        let overflowingDataBytes = [UInt8](try DataStoreBlock(type: .data, data: .mockRepeating(byte: 0xff, times: Int(overflowingLength)))
            .serialize(maxLength: overflowingLength))
        try reader.file.write(data: Data(okVersionBytes + overflowingDataBytes))

        // Then
        DDAssertThrowsError(try reader.read()) { (error: TLVBlockError) in
            DDAssertReflectionEqual(error, .bytesLengthExceedsLimit(length: overflowingLength, limit: maxBlockLength))
        }
    }

    func testReadingMissingDataBytes() throws {
        // When
        try reader.file.write(data: Data(okVersionBytes + [/* missing data */]))

        // Then
        DDAssertThrowsError(try reader.read()) { (error: DataStoreFileReadingError) in
            DDAssertReflectionEqual(error, .unexpectedBlocks([.version]))
        }
    }

    func testReadingEmptyFile() throws {
        // When
        try reader.file.write(data: Data())

        // Then
        DDAssertThrowsError(try reader.read()) { (error: DataStoreFileReadingError) in
            DDAssertReflectionEqual(error, .unexpectedBlocks([]))
        }
    }

    func testReadingInvalidFile() throws {
        try (0..<10).forEach { _ in
            // When
            try reader.file.write(data: .mockRandom(ofSize: 1_024)) // arbitrary bytes (invalid format)

            // Then
            XCTAssertThrowsError(try reader.read())
        }
    }
}
