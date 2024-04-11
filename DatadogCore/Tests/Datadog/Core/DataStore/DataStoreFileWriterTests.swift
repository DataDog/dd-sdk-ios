/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import TestUtilities
import DatadogInternal
@testable import DatadogCore

class DataStoreFileWriterTests: XCTestCase {
    private var writer: DataStoreFileWriter! // swiftlint:disable:this implicitly_unwrapped_optional

    override func setUpWithError() throws {
        CreateTemporaryDirectory()
        writer = DataStoreFileWriter(
            file: try Directory(url: temporaryDirectory).createFile(named: "file")
        )
    }

    override func tearDown() {
        DeleteTemporaryDirectory()
    }

    func testWritingVersionAndData() throws {
        // When
        try writer.write(data: "value data".utf8Data, version: 3)

        // Then
        let expectedBytes: [UInt8] = [
            // version block:
            /* T: */ 0x00, 0x00, /* L: */ 0x02, 0x00, 0x00, 0x00, /* V: */ 0x03, 0x00, // 3
            // data block:
            /* T: */ 0x01, 0x00, /* L: */ 0x0A, 0x00, 0x00, 0x00, /* V: */ 0x76, 0x61, 0x6C, 0x75, 0x65, 0x20, 0x64, 0x61, 0x74, 0x61, // "value data"
        ]
        let actualBytes = [UInt8](try writer.file.read())
        XCTAssertEqual(expectedBytes, actualBytes)
    }

    func testWritingVersion() throws {
        XCTAssertNoThrow(try writer.write(data: .mockAny(), version: .min))
        XCTAssertNoThrow(try writer.write(data: .mockAny(), version: .max))
    }

    func testWritingData() throws {
        // When
        let maxLength = DataStoreFileWriter.Constants.maxDataLength
        let min = Data()
        let max: Data = .mockRandom(ofSize: maxLength)
        let overflow: Data = .mockRandom(ofSize: maxLength + 1)

        // Then
        XCTAssertNoThrow(try writer.write(data: min, version: .mockAny()))
        XCTAssertNoThrow(try writer.write(data: max, version: .mockAny()))
        DDAssertThrowsError(try writer.write(data: overflow, version: .mockAny())) { (error: DataStoreFileWritingError) in
            DDAssertReflectionEqual(error, .failedToEncodeData(TLVBlockError.bytesLengthExceedsLimit(limit: maxLength)))
        }
    }
}
