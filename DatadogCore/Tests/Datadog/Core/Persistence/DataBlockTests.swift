/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import TestUtilities

@testable import DatadogCore

class DataBlockTests: XCTestCase {
    func testSerializeEventBlock() throws {
        XCTAssertEqual(
            try DataBlock(type: .event, data: Data([0xFF])).serialize(),
            Data([0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0xFF])
        )
    }

    func testSerializeEventMetadataBlock() throws {
        XCTAssertEqual(
            try DataBlock(type: .eventMetadata, data: Data([0xFF])).serialize(),
            Data([0x01, 0x00, 0x01, 0x00, 0x00, 0x00, 0xFF])
        )
    }

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

    func testDataBlockReader_withEventDataBlock() throws {
        let data = Data([0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0xFF])
        let reader = DataBlockReader(data: data)
        let block = try reader.next()
        XCTAssertEqual(block?.type, .event)
        XCTAssertEqual(block?.data, Data([0xFF]))
    }

    func testDataBlockReader_withEventMetadataBlock() throws {
        let data = Data([0x01, 0x00, 0x01, 0x00, 0x00, 0x00, 0xFF])
        let reader = DataBlockReader(data: data)
        let block = try reader.next()
        XCTAssertEqual(block?.type, .eventMetadata)
        XCTAssertEqual(block?.data, Data([0xFF]))
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
        let reader = DataBlockReader(data: data, maxBlockLength: 2)

        let block = try reader.next()
        XCTAssertEqual(block?.type, .event)
        XCTAssertEqual(block?.data.first, 0xFF)
        XCTAssertEqual(block?.data.count, 2)
    }

    func testDataBlockReader_skipsExceedingBytesLengthLimit() throws {
        let data = Data([0x00, 0x00, 0x02, 0x00, 0x00, 0x00, 0xFF, 0xFF])
        let reader = DataBlockReader(data: data, maxBlockLength: 1)

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
        CreateTemporaryDirectory()
        defer { DeleteTemporaryDirectory() }

        let url = temporaryDirectory.appendingPathComponent("file", isDirectory: false)
        FileManager.default.createFile(atPath: url.path, contents: nil, attributes: nil)
        try FileManager.default.removeItem(at: url)

        let stream = InputStream(url: url)!
        let reader = DataBlockReader(input: stream)

        XCTAssertThrowsError(try reader.next()) { error in
            guard case DataBlockError.readOperationFailed(streamStatus: _, streamError: let streamError) = error else {
                return XCTFail("Unexpected error: \(error)")
            }

            guard let streamError = streamError else {
                return XCTFail("Expected stream error")
            }

            XCTAssertTrue(streamError.localizedDescription.contains("No such file or directory"))
        }
    }
}

private extension DataBlockReader {
    convenience init(data: Data, maxBlockLength: UInt64? = nil) {
        let stream = InputStream(data: data)

        if let maxBlockLength = maxBlockLength {
            self.init(input: stream, maxBlockLength: maxBlockLength)
        } else {
            self.init(input: stream)
        }
    }
}
