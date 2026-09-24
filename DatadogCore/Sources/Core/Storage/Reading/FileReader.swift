/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

/// Reads data from files.
internal final class FileReader: Reader {
    /// Orchestrator producing reference to readable file.
    private let orchestrator: FilesOrchestratorType
    private let encryption: DataEncryption?
    /// Telemetry interface.
    private let telemetry: Telemetry

    /// Files marked as read.
    private var filesRead: Set<String> = []

    init(
        orchestrator: FilesOrchestratorType,
        encryption: DataEncryption?,
        telemetry: Telemetry
    ) {
        self.orchestrator = orchestrator
        self.telemetry = telemetry
        self.encryption = encryption
    }

    // MARK: - Reading batches

    func readFiles(limit: Int) -> [ReadableFile] {
        return orchestrator.getReadableFiles(excludingFilesNamed: filesRead, limit: limit)
    }

    func readBatch(from file: ReadableFile) -> Batch? {
        let decoded: DecodedBlocks
        do {
            decoded = try decode(stream: file.stream())
        } catch {
            DD.logger.error("(\(orchestrator.trackName)) Failed to read data from file", error: error)
            telemetry.error("(\(orchestrator.trackName)) Failed to read data from file", error: error)

            // A block exceeding the fixed size limit will never decode. Other read failures,
            // including a short read, may succeed on a later attempt, so keep the file.
            if let error = error as? TLVBlockError, case .bytesLengthExceedsLimit = error {
                markFileAsRead(file, reason: .invalid)
            }
            return nil
        }

        guard !decoded.hasEvent else {
            return Batch(dataBlocks: decoded.blocks, file: file)
        }

        guard !decoded.hasUndecryptableBlocks else {
            // No event could be decrypted. Retrying this file on every upload cycle can prevent
            // newer batches from being selected. `decode(stream:)` reported the failure.
            DD.logger.error("(\(orchestrator.trackName)) Failed to decrypt data")
            telemetry.error("(\(orchestrator.trackName)) Failed to decrypt data")
            markFileAsRead(file, reason: .invalid)
            return nil
        }

        // A batch holding no event has nothing to upload and never will: the file either holds no
        // complete event, or holds nothing at all. The latter is what a failed write leaves behind -
        // `getWritableFile()` creates the file before the data is appended to it, so an append that
        // fails, e.g. by running out of disk space, leaves an empty file. Delete it rather than
        // handing an empty batch to the uploader.
        DD.logger.error("(\(orchestrator.trackName)) Dropping batch with no event")
        telemetry.error("(\(orchestrator.trackName)) Dropping batch with no event")
        markFileAsRead(file, reason: .invalid)
        return nil
    }

    func markFileAsRead(_ file: ReadableFile, reason: BatchDeletedMetric.RemovalReason) {
        orchestrator.delete(readableFile: file, deletionReason: reason)
        filesRead.insert(file.name)
    }
}

private extension FileReader {
    struct DecodedBlocks {
        let blocks: [BatchDataBlock]
        let hasEvent: Bool
        let hasUndecryptableBlocks: Bool
    }

    /// Decodes input data
    ///
    /// The input data is expected to be a stream of `DataBlock`. Only block of type `event` are
    /// consumed and decrypted if encryption is available. Decrypted events are finally joined with
    /// data-format separator.
    ///
    /// - Parameter stream: The InputStream that provides data to decode.
    /// - Returns: The decoded and formatted data.
    func decode(stream: InputStream) throws -> DecodedBlocks {
        let reader = BatchDataBlockReader(
            input: stream,
            maxBlockLength: orchestrator.performance.maxObjectSize
        )

        var hasEvent = false
        var hasUndecryptableBlocks = false
        let blocks = try reader.all()
            .compactMap { dataBlock -> BatchDataBlock? in
                do {
                    let block = try decrypt(dataBlock: dataBlock)
                    if block.type == .event {
                        hasEvent = true
                    }
                    return block
                } catch {
                    hasUndecryptableBlocks = true
                    return nil
                }
            }

        return DecodedBlocks(blocks: blocks, hasEvent: hasEvent, hasUndecryptableBlocks: hasUndecryptableBlocks)
    }

    func decrypt(dataBlock: BatchDataBlock) throws -> BatchDataBlock {
        let decrypted = try decrypt(data: dataBlock.data)
        return BatchDataBlock(type: dataBlock.type, data: decrypted)
    }

    /// Decrypts data if encryption is available.
    ///
    /// If no encryption, the data is returned.
    ///
    /// - Parameter data: The data to decrypt.
    /// - Returns: Decrypted data.
    func decrypt(data: Data) throws -> Data {
        guard let encryption = encryption else {
            return data
        }

        return try encryption.decrypt(data: data)
    }
}
