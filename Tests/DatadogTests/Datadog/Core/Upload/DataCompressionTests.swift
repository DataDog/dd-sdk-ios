/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import XCTest
@testable import Datadog

class DataCompressionTests: XCTestCase {
    func testFuzzy_Adler32() {
        for _ in 1...500 {
            // Given
            let data: Data = .mockRandom(ofSize: Int.mockRandom(min: 1, max: 10_000))

            // When
            let checksum = adler32(data)

            // Then
            XCTAssertEqual(checksum?.count, 4)
        }
    }

    func testFuzzy_deflate_inflate() throws {
        for _ in 1...500 {
            // Given
            let data: Data = .mockRandom(ofSize: Int.mockRandom(min: 100, max: 10_000))

            // When
            let compressed = try XCTUnwrap(deflate(data))
            let decompressed = inflate(compressed)

            // Then
            XCTAssertEqual(decompressed, data)
        }
    }

    func testFuzzy_zip_unzip() throws {
        for _ in 1...500 {
            // Given
            let data: Data = .mockRandom(ofSize: Int.mockRandom(min: 100, max: 10_000))

            // When
            let compressed = try XCTUnwrap(zip(data))
            let decompressed = unzip(compressed)

            // Then
            XCTAssertEqual(decompressed, data)
        }
    }

    func test8MB_deflate_inflate() throws {
        // Given
        let size = 1_024 * 1_024 * 8 // 8 MB
        let data: Data = .mockRandom(ofSize: size)

        // When
        let compressed = try XCTUnwrap(deflate(data))
        let decompressed = inflate(compressed, capacity: size)

        // Then
        XCTAssertEqual(decompressed, data)
    }
}
