/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

/// Block size binary type
internal typealias BlockSize = UInt32

/// Block type supported in data stream
internal enum BlockType: UInt16 {
    case event = 0x00
}

/// Reported errors while manipulateing data blocks.
internal enum DataBlockError: Error {
    case readOperationFailed(streamError: Error?)
    case invalidByteSequence
}

/// A data block in defined by its type and a byte sequence.
///
/// A block can be serialized in data stream by following TLV format.
internal struct DataBlock {
    /// Type describing the data block.
    let type: BlockType

    /// The data.
    var data: Data

    /// Returns a Data block in Type-Lenght-Value format.
    ///
    /// A block follow TLV with bytes aligned such as:
    ///
    ///     +-  2 bytes -+-   4 bytes   -+- n bytes -|
    ///     | block type | data size (n) |    data   |
    ///     +------------+---------------+-----------+
    ///
    /// - Returns: a data block in TLV.
    func serialize() -> Data {
        var buffer = Data()
        // T
        withUnsafeBytes(of: type.rawValue) { buffer.append(contentsOf: $0) }
        // L
        withUnsafeBytes(of: BlockSize(data.count)) { buffer.append(contentsOf: $0) }
        // V
        buffer += data
        return buffer
    }
}

/// A block reader can read TLV formatted blocks from a data input.
///
/// This class provides methods to iteratively retrieve a sequence of
/// `DataBlock`.
internal final class DataBlockReader {
    /// The input data stream.
    private let stream: InputStream

    /// Reads block from data input.
    ///
    /// At initilization, the reader will open a stream targeting the input
    /// data. The stream will be closed when the reader instance is deallocated.
    ///
    /// - Parameter data: The data input
    init(data: Data) {
        stream = InputStream(data: data)
        stream.open()
    }

    deinit {
        stream.close()
    }

    /// Reads the next data block started at current index in data input.
    ///
    /// This method returns `nil` when the entire data was traversed but no more
    /// block could be found.
    ///
    /// - Throws: `DataBlockError` while reading the input stream.
    /// - Returns: The next block or nil if none could be found.
    func next() throws -> DataBlock? {
        // look for the next known block
        while stream.hasBytesAvailable {
            // read an entire block before inferring the data type
            // to leave the stream in a usuable state if an unkown
            // type was encountered.
            let type = try readType()
            let data = try readData()

            if let type = BlockType(rawValue: type) {
                return DataBlock(type: type, data: data)
            }
        }

        return nil
    }

    /// Reads all data blocks from current index in the stream.
    ///
    /// - Throws: `DataBlockError` while reading the input stream.
    /// - Returns: The block sequence found in the input
    func all() throws -> [DataBlock] {
        var blocks: [DataBlock] = []

        while let block = try next() {
            blocks.append(block)
        }

        return blocks
    }

    /// Reads `lenght` bytes from stream.
    ///
    /// - Parameter lenght: The number of byte to read
    /// - Throws: `DataBlockError` while reading the input stream.
    /// - Returns: Data bytes from stream.
    private func read(lenght: Int) throws -> Data {
        var bytes = [UInt8](repeating: 0, count: lenght)
        let count = stream.read(&bytes, maxLength: lenght)

        if count < 0 {
            throw DataBlockError.readOperationFailed(streamError: stream.streamError)
        }

        guard count == lenght else {
            throw DataBlockError.invalidByteSequence
        }

        return Data(bytes)
    }

    /// Reads a block type.
    private func readType() throws -> BlockType.RawValue {
        let data = try read(lenght: MemoryLayout<BlockType.RawValue>.size)
        return data.withUnsafeBytes { $0.load(as: BlockType.RawValue.self) }
    }

    /// Reads  block data.
    private func readData() throws -> Data {
        let data = try read(lenght: MemoryLayout<BlockSize>.size)
        let size = data.withUnsafeBytes { $0.load(as: BlockSize.self) }
        return try read(lenght: Int(size))
    }
}
