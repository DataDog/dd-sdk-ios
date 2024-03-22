/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

/// A block reader can read TLV formatted blocks from a data input.
///
/// This class provides methods to iteratively retrieve a sequence of
/// `DataBlock`.
internal final class TLVBlockReader<BlockType> where BlockType: RawRepresentable, BlockType.RawValue == UInt16 {
    /// The input data stream.
    private let stream: InputStream

    /// Maximum data length of a block.
    private let maxBlockLength: UInt64

    /// Reads block from an input stream.
    ///
    /// At initilization, the reader will open the stream, it will be closed
    /// when the reader instance is deallocated.
    ///
    /// - Parameter stream: The input stream
    init(
        input stream: InputStream,
        maxBlockLength: UInt64 = MAX_DATA_LENGTH
    ) {
        self.maxBlockLength = maxBlockLength
        self.stream = stream
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
    /// - Throws: `TLVBlockError` while reading the input stream.
    /// - Returns: The next block or nil if none could be found.
    func next() throws -> TLVBlock<BlockType>? {
        // look for the next known block
        while true {
            do {
                return try readBlock()
            } catch TLVBlockError.invalidDataType {
                continue
            } catch TLVBlockError.endOfStream {
                // Some streams won't return false for hasBytesAvailable until a read is attempted
                return nil
            } catch {
                throw error
            }
        }
    }

    /// Reads all data blocks from current index in the stream.
    ///
    /// - Throws: `TLVBlockError` while reading the input stream.
    /// - Returns: The block sequence found in the input
    func all() throws -> [TLVBlock<BlockType>] {
        var blocks: [TLVBlock<BlockType>] = []

        while let block = try next() {
            blocks.append(block)
        }

        return blocks
    }

    /// Reads `length` bytes from stream.
    ///
    /// - Parameter length: The number of byte to read
    /// - Throws: `TLVBlockError` while reading the input stream.
    /// - Returns: Data bytes from stream.
    private func read(length: Int) throws -> Data {
        guard length > 0 else {
            return Data()
        }

        // Load from stream directly to data without unnecessary copies
        var data = Data(count: length)
        let count: Int = try data.withUnsafeMutableBytes {
            guard let buffer = $0.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                throw TLVBlockError.dataAllocationFailure
            }
            return stream.read(buffer, maxLength: length)
        }

        if count < 0 {
            throw TLVBlockError.readOperationFailed(
                streamStatus: stream.streamStatus,
                streamError: stream.streamError
            )
        }

        if count == 0 {
            throw TLVBlockError.endOfStream
        }

        guard count == length else {
            throw TLVBlockError.invalidByteSequence(expected: length, got: count)
        }

        return data
    }

    /// Reads a block.
    private func readBlock() throws -> TLVBlock<BlockType> {
        // read an entire block before inferring the data type
        // to leave the stream in a usuable state if an unkown
        // type was encountered.
        let type = try readType()
        let data = try readData()

        guard let type = BlockType(rawValue: type) else {
            throw TLVBlockError.invalidDataType(got: type)
        }

        return TLVBlock(type: type, data: data)
    }

    /// Reads a block type.
    private func readType() throws -> BlockType.RawValue {
        let data = try read(length: MemoryLayout<BlockType.RawValue>.size)
        return data.withUnsafeBytes { $0.load(as: BlockType.RawValue.self) }
    }

    /// Reads block data.
    private func readData() throws -> Data {
        let data = try read(length: MemoryLayout<TLVBlockSize>.size)
        let size = data.withUnsafeBytes { $0.load(as: TLVBlockSize.self) }

        // even if `Int` is able to represent all `TLVBlockSize` on 64 bit
        // arch, we make sure to avoid overflow and get the exact data
        // length.
        // Additionally check that length hasn't been corrupted and
        // we don't try to generate a huge buffer.
        guard let length = Int(exactly: size), length <= maxBlockLength else {
            throw TLVBlockError.bytesLengthExceedsLimit(limit: maxBlockLength)
        }

        return try read(length: length)
    }
}
extension TLVBlockError: CustomStringConvertible {
    var description: String {
        switch self {
        case .readOperationFailed(let status, let error):
            let error = error.map { "\($0)" } ?? "(null)"
            return "DataBlock read operation failed with stream status: \(status.rawValue), error: \(error)"
        case .invalidDataType(let type):
            return "Invalid DataBlock type: \(type)"
        case .invalidByteSequence(let expected, let got):
            return "Invalid bytes sequence in DataBlock: expected \(expected) bytes but got \(got)"
        case .bytesLengthExceedsLimit(let limit):
            return "DataBlock length exceeds limit of \(limit) bytes"
        case .dataAllocationFailure:
            return "Allocation failure while reading stream"
        case .endOfStream:
            return "Reach end of stream while reading data blocks"
        }
    }
}
