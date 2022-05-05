/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import XCTest
@testable import Datadog

class DataBlockTests: XCTestCase {
    func testSerializeDataBlock() throws {
        XCTAssertEqual(
            DataBlock(type: .event, data: Data([0xFF])).serialize(),
            Data([0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0xFF])
        )
    }

    func testDataBlockReader_withSingleBlock() throws {
        let data = Data([0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0xFF])
        let reader = DataBlockReader(data: data)
        let block = try reader.next()
        XCTAssertEqual(block?.type, .event)
        XCTAssertEqual(block?.data, Data([0xFF]))
    }

    func testDataBlockReader_withMultipleBlock() throws {
        let data = (0..<100).map { size in
            DataBlock(
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
}
