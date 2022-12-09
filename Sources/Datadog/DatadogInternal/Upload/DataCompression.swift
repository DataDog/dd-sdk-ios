/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import Compression
import zlib

/// `Deflate` provides static methods to deflate `Data` for HTTP `deflate` `Content-Encoding`
/// using the `zlib` structure defined in IETF RFC 1950 with the deflate compression algorithm defined in
/// IETF RFC 1951.
///
/// ref:
/// - https://zlib.net/
/// - https://datatracker.ietf.org/doc/html/rfc1950
/// - https://datatracker.ietf.org/doc/html/rfc1951
/* public */ internal struct Deflate {
    /// Compresses the data into `ZLIB` data format.
    ///
    /// The `Compression` library implements the zlib encoder at level 5 only. This compression level
    /// provides a good balance between compression speed and compression ratio.
    ///
    /// The encoded format is the ZLIB Compressed Data Format as described in IETF RFC 1950
    /// https://datatracker.ietf.org/doc/html/rfc1950
    ///
    /// - Parameter data: Source data to deflate
    /// - Returns:  The compressed data format.
    /* public */ internal static func encode(_ data: Data) -> Data? {
        // 2 bytes header - defines the compression mode
        //
        // +---+---+
        // |CMF|FLG|
        // +---+---+
        //
        // ref. https://datatracker.ietf.org/doc/html/rfc1950#section-2.2
        //
        // The following header value is from `mw99/DataCompression` which applies
        // the same compression algorithm defined by `COMPRESSION_ZLIB`
        // ref. https://github.com/mw99/DataCompression
        let header = Data([0x78, 0x5e])

        guard
            let raw = compress(data),
            let checksum = adler32(data),
            // Returns `nil` when compression expands the data size.
            data.count > header.count + raw.count + checksum.count
        else { return nil }

        return header + raw + checksum
    }

    /// Compresses the data using the `ZLIB` compression algorithm.
    ///
    /// The `Compression` library implements the zlib encoder at level 5 only. This compression level
    /// provides a good balance between compression speed and compression ratio.
    ///
    /// The encoded format is the raw DEFLATE format as described in in IETF RFC 1951
    /// https://datatracker.ietf.org/doc/html/rfc1951
    ///
    /// This deflate implementation uses `compression_encode_buffer(_:_:_:_:_:_:)`
    /// from the `Compression` framework by allocating a destination buffer of source size and copying
    /// the result into a `Data` structure. In the worst possible case, where the compression expands the
    /// data size, the destination buffer becomes too small and deflation returns `nil`.
    ///
    /// ref. https://developer.apple.com/documentation/compression/1480986-compression_encode_buffer
    ///
    /// - Parameter data: Source data to deflate
    /// - Returns:  The compressed data. If the compressed data size is bigger than the source size,
    ///             or an error occurs, `nil` is returned.
    /* public */ internal static func compress(_ data: Data) -> Data? {
        return data.withUnsafeBytes {
            guard let ptr = $0.bindMemory(to: UInt8.self).baseAddress else {
                return nil
            }

            let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: data.count)
            defer { buffer.deallocate() }

            // The number of bytes written to the destination buffer after compressing
            // the input. If the funtion can't compress the entire input to fit into
            // the provided destination buffer, or an error occurs, 0 is returned.
            let size = compression_encode_buffer(buffer, data.count, ptr, data.count, nil, COMPRESSION_ZLIB)
            guard size > 0 else {
                return nil
            }

            return Data(bytes: buffer, count: size)
        }
    }

    /// Calculates the Adler32 checksum of the given data.
    ///
    /// An Adler-32 checksum is almost as reliable as a CRC-32 but can be computed much faster.
    ///
    /// - Parameter data: Data to compute the checksum.
    /// - Returns: The Adler-32 checksum.
    /* public */ internal static func adler32(_ data: Data) -> Data? {
        let adler: uLong? = data.withUnsafeBytes {
            guard let ptr = $0.bindMemory(to: Bytef.self).baseAddress else {
                return nil
            }

            // The Adler-32 checksum should be initialized to 1 as described in
            // https://datatracker.ietf.org/doc/html/rfc1950#section-8
            return zlib.adler32(1, ptr, uInt(data.count))
        }

        guard let checksum = adler else {
            return nil
        }

        var bytes = UInt32(checksum).bigEndian
        return Data(bytes: &bytes, count: MemoryLayout<UInt32>.size)
    }
}
