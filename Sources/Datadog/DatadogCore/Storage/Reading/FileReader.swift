/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

/// Reads data from files.
internal final class FileReader: Reader {
    /// Orchestrator producing reference to readable file.
    private let orchestrator: FilesOrchestratorType
    private let encryption: DataEncryption?

    /// Files marked as read.
    private var filesRead: Set<String> = []

    init(
        orchestrator: FilesOrchestratorType,
        encryption: DataEncryption? = nil
    ) {
        self.orchestrator = orchestrator
        self.encryption = encryption
    }

    // MARK: - Reading batches

    func readNextBatch() -> Batch? {
        guard let file = orchestrator.getReadableFile(excludingFilesNamed: filesRead) else {
            return nil
        }

        do {
            let events = try decode(stream: file.stream())
            return Batch(events: events, file: file)
        } catch {
            DD.telemetry.error("Failed to read data from file", error: error)
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
    private func decode(stream: InputStream) throws -> [Data] {
        let reader = DataBlockReader(
            input: stream,
            maxBlockLenght: orchestrator.performance.maxObjectSize
        )

        var failure: String? = nil
        defer {
            failure.map { DD.logger.error($0) }
        }

        return try reader.all()
            // get event blocks only
            .compactMap {
                switch $0.type {
                case .event:
                    return $0.data
                }
            }
            // decrypt data - report failure
            .compactMap { (data: Data) in
                do {
                    return try decrypt(data: data)
                } catch {
                    failure = "🔥 Failed to decrypt data with error: \(error)"
                    return nil
                }
            }
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

    func markBatchAsRead(_ batch: Batch) {
        orchestrator.delete(readableFile: batch.file)
        filesRead.insert(batch.file.name)
    }
}
