/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import TestUtilities
@testable import DatadogCore

class Storage_TLVTests: XCTestCase {
    func testSerializeEventBlock() throws {
        // Given
        let eventData: Data = .mockRandom(ofSize: 100)

        // When
        let tlvData = try BatchDataBlock(type: .event, data: eventData).serialize()

        // Then
        let expectedT = Data([0x00, 0x00])
        let expectedL = Data([0x64, 0x00, 0x00, 0x00]) // 100 in hex
        let expectedV = eventData

        XCTAssertEqual(tlvData, expectedT + expectedL + expectedV)
    }

    func testSerializeEventMetadataBlock() throws {
        // Given
        let eventMetadata: Data = .mockRandom(ofSize: 100)

        // When
        let tlvData = try BatchDataBlock(type: .eventMetadata, data: eventMetadata).serialize()

        // Then
        let expectedT = Data([0x01, 0x00])
        let expectedL = Data([0x64, 0x00, 0x00, 0x00]) // 100 in hex
        let expectedV = eventMetadata

        XCTAssertEqual(tlvData, expectedT + expectedL + expectedV)
    }
}
