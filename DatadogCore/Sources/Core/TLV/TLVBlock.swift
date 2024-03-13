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
    case bytesLengthExceedsLimit(limit: UInt64)
    case dataAllocationFailure
    case endOfStream
}

internal protocol TLVBlockType {
    associatedtype RawValue = UInt16
    init?(rawValue: RawValue)
    var rawValue: RawValue { get }
}

/// A data block in defined by its type and a byte sequence.
///
/// A block can be serialized in data stream by following TLV format.
internal struct TLVBlock<BlockType: TLVBlockType> {
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
    func serialize(maxLength: UInt64 = MAX_DATA_LENGTH) throws -> Data {
        var buffer = Data()
        // T
        withUnsafeBytes(of: type.rawValue) { buffer.append(contentsOf: $0) }
        // L
        guard let length = TLVBlockSize(exactly: data.count), length <= maxLength else {
            throw TLVBlockError.bytesLengthExceedsLimit(limit: maxLength)
        }
        withUnsafeBytes(of: length) { buffer.append(contentsOf: $0) }
        // V
        buffer += data
        return buffer
    }
}
