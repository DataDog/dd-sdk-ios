/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

/// Reads data from files.
internal final class FileReader: Reader {
    /// Data reading format.
    private let dataFormat: DataFormat
    /// Orchestrator producing reference to readable file.
    private let orchestrator: FilesOrchestrator
    private let encryption: DataEncryption?

    /// Files marked as read.
    private var filesRead: Set<String> = []

    init(
        dataFormat: DataFormat,
        orchestrator: FilesOrchestrator,
        encryption: DataEncryption? = nil
    ) {
        self.dataFormat = dataFormat
        self.orchestrator = orchestrator
        self.encryption = encryption
    }

    // MARK: - Reading batches

    func readNextBatch() -> Batch? {
        guard let file = orchestrator.getReadableFile(excludingFilesNamed: filesRead) else {
            return nil
        }

        do {
            let fileData = try decode(data: file.read())
            let batchData = dataFormat.prefixData + fileData + dataFormat.suffixData
            return Batch(data: batchData, file: file)
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
    /// - Parameter data: The data to decode.
    /// - Returns: The decoded and formatted data.
    private func decode(data: Data) throws -> Data {
        let reader = DataBlockReader(data: data)

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
            // concat data
            .reduce(Data()) { $0 + $1 + [dataFormat.separatorByte] }
            // drop last separator
            .dropLast()
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
