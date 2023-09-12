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

    func readNextBatch(context: DatadogContext) -> Batch? {
        guard let file = orchestrator.getReadableFile(excludingFilesNamed: filesRead, context: context) else {
            return nil
        }

        do {
            let dataBlocks = try decode(stream: file.stream())
            return Batch(dataBlocks: dataBlocks, file: file)
        } catch {
            telemetry.error("Failed to read data from file", error: error)
            return nil
        }
    }

    /// Decodes input data
    ///
    /// The input data is expected to be a stream of `DataBlock`. Only block of type `event` are
    /// consumed and decrypted if encryption is available. Decrypted events are finally joined with
    /// data-format separator.
    ///
    /// - Parameter stream: The InputStream that provides data to decode.
    /// - Returns: The decoded and formatted data.
    private func decode(stream: InputStream) throws -> [DataBlock] {
        let reader = DataBlockReader(
            input: stream,
            maxBlockLength: orchestrator.performance.maxObjectSize
        )

        var failure: String? = nil
        defer {
            failure.map { DD.logger.error($0) }
        }

        return try reader.all()
            .compactMap { dataBlock in
                do {
                    return try decrypt(dataBlock: dataBlock)
                } catch {
                    failure = "🔥 Failed to decrypt data with error: \(error)"
                    return nil
                }
            }
    }

    private func decrypt(dataBlock: DataBlock) throws -> DataBlock {
        let decrypted = try decrypt(data: dataBlock.data)
        return DataBlock(type: dataBlock.type, data: decrypted)
    }

    /// Decrypts data if encryption is available.
    ///
    /// If no encryption, the data is returned.
    ///
    /// - Parameter data: The data to decrypt.
    /// - Returns: Decrypted data.
    private func decrypt(data: Data) throws -> Data {
        guard let encryption = encryption else {
            return data
        }

        return try encryption.decrypt(data: data)
    }

    // MARK: - Accepting batches

    func markBatchAsRead(_ batch: Batch, reason: BatchDeletedMetric.RemovalReason, context: DatadogContext) {
        orchestrator.delete(readableFile: batch.file, deletionReason: reason, context: context)
        filesRead.insert(batch.file.name)
    }
}
