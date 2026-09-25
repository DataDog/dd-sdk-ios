/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import TestUtilities
@testable import DatadogCore

private enum BlockType: UInt16 {
    case one = 0x01
    case two = 0x02
    case three = 0x03
}

private typealias Block = TLVBlock<BlockType>

class TLVBlockTests: XCTestCase {
    func testSerializeBlock() throws {
        XCTAssertEqual(
            try Block(type: .one, data: Data([0xAA])).serialize(),
            Data([0x01, 0x00, 0x01, 0x00, 0x00, 0x00, 0xAA])
            //   ^   type  ^  ^    data size       ^ ^data^
        )
        XCTAssertEqual(
            try Block(type: .two, data: Data([0xAA, 0xBB])).serialize(),
            Data([0x02, 0x00, 0x02, 0x00, 0x00, 0x00, 0xAA, 0xBB])
        )
        XCTAssertEqual(
            try Block(type: .three, data: Data([0xAA, 0xBB, 0xCC])).serialize(),
            Data([0x03, 0x00, 0x03, 0x00, 0x00, 0x00, 0xAA, 0xBB, 0xCC])
        )
    }

    func testSerialize_zeroBytesBlock() throws {
        XCTAssertEqual(
            try Block(type: .one, data: Data()).serialize(),
            Data([0x01, 0x00, 0x00, 0x00, 0x00, 0x00])
        )
    }

    func testSerialize_largeBytesBlock() throws {
        let largeData: Data = .mockRandom(ofSize: 4 * 1_024 * 1_024) // 4MB — within the 5MB limit
        let blockData = try Block(type: .one, data: largeData).serialize()

        XCTAssertEqual(blockData.count, 4 * 1_024 * 1_024 + 6)
        // TLV representation: T=0x0001 (little-endian), L=4MB as little-endian UInt32, V=<largeData>
        XCTAssertEqual(blockData.prefix(6), Data([0x01, 0x00, 0x00, 0x00, 0x40, 0x00]))
        XCTAssertEqual(blockData.suffix(4 * 1_024 * 1_024), largeData)
    }

    func testSerialize_withLengthExceedingLimit() throws {
        let maxDataLength = TLVBlockSize(100)
        let exceedingData: Data = .mockRandom(ofSize: maxDataLength + 1)

        do {
            _ = try Block(type: .one, data: exceedingData).serialize(maxLength: maxDataLength)
            XCTFail()
        } catch let error {
            XCTAssertEqual(
                (error as CustomStringConvertible).description,
                TLVBlockError.bytesLengthExceedsLimit(length: maxDataLength + 1, limit: maxDataLength).description
            )
        }
    }

    // MARK: - Serializing into a shared buffer

    func testSerializeInto_appendsAtTheEndOfTheBuffer() throws {
        // Given
        var buffer = Data([0xFF, 0xFE])

        // When
        try Block(type: .one, data: Data([0xAA])).serialize(into: &buffer)
        try Block(type: .two, data: Data([0xBB, 0xCC])).serialize(into: &buffer)

        // Then
        XCTAssertEqual(
            buffer,
            Data([0xFF, 0xFE])
                + Data([0x01, 0x00, 0x01, 0x00, 0x00, 0x00, 0xAA])
                + Data([0x02, 0x00, 0x02, 0x00, 0x00, 0x00, 0xBB, 0xCC])
        )
    }

    func testSerializeInto_producesSameBytesAsSerialize() throws {
        // Given
        let blocks = [
            Block(type: .one, data: Data()),
            Block(type: .two, data: .mockRandom(ofSize: 1)),
            Block(type: .three, data: .mockRandom(ofSize: 1_024)),
            Block(type: .one, data: .mockRandom(ofSize: 512 * 1_024)),
        ]

        // When
        var buffer = Data()
        try blocks.forEach { try $0.serialize(into: &buffer) }

        // Then
        let expected = try blocks.reduce(into: Data()) { $0 += try $1.serialize() }
        XCTAssertEqual(buffer, expected)
    }

    func testSerializeInto_withLengthExceedingLimit_leavesBufferUnchanged() throws {
        // Given
        let maxDataLength = TLVBlockSize(100)
        var buffer = Data()
        try Block(type: .one, data: Data([0xAA])).serialize(into: &buffer, maxLength: maxDataLength)
        let bufferBefore = buffer

        // When
        let exceedingData: Data = .mockRandom(ofSize: maxDataLength + 1)
        XCTAssertThrowsError(try Block(type: .two, data: exceedingData).serialize(into: &buffer, maxLength: maxDataLength)) { error in
            XCTAssertEqual(
                (error as CustomStringConvertible).description,
                TLVBlockError.bytesLengthExceedsLimit(length: maxDataLength + 1, limit: maxDataLength).description
            )
        }

        // Then - no partial block was appended, so the buffer remains a valid TLV stream
        XCTAssertEqual(buffer, bufferBefore)
    }

    func testSanitizingReadOperationFailed_neverReportsRawStreamError() {
        // Given
        // `streamError`'s `userInfo` content depends on its domain - `NSCocoaErrorDomain` file errors,
        // for instance, can include the file path via `NSFilePathErrorKey` - so it must go through the
        // same central `NSError` sanitization as any other foreign error, not be interpolated directly
        // into `TLVBlockError`'s description.
        let sensitiveFilePath = "/var/mobile/Containers/session-\(String.mockRandom(length: 16))/file.dat"
        let streamError = NSError(
            domain: NSCocoaErrorDomain,
            code: 260,
            userInfo: [NSFilePathErrorKey: sensitiveFilePath]
        )
        let error = TLVBlockError.readOperationFailed(streamStatus: .error, streamError: streamError)

        // When
        let sanitized = error.sanitize()

        // Then
        XCTAssertFalse(sanitized.message.contains(sensitiveFilePath))
        XCTAssertTrue(sanitized.message.contains("domain: \(NSCocoaErrorDomain), code: 260"))
    }
}
