/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
@testable import Datadog

class DataBlockTests: XCTestCase {
    func testSerializeDataBlock() throws {
        XCTAssertEqual(
            try DataBlock(type: .event, data: Data([0xFF])).serialize(),
            Data([0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0xFF])
        )
    }

    func testSerialize_zeroBytesBlock() throws {
        XCTAssertEqual(
            try DataBlock(type: .event, data: Data()).serialize(),
            Data([0x00, 0x00, 0x00, 0x00, 0x00, 0x00])
        )
    }

    func testSerialize_largeBytesBlock() throws {
        let data = try DataBlock(
            type: .event,
            data: .mockRepeating(byte: 0xFF, times: 10_000_000) // 10MB
        ).serialize()

        XCTAssertEqual(data.count, 10_000_006)
        // TLV representation: T=0x0000, L=0x00989680, V[0]=0xFF
        XCTAssertEqual(data.prefix(7), Data([0x00, 0x00, 0x80, 0x96, 0x98, 0x00, 0xFF]))
    }

    func testDataBlockReader_withSingleBlock() throws {
        let data = Data([0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0xFF])
        let reader = DataBlockReader(data: data)
        let block = try reader.next()
        XCTAssertEqual(block?.type, .event)
        XCTAssertEqual(block?.data, Data([0xFF]))
    }

    func testDataBlockReader_withMultipleBlock() throws {
        let data = try (0..<100).map { size in
            try DataBlock(
                type: .event,
                data: .mock(ofSize: size)
            ).serialize()
        }
        .reduce(Data(), +)

        let reader = DataBlockReader(data: data)
        let blocks = try reader.all()

        XCTAssertEqual(blocks.count, 100)
        XCTAssertEqual(blocks.first?.data.count, 0)
        XCTAssertEqual(blocks.last?.data.count, 99)
    }

    func testDataBlockReader_skipUnknownType() throws {
        let data = Data(
            [
                0x00, 0xFF, 0x01, 0x00, 0x00, 0x00, 0xFF,
                0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0xFF,
                0x00, 0xFF, 0x01, 0x00, 0x00, 0x00, 0xFF
            ]
        )
        let reader = DataBlockReader(data: data)
        let block = try reader.next()
        XCTAssertEqual(block?.type, .event)
        XCTAssertEqual(block?.data, Data([0xFF]))
        XCTAssertNil(try reader.next())
    }

    func testDataBlockReader_readsZeroBytesBlock() throws {
        let data = Data(
            [
                0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
                0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0xFF,
                0x00, 0x00, 0x02, 0x00, 0x00, 0x00, 0xFF, 0xFF
            ]
        )
        let reader = DataBlockReader(data: data)

        var block = try reader.next()
        XCTAssertEqual(block?.type, .event)
        XCTAssertEqual(block?.data, Data())

        block = try reader.next()
        XCTAssertEqual(block?.type, .event)
        XCTAssertEqual(block?.data, Data([0xFF]))

        block = try reader.next()
        XCTAssertEqual(block?.type, .event)
        XCTAssertEqual(block?.data, Data([0xFF, 0xFF]))
    }

    func testDataBlockReader_readsBytesUnderLengthLimit() throws {
        let data = Data([0x00, 0x00, 0x02, 0x00, 0x00, 0x00, 0xFF, 0xFF])
        let reader = DataBlockReader(data: data, maxBlockLenght: 2)

        let block = try reader.next()
        XCTAssertEqual(block?.type, .event)
        XCTAssertEqual(block?.data.first, 0xFF)
        XCTAssertEqual(block?.data.count, 2)
    }

    func testDataBlockReader_skipsExceedingBytesLengthLimit() throws {
        let data = Data([0x00, 0x00, 0x02, 0x00, 0x00, 0x00, 0xFF, 0xFF])
        let reader = DataBlockReader(data: data, maxBlockLenght: 1)

        do {
            _ = try reader.next()
            XCTFail("Expected error to be thrown")
        } catch DataBlockError.bytesLengthExceedsLimit(let limit) where limit == 1 {
            // Expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testDataBlockReader_whenIOErrorHappens_itThrowsWhenReading() throws {
        temporaryDirectory.create()
        defer { temporaryDirectory.delete() }

        let file = try temporaryDirectory.createFile(named: "file")
        try file.delete()

        let stream = try file.stream()
        let reader = DataBlockReader(input: stream)

        do {
            _ = try reader.next()
            XCTFail("Expected error to be thrown")
        } catch DataBlockError.readOperationFailed(_, let error) {
            XCTAssertEqual(
                (error as? NSError)?.localizedDescription,
                "The operation couldn’t be completed. No such file or directory"
            )
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}

private extension DataBlockReader {
    convenience init(data: Data, maxBlockLenght: UInt64? = nil) {
        let stream = InputStream(data: data)

        if let maxBlockLenght = maxBlockLenght {
            self.init(input: stream, maxBlockLenght: maxBlockLenght)
        } else {
            self.init(input: stream)
        }
    }
}
