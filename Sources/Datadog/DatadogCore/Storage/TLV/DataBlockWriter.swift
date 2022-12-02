/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

/// A block writer can read TLV formatted blocks from a data input.
///
/// This class provides methods to iteratively retrieve a sequence of
/// `DataBlock`.
internal final class DataBlockWriter {
    /// The input data stream.
    private let stream: OutputStream

    convenience init?(url: URL, append shouldAppend: Bool = true) {
        guard let stream = OutputStream(url: url, append: shouldAppend) else {
            return nil
        }

        self.init(output: stream)
    }

    /// Writes blocks from an output stream.
    ///
    /// At initilization, the writer will open the stream, it will be closed
    /// when the writer instance is deallocated.
    ///
    /// - Parameter stream: The output stream
    init(output stream: OutputStream) {
        self.stream = stream
        stream.open()
    }

    deinit {
        stream.close()
    }

    func write(_ block: DataBlock) throws {
        guard stream.hasSpaceAvailable else {
            throw DataBlockError.noSpaceAvailable
        }

        let data = try block.serialize()

        let count = try data.withUnsafeBytes {
            guard let ptr = $0.bindMemory(to: UInt8.self).baseAddress else {
                throw DataBlockError.writeOperationFailed(streamError: nil)
            }

            return stream.write(ptr, maxLength: data.count)
        }

        if count < 0 {
            throw DataBlockError.readOperationFailed(streamError: stream.streamError)
        }

        guard count == data.count else {
            throw DataBlockError.invalidByteSequence
        }
    }
}
