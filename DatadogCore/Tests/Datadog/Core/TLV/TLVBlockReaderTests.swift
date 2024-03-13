/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import TestUtilities
@testable import DatadogCore

private enum BlockType: UInt16, TLVBlockType, CaseIterable {
    case one = 0x01
    case two = 0x02
    case three = 0x03
}

private typealias Block = TLVBlock<BlockType>
private typealias BlockReader = TLVBlockReader<BlockType>

class TLVBlockReaderTests: XCTestCase {
    func testReadingNextBlocks() throws {
        let block1 = Data([0x01, 0x00, 0x01, 0x00, 0x00, 0x00, 0xAA])
        let block2 = Data([0x02, 0x00, 0x02, 0x00, 0x00, 0x00, 0xAA, 0xBB])
        let block3 = Data([0x03, 0x00, 0x03, 0x00, 0x00, 0x00, 0xAA, 0xBB, 0xCC])
        //                 ^   type  ^ ^    data size       ^  ^     data      ^

        let reader = BlockReader(data: block1 + block2 + block3)
        var currentBlock: Block

        currentBlock = try XCTUnwrap(reader.next())
        XCTAssertEqual(currentBlock.type, .one)
        XCTAssertEqual(currentBlock.data, Data([0xAA]))

        currentBlock = try XCTUnwrap(reader.next())
        XCTAssertEqual(currentBlock.type, .two)
        XCTAssertEqual(currentBlock.data, Data([0xAA, 0xBB]))

        currentBlock = try XCTUnwrap(reader.next())
        XCTAssertEqual(currentBlock.type, .three)
        XCTAssertEqual(currentBlock.data, Data([0xAA, 0xBB, 0xCC]))

        XCTAssertNil(try reader.next())
    }

    func testReadingNextBlocks_whenEmpty() throws {
        let reader = BlockReader(data: Data())
        XCTAssertNil(try reader.next())
    }

    func testWhenReadingNextBlocks_itSkipsUnknownTypes() throws {
        let data = Data(
            [
                0x00, 0xFF, 0x01, 0x00, 0x00, 0x00, 0xFF, // <- unknown type: 0x00, 0xFF
                0x01, 0x00, 0x01, 0x00, 0x00, 0x00, 0xFF, // <- known type: 0x01, 0x00
                0x00, 0xFF, 0x01, 0x00, 0x00, 0x00, 0xFF, // <- unknown type: 0x00, 0xFF
            ]
        )
        let reader = BlockReader(data: data)
        let block = try XCTUnwrap(reader.next())
        XCTAssertEqual(block.type, .one)
        XCTAssertEqual(block.data, Data([0xFF]))
        XCTAssertNil(try reader.next())
    }

    func testReadingAllBlocks() throws {
        let data = try (0..<100).map { idx in
            try Block(
                type: BlockType.allCases[idx % BlockType.allCases.count],
                data: .mock(ofSize: idx)
            ).serialize()
        }
            .reduce(Data(), +)

        let reader = BlockReader(data: data)
        let blocks = try reader.all()

        XCTAssertEqual(blocks.count, 100)
        XCTAssertEqual(blocks.filter({ $0.type == .one }).count, 34)
        XCTAssertEqual(blocks.filter({ $0.type == .two }).count, 33)
        XCTAssertEqual(blocks.filter({ $0.type == .three }).count, 33)
        XCTAssertEqual(blocks.first?.data.count, 0)
        XCTAssertEqual(blocks.last?.data.count, 99)
    }

    func testReadingZeroBytesBlock() throws {
        let data = Data(
            [
                0x01, 0x00, 0x00, 0x00, 0x00, 0x00,
                0x02, 0x00, 0x01, 0x00, 0x00, 0x00, 0xFF,
                0x03, 0x00, 0x02, 0x00, 0x00, 0x00, 0xFF, 0xFF
            ]
        )
        let reader = BlockReader(data: data)

        var block = try reader.next()
        XCTAssertEqual(block?.type, .one)
        XCTAssertEqual(block?.data, Data())

        block = try reader.next()
        XCTAssertEqual(block?.type, .two)
        XCTAssertEqual(block?.data, Data([0xFF]))

        block = try reader.next()
        XCTAssertEqual(block?.type, .three)
        XCTAssertEqual(block?.data, Data([0xFF, 0xFF]))
    }

    func testReadingBytesUnderLengthLimit() throws {
        let data = Data([0x01, 0x00, 0x02, 0x00, 0x00, 0x00, 0xFF, 0xFF])
        let reader = BlockReader(data: data, maxBlockLength: 2)

        let block = try XCTUnwrap(reader.next())
        XCTAssertEqual(block.type, .one)
        XCTAssertEqual(block.data.first, 0xFF)
        XCTAssertEqual(block.data.count, 2)
    }

    func testSkippingExceedingBytesLengthLimit() throws {
        let data = Data([0x01, 0x00, 0x02, 0x00, 0x00, 0x00, 0xFF, 0xFF])
        let reader = BlockReader(data: data, maxBlockLength: 1)

        XCTAssertThrowsError(try reader.next()) { error in
            guard let error = error as? TLVBlockError, case TLVBlockError.bytesLengthExceedsLimit(let limit) = error else {
                XCTFail("Unexpected error: \(error)")
                return
            }
            XCTAssertEqual(limit, 1)
        }
    }

    func testWhenIOErrorHappens_itThrowsWhenReading() throws {
        CreateTemporaryDirectory()
        defer { DeleteTemporaryDirectory() }

        let url = temporaryDirectory.appendingPathComponent("file", isDirectory: false)
        let stream = try XCTUnwrap(InputStream(url: url))
        let reader = BlockReader(input: stream)

        XCTAssertThrowsError(try reader.next()) { error in
            guard let error = error as? TLVBlockError, case TLVBlockError.readOperationFailed(_, let nsError as NSError) = error else {
                XCTFail("Unexpected error: \(error)")
                return
            }
            XCTAssertTrue(nsError.localizedDescription.contains("No such file or directory"))
        }
    }
}

private extension BlockReader {
    convenience init(data: Data, maxBlockLength: UInt64? = nil) {
        let stream = InputStream(data: data)

        if let maxBlockLength = maxBlockLength {
            self.init(input: stream, maxBlockLength: maxBlockLength)
        } else {
            self.init(input: stream)
        }
    }
}
