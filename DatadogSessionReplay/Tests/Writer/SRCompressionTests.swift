/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import zlib
import XCTest
import Compression

@testable import DatadogSessionReplay
@testable import TestUtilities

class SRCompressionTests: XCTestCase {
    func testWhenDataIsCompressed_itDecompressesToOriginalData() throws {
        for length in 1...100 {
            // Given
            let original: String = .mockRandom(length: length)

            // When
            let data = try XCTUnwrap(original.data(using: .utf8))
            let compressed = try SRCompression.compress(data: data)

            // Then
            let decompressedData = try XCTUnwrap(Deflate.decode(compressed), "Failed to decompress deflated data")
            let decompressed = try XCTUnwrap(String(data: decompressedData, encoding: .utf8))
            XCTAssertEqual(decompressed, original)
        }
    }

    func testWhenDataIsCompressedItTakesLessSpace() throws {
        // Given
        let pattern: String = .mockRandom()
        let textWithPatterns = (0..<100)
            .map { _ in pattern + String.mockRandom() }
            .joined()

        // When
        let data = try XCTUnwrap(textWithPatterns.data(using: .utf8))
        let compressed = try SRCompression.compress(data: data)

        // Then
        XCTAssertLessThan(compressed.count, data.count)
    }

    /// Following fixtures were recorded from `dd-sdk-android` deflater.
    func testFixtures() throws {
        // Given
        let data1 = "1"
        let data2 = "11111"
        let data3 = "Foo bar bizz buzz"
        let data4 = "Lorem ipsum dolor sit amet, Lorem ipsum dolor sit amet"
        let data5 = "Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat. Duis aute irure dolor in reprehenderit in voluptate velit esse cillum dolore eu fugiat nulla pariatur. Excepteur sint occaecat cupidatat non proident, sunt in culpa qui officia deserunt mollit anim id est laborum."

        // When
        let compressed1 = try SRCompression.compress(data: data1.data(using: .utf8)!)
        let compressed2 = try SRCompression.compress(data: data2.data(using: .utf8)!)
        let compressed3 = try SRCompression.compress(data: data3.data(using: .utf8)!)
        let compressed4 = try SRCompression.compress(data: data4.data(using: .utf8)!)
        let compressed5 = try SRCompression.compress(data: data5.data(using: .utf8)!)

        // Then
        let expected1 = Data([0x78, 0x9c, 0x32, 0x04, 0x00, 0x00, 0x00, 0xff, 0xff, 0x03, 0x00, 0x00, 0x32, 0x00, 0x32])
        let expected2 = Data([0x78, 0x9c, 0x32, 0x34, 0x04, 0x02, 0x00, 0x00, 0x00, 0x00, 0xff, 0xff, 0x03, 0x00, 0x02, 0xe4, 0x00, 0xf6])
        let expected3 = Data([0x78, 0x9c, 0x72, 0xcb, 0xcf, 0x57, 0x48, 0x4a, 0x2c, 0x52, 0x48, 0xca, 0xac, 0xaa, 0x52, 0x48, 0x2a, 0xad, 0xaa, 0x02, 0x00, 0x00, 0x00, 0xff, 0xff, 0x03, 0x00, 0x35, 0x75, 0x06, 0x44])
        let expected4 = Data([0x78, 0x9c, 0xf2, 0xc9, 0x2f, 0x4a, 0xcd, 0x55, 0xc8, 0x2c, 0x28, 0x2e, 0xcd, 0x55, 0x48, 0xc9, 0xcf, 0xc9, 0x2f, 0x52, 0x28, 0xce, 0x2c, 0x51, 0x48, 0xcc, 0x4d, 0x2d, 0xd1, 0x51, 0xf0, 0xc1, 0x29, 0x07, 0x00, 0x00, 0x00, 0xff, 0xff, 0x03, 0x00, 0x21, 0x6a, 0x13, 0xd5])
        let expected5 = Data([0x78, 0x9c, 0x34, 0x90, 0xc1, 0x71, 0x43, 0x31, 0x08, 0x44, 0x5b, 0xd9, 0x02, 0x3c, 0xbf, 0x8a, 0xe4, 0x96, 0x6b, 0x0a, 0x20, 0x88, 0xef, 0x30, 0x23, 0x09, 0x59, 0x02, 0x8f, 0xcb, 0x0f, 0xca, 0x4f, 0x6e, 0x42, 0xc0, 0xb2, 0xfb, 0x3e, 0x6c, 0x4a, 0x83, 0x8e, 0x15, 0x0d, 0xc5, 0xaa, 0x4d, 0x2c, 0x75, 0x50, 0x13, 0xbf, 0x81, 0xad, 0x2f, 0x61, 0x17, 0x8f, 0x09, 0x2a, 0x3a, 0x74, 0xb1, 0xf6, 0x3b, 0xa4, 0x6a, 0x36, 0x97, 0x94, 0x5c, 0x80, 0x68, 0xac, 0x66, 0x05, 0x2e, 0x6d, 0xe4, 0xb2, 0x76, 0xd6, 0xa2, 0x25, 0xba, 0x23, 0x1c, 0x95, 0xbe, 0x52, 0x1e, 0xe2, 0x97, 0xb4, 0xa0, 0xd1, 0xbd, 0x13, 0xa8, 0xea, 0x23, 0xe8, 0xc0, 0xa7, 0x43, 0xba, 0xb6, 0xd4, 0x46, 0xd3, 0xfd, 0x78, 0x66, 0x49, 0xed, 0x86, 0x47, 0xe8, 0x42, 0xb7, 0xe5, 0x33, 0x0a, 0xe4, 0x25, 0x93, 0xd5, 0xc9, 0xd5, 0x3a, 0xa2, 0x56, 0x6a, 0x6c, 0x97, 0xf2, 0x1e, 0xd2, 0xa5, 0xfb, 0xd2, 0xaf, 0xa4, 0x8e, 0x1c, 0x86, 0x50, 0x1a, 0x6f, 0xe9, 0xc9, 0xae, 0x00, 0x79, 0xca, 0x0f, 0xbc, 0x6d, 0x49, 0x0a, 0x17, 0xe8, 0x8c, 0x74, 0x72, 0x65, 0xd5, 0x8e, 0x29, 0x63, 0xca, 0xb7, 0xf4, 0x22, 0x33, 0x83, 0xe7, 0xc7, 0xd3, 0x6a, 0x8c, 0x3c, 0x27, 0x69, 0x27, 0x93, 0x42, 0xd6, 0x12, 0xb0, 0xd6, 0xfa, 0x4f, 0x28, 0x03, 0x05, 0xce, 0xb8, 0x2b, 0x39, 0xfa, 0x36, 0x84, 0x41, 0x33, 0x8b, 0x98, 0x07, 0xde, 0x5f, 0x2c, 0xc3, 0x25, 0x36, 0xc6, 0x64, 0x60, 0xcc, 0x24, 0x9c, 0x73, 0x1c, 0x43, 0x0b, 0xf9, 0xde, 0xc8, 0x14, 0x63, 0x9a, 0x16, 0xe9, 0x9b, 0xe2, 0x26, 0x95, 0x47, 0x39, 0xea, 0xa0, 0x9d, 0x1b, 0x76, 0x9e, 0xca, 0x4a, 0x28, 0xb2, 0x64, 0xee, 0x6e, 0xb3, 0xba, 0x6d, 0xd0, 0x06, 0xa4, 0x89, 0x63, 0xfd, 0x71, 0x8d, 0x76, 0xfc, 0x00, 0x00, 0x00, 0xff, 0xff, 0x03, 0x00, 0xa0, 0x5c, 0xa5, 0x09])

        XCTAssertEqual(compressed1, expected1)
        XCTAssertEqual(compressed2, expected2)
        XCTAssertEqual(compressed3, expected3)
        XCTAssertEqual(compressed4, expected4)
        XCTAssertEqual(compressed5, expected5)
    }
}

// MARK: - Helpers

/// TODO: RUMM-2690 Share this utility with `DatadogCore` tests
/// Right now this is a copy & paste from `DatadogTests`. Sharing this implementation will only be possible
/// after we create a common module that facilitates tests.
struct Deflate {
    /// Decompresses the data format using the `ZLIB` compression algorithm.
    ///
    /// The provided data format must be ZLIB Compressed Data Format as described in IETF RFC 1950
    /// https://datatracker.ietf.org/doc/html/rfc1950
    ///
    /// - Parameters:
    ///   - data: The compressed data.
    ///   - capacity: Capacity of the allocated memory to contain the decoded data. 1MB by default.
    /// - Returns: Decompressed data.
    static func decode(_ data: Data, capacity: Int = 1.MB) -> Data? {
        // Skip `deflate` header (2 bytes) and checksum (4 bytes)
        // validations and inflate raw deflated data.
        let range = 2..<data.count - 4
        return decompress(data.subdata(in: range), capacity: capacity)
    }

    /// Decompresses the data using the `ZLIB` compression algorithm.
    ///
    /// The `Compression` library implements the zlib encoder at level 5 only. This compression level
    /// provides a good balance between compression speed and compression ratio.
    ///
    /// This inflate implementation uses `compression_decode_buffer(_:_:_:_:_:_:)`
    /// from the `Compression` framework by allocating a destination buffer of size `capacity`
    /// and copying the result into a `Data` structure
    ///
    /// ref. https://developer.apple.com/documentation/compression/1481000-compression_decode_buffer
    ///
    /// - Parameters:
    ///   - data: Raw deflated data stream.
    ///   - capacity: Capacity of the allocated memory to contain the decoded data. 1MB by default.
    /// - Returns: Decompressed data.
    static func decompress(_ data: Data, capacity: Int = 1.MB) -> Data? {
        data.withUnsafeBytes {
            guard let ptr = $0.bindMemory(to: UInt8.self).baseAddress else {
                return nil
            }

            let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: capacity)
            defer { buffer.deallocate() }

            // Returns the number of bytes written to the destination buffer after
            // decompressing the input. If there is not enough space in the destination
            // buffer to hold the entire decompressed output, the function writes the
            // first dst_size bytes to the buffer and returns dst_size. Note that this
            // behavior differs from that of `compression_encode_buffer(_:_:_:_:_:_:)`.
            let size = compression_decode_buffer(buffer, capacity, ptr, data.count, nil, COMPRESSION_ZLIB)
            return Data(bytes: buffer, count: size)
        }
    }
}
