/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
@testable import Datadog

final class EventGeneratorTests: XCTestCase {
    func testEmpty() throws {
        let dataBlocks = [DataBlock]()

        let sut = EventGenerator(dataBlocks: dataBlocks)
        let events = sut.map { $0 }
        XCTAssertEqual(events.count, 0)
    }

    func testWithoutEvent() throws {
        let dataBlocks = [DataBlock(type: .eventMetadata, data: Data([0x01]))]

        let sut = EventGenerator(dataBlocks: dataBlocks)
        let events = sut.map { $0 }
        XCTAssertEqual(events.count, 0)
    }

    func testEventWithoutMetadata() throws {
        let dataBlocks = [DataBlock(type: .event, data: Data([0x01]))]

        let sut = EventGenerator(dataBlocks: dataBlocks)
        let events = sut.map { $0 }
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events[0].data, Data([0x01]))
        XCTAssertNil(events[0].metadata)
    }

    func testEventWithMetadata() throws {
        let dataBlocks = [
            DataBlock(type: .eventMetadata, data: Data([0x02])),
            DataBlock(type: .event, data: Data([0x01]))
        ]

        let sut = EventGenerator(dataBlocks: dataBlocks)
        let events = sut.map { $0 }
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events[0].metadata, Data([0x02]))
        XCTAssertEqual(events[0].data, Data([0x01]))
    }

    func testEventWithCurruptedMetadata() throws {
        let dataBlocks = [
            DataBlock(type: .eventMetadata, data: Data([0x03])), // skipped from reading
            DataBlock(type: .eventMetadata, data: Data([0x02])),
            DataBlock(type: .event, data: Data([0x01]))
        ]

        let sut = EventGenerator(dataBlocks: dataBlocks)
        let events = sut.map { $0 }
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events[0].metadata, Data([0x02]))
        XCTAssertEqual(events[0].data, Data([0x01]))
    }

    func testEvents() {
        let dataBlocks = [
            DataBlock(type: .eventMetadata, data: Data([0x02])),
            DataBlock(type: .event, data: Data([0x01])),
            DataBlock(type: .event, data: Data([0x03])),
            DataBlock(type: .event, data: Data([0x05]))
        ]

        let sut = EventGenerator(dataBlocks: dataBlocks)
        let events = sut.map { $0 }
        XCTAssertEqual(events.count, 3)

        XCTAssertEqual(events[0].data, Data([0x01]))
        XCTAssertEqual(events[0].metadata, Data([0x02]))

        XCTAssertEqual(events[1].data, Data([0x03]))
        XCTAssertNil(events[1].metadata)

        XCTAssertEqual(events[2].data, Data([0x05]))
        XCTAssertNil(events[2].metadata)
    }
}
