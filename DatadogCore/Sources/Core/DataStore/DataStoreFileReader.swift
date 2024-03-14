/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

internal enum DataStoreFileReadingError: Error {
    /// Indicates unexpected TLV blocks encountered during file reading.
    case unexpectedBlocks([DataStoreBlockType])
    /// Indicates unexpected order of TLV blocks encountered during file reading.
    case unexpectedBlocksOrder([DataStoreBlockType])
    /// Indicates that the data size is less than the size of the desired type to read from the value of a TLV block.
    case insufficientVersionBytes
}

internal struct DataStoreFileReader {
    internal enum Constants {
        /// The maximum length of value block.
        static let maxBlockLength = DataStoreFileWriter.Constants.maxDataLength
    }

    let file: File

    func read() throws -> (Data, DataStoreKeyVersion) {
        let reader = DataStoreBlockReader(
            input: try file.stream(),
            maxBlockLength: Constants.maxBlockLength
        )
        let blocks = try reader.all()

        guard blocks.count == 2 else {
            throw DataStoreFileReadingError.unexpectedBlocks(blocks.map { $0.type })
        }
        guard blocks[0].type == .version, blocks[1].type == .data else {
            throw DataStoreFileReadingError.unexpectedBlocksOrder(blocks.map { $0.type })
        }

        let version: DataStoreKeyVersion = try value(from: blocks[0].data)
        let data = blocks[1].data

        return (data, version)
    }

    // MARK: - Decoding

    private func value<T: FixedWidthInteger>(from data: Data) throws -> T {
        guard data.count >= MemoryLayout<T>.size else {
            throw DataStoreFileReadingError.insufficientVersionBytes
        }

        return data.withUnsafeBytes { $0.load(as: T.self) }
    }
}
