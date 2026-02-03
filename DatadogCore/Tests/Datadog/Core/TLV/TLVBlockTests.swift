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
        let largeData: Data = .mockRandom(ofSize: 10_000_000) // 10MB
        let blockData = try Block(type: .one, data: largeData).serialize()

        XCTAssertEqual(blockData.count, 10_000_006)
        // TLV representation: T=0x0000, L=0x00989680, V=<largeData>
        XCTAssertEqual(blockData.prefix(6), Data([0x01, 0x00, 0x80, 0x96, 0x98, 0x00]))
        XCTAssertEqual(blockData.suffix(10_000_000), largeData)
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
}
