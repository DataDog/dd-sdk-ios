/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

/// Block size binary type
internal typealias BlockSize = UInt32

/// Block type supported in data stream
public enum BlockType: UInt16 {
    case event = 0x00
}

/// Reported errors while manipulating data blocks.
internal enum DataBlockError: Error {
    case readOperationFailed(streamError: Error?)
    case writeOperationFailed(streamError: Error?)
    case invalidByteSequence
    case dataLenghtExceedsLimit
    case noSpaceAvailable
    case endOfBuffer
}

/// A data block in defined by its type and a byte sequence.
///
/// A block can be serialized in data stream by following TLV format.
public struct DataBlock {
    /// Type describing the data block.
    public let type: BlockType

    /// The data.
    public var data: Data

    /// Returns a Data block in Type-Lenght-Value format.
    ///
    /// A block follow TLV with bytes aligned such as:
    ///
    ///     +-  2 bytes -+-   4 bytes   -+- n bytes -|
    ///     | block type | data size (n) |    data   |
    ///     +------------+---------------+-----------+
    ///
    /// - Returns: a data block in TLV.
    func serialize() throws -> Data {
        var buffer = Data()
        // T
        withUnsafeBytes(of: type.rawValue) { buffer.append(contentsOf: $0) }
        // L
        guard let length = BlockSize(exactly: data.count) else {
            throw DataBlockError.dataLenghtExceedsLimit
        }
        withUnsafeBytes(of: length) {
            buffer.append(contentsOf: $0)
        }
        // V
        buffer += data
        return buffer
    }
}
