/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import zlib

internal struct SRCompression {
    /// Compresses the data into ZLIB Compressed Data Format as described in IETF RFC 1950.
    ///
    /// To meet `dogweb` expectation for Session Replay, it uses compression level `6` and `Z_SYNC_FLUSH`
    /// + `Z_FINISH` flags for flushing compressed data to the output. This allows the receiver (SR player) to
    /// concatenate succeeding chunks of compressed data and perform inflate only once instead of decompressing
    /// each chunk individually.
    static func compress(data: Data) throws -> Data {
        return try zcompress(
            data: data,
            level: 6,
            // To ensure zlib has enough size in its buffer, we allocate chunk size for worst-case scenario (compression of 1 byte):
            //
            // > Ref.: https://github.com/madler/zlib/blob/04f42ceca40f73e2978b50e93806c2a18c1281fc/compress.c#L15
            // > destination buffer (...) must be at least 0.1% larger than sourceLen plus 12 bytes
            chunk: Int((Double(data.count) * 1.01).rounded(.up) + 12)
        )
    }

    private static func zcompress(data: Data, level: Int, chunk: Int) throws -> Data {
        // z_streamp->next_in requires mutable bytes
        var m_data = data

        return try m_data.withUnsafeMutableBytes {
            guard let ptr = $0.bindMemory(to: Bytef.self).baseAddress else {
                throw InternalError(description: "zlib compress: failed to bind data memory")
            }

            let buffer = UnsafeMutablePointer<Bytef>.allocate(capacity: chunk)
            defer { buffer.deallocate() }

            let stream = z_streamp.allocate(capacity: 1)
            defer { stream.deallocate() }

            // Configure initial state of zlib:
            // - Setting `Z_NULL` for memory allocation routines means that zlib will use its default implementations.
            // - This mutable state is shared between our code and zlib. In later do / while iterations zlib will leverage
            // it to empower `deflate()` calls and walk through original `data` with `next_in` and `avail_in`.
            // - A good explanation of how to use `z_stream`: https://zlib.net/zlib_how.html
            // - A practical explanation of different ZLIB APIs: https://github.com/madler/zlib/blob/cacf7f1d4e3d44d871b605da3b647f07d718623f/zlib.h
            stream.pointee.next_in = ptr // pointer to next input byte
            stream.pointee.avail_in = uInt(data.count) // number of bytes available at next_in
            stream.pointee.total_out = 0 // total number of bytes output so far
            stream.pointee.zalloc = nil // Z_NULL: nil points to addr 0x0, equivalent of Z_NULL
            stream.pointee.zfree = nil // Z_NULL
            stream.pointee.opaque = nil // Z_NULL

            var result = deflateInit_(stream, Int32(level), ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size))
            defer { deflateEnd(stream) } // free the allocated zlib state

            guard result == Z_OK else {
                throw InternalError(description: "zlib deflateInit_() error: \(zerror(result)) when compressing data of \(data.count) bytes")
            }

            var c_data = Data()
            repeat {
                stream.pointee.next_out = buffer
                stream.pointee.avail_out = uInt(chunk)

                let flush = stream.pointee.avail_in == 0 ? Z_FINISH : Z_SYNC_FLUSH // if no more data to compress
                result = deflate(stream, flush)

                let count = chunk - Int(stream.pointee.avail_out)
                c_data.append(buffer, count: count)
            } while result == Z_OK

            guard result == Z_STREAM_END else {
                throw InternalError(description: "zlib deflate() error: \(zerror(result)) when compressing data of \(data.count) bytes")
            }

            return c_data
        }
    }

    private static func zerror(_ code: Int32) -> String {
        switch code {
        case Z_ERRNO:
            return "Z_ERRNO"
        case Z_STREAM_ERROR:
            return "Z_STREAM_ERROR"
        case Z_DATA_ERROR:
            return "Z_DATA_ERROR"
        case Z_MEM_ERROR:
            return "Z_MEM_ERROR"
        case Z_BUF_ERROR:
            return "Z_BUF_ERROR"
        case Z_VERSION_ERROR:
            return "Z_VERSION_ERROR"
        default:
            return "unknown error (\(code))"
        }
    }
}
