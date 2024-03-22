/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import TestUtilities
@testable import DatadogCore

class DataStore_TLVTests: XCTestCase {
    /// The Length bytes for tested block.
    private let expectedL = Data([0x64, 0x00, 0x00, 0x00]) // "100" encoded as hex
    /// The Value bytes for tested block.
    private let expectedV: Data = .mockRandom(ofSize: 100) // 100 bytes of data

    func testSerializeVersionBlock() throws {
        // When
        let tlvData = try DataStoreBlock(type: .version, data: expectedV).serialize()

        // Then
        let expectedT = Data([0x00, 0x00])
        XCTAssertEqual(tlvData, expectedT + expectedL + expectedV)
    }

    func testSerializeDataBlock() throws {
        // When
        let tlvData = try DataStoreBlock(type: .data, data: expectedV).serialize()

        // Then
        let expectedT = Data([0x01, 0x00])
        XCTAssertEqual(tlvData, expectedT + expectedL + expectedV)
    }
}
