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
    private let internalMonitor: InternalMonitor?

    /// Files marked as read.
    private var filesRead: Set<String> = []

    init(
        dataFormat: DataFormat,
        orchestrator: FilesOrchestrator,
        encryption: DataEncryption? = nil,
        internalMonitor: InternalMonitor? = nil
    ) {
        self.dataFormat = dataFormat
        self.orchestrator = orchestrator
        self.encryption = encryption
        self.internalMonitor = internalMonitor
    }

    // MARK: - Reading batches

    func readNextBatch() -> Batch? {
        guard let file = orchestrator.getReadableFile(excludingFilesNamed: filesRead) else {
            return nil
        }

        do {
            let fileData = try decrypt(data: file.read())
            let batchData = dataFormat.prefixData + fileData + dataFormat.suffixData
            return Batch(data: batchData, file: file)
        } catch {
            internalMonitor?.sdkLogger.error("Failed to read data from file", error: error)
            return nil
        }
    }

    /// Decrypts data if encryption is available.
    ///
    /// When encryption is provided, the data is splitted using data-format separator, each slices
    /// is then decoded from base64 and decrypted. Data is finally re-joined with data-format separator.
    ///
    /// If no encryption, the data is returned.
    ///
    /// - Parameter data: The data to decrypt.
    /// - Returns: Decrypted data.
    private func decrypt(data: Data) -> Data {
        guard let encryption = encryption else {
            return data
        }

        var failure: String? = nil
        defer {
            failure.map { userLogger.error($0) }
        }

        return data
            // split data
            .split(separator: dataFormat.separatorByte)
            // decode base64 - report failure
            .compactMap {
                if let data = Data(base64Encoded: $0) {
                    return data
                }

                failure = "🔥 Failed to decode base64 data before decryption"
                return nil
            }
            // decrypt data - report failure
            .compactMap { (data: Data) in
                do {
                    return try encryption.decrypt(data: data)
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

    // MARK: - Accepting batches

    func markBatchAsRead(_ batch: Batch) {
        orchestrator.delete(readableFile: batch.file)
        filesRead.insert(batch.file.name)
    }
}
