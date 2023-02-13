/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import TestUtilities

@testable import DatadogInternal

class DataCompressionTests: XCTestCase {
    let encoder = JSONEncoder()

    struct Foo: Codable {
        let bar: String
        let baz: Int
        let qux: URL

        init() {
            let length: Int = .mockRandom(min: 100, max: 10_000)
            bar = .mockRandom(length: length)
            baz = .mockRandom()
            qux = .mockRandom()
        }
    }

    func testWhenComputingAdler32Checksum_itAlwaysHas4Bytes() throws {
        for _ in 1...100 {
            // Given
            let data = try encoder.encode(Foo())

            // When
            let checksum = Deflate.adler32(data)

            // Then
            XCTAssertEqual(checksum?.count, 4)
        }
    }

    func testWhenDataIsDeflated_itInflateToOriginalData() throws {
        for _ in 1...100 {
            // Given
            let data = try encoder.encode(Foo())

            // When
            let compressed = try XCTUnwrap(Deflate.compress(data))
            let decompressed = zlib.decompress(compressed)

            // Then
            XCTAssertEqual(decompressed, data)
        }
    }

    func testWhenDataIsCompressed_itDecompressToOriginalData() throws {
        for _ in 1...100 {
            // Given
            let data = try encoder.encode(Foo())

            // When
            let compressed = try XCTUnwrap(Deflate.encode(data))
            let decompressed = zlib.decode(compressed)

            // Then
            XCTAssertEqual(decompressed, data)
        }
    }
}
