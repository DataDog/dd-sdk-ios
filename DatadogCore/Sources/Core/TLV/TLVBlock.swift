/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

/// Block size binary type
internal typealias TLVBlockSize = UInt32

/// Reported errors while manipulating data blocks.
internal enum TLVBlockError: Error {
    case readOperationFailed(streamStatus: Stream.Status, streamError: Error?)
    case invalidDataType(got: Any)
    case invalidByteSequence(expected: Int, got: Int)
    case bytesLengthExceedsLimit(length: TLVBlockSize?, limit: TLVBlockSize)
    case dataAllocationFailure
    case endOfStream
}
/// A data block in defined by its type and a byte sequence.
///
/// A block can be serialized in data stream by following TLV format.
internal struct TLVBlock<BlockType> where BlockType: RawRepresentable, BlockType.RawValue == UInt16 {
    /// Type describing the data block.
    let type: BlockType

    /// The data.
    var data: Data

    /// Returns a Data block in Type-Length-Value format.
    ///
    /// A block follow TLV with bytes aligned such as:
    ///
    ///     +-  2 bytes -+-   4 bytes   -+- n bytes -|
    ///     | block type | data size (n) |    data   |
    ///     +------------+---------------+-----------+
    /// - Parameter maxLength: Maximum data length of a block.
    /// - Returns: a data block in TLV.
    func serialize(maxLength: TLVBlockSize = maxTLVDataLength) throws -> Data {
        var buffer = Data()
        try serialize(into: &buffer, maxLength: maxLength)
        return buffer
    }

    /// Appends this block, in Type-Length-Value format, at the end of the given buffer.
    ///
    /// Appending in place avoids the intermediate `Data` allocation and the extra copy of the whole
    /// payload that `serialize(maxLength:)` incurs when its result is appended to another buffer.
    /// Callers accumulating several blocks should prefer this method.
    ///
    /// The block length is validated before any byte is appended, so a thrown error leaves `buffer`
    /// unchanged and safe to keep using.
    ///
    /// - Parameters:
    ///   - buffer: The buffer to append this block to.
    ///   - maxLength: Maximum data length of a block.
    func serialize(into buffer: inout Data, maxLength: TLVBlockSize = maxTLVDataLength) throws {
        guard let length = TLVBlockSize(exactly: data.count), length <= maxLength else {
            throw TLVBlockError.bytesLengthExceedsLimit(length: TLVBlockSize(exactly: data.count), limit: maxLength)
        }
        // T
        withUnsafeBytes(of: type.rawValue) { buffer.append(contentsOf: $0) }
        // L
        withUnsafeBytes(of: length) { buffer.append(contentsOf: $0) }
        // V
        buffer += data
    }
}
