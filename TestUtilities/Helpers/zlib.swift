/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import Compression

public struct zlib {
    /// Decompresses the data format using the `ZLIB` compression algorithm.
    ///
    /// The provided data format must be ZLIB Compressed Data Format as described in IETF RFC 1950
    /// https://datatracker.ietf.org/doc/html/rfc1950
    ///
    /// - Parameters:
    ///   - data: The compressed data.
    ///   - capacity: Capacity of the allocated memory to contain the decoded data. 1MB by default.
    /// - Returns: Decompressed data.
    public static func decode(_ data: Data, capacity: Int = 1_000_000) -> Data? {
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
    public static func decompress(_ data: Data, capacity: Int = 1_000_000) -> Data? {
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
