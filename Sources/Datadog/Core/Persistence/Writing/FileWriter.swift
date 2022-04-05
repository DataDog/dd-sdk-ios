/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

/// Writes data to files.
internal final class FileWriter: Writer {
    /// Data writing format.
    private let dataFormat: DataFormat
    /// Orchestrator producing reference to writable file.
    private let orchestrator: FilesOrchestrator
    /// JSON encoder used to encode data.
    private let jsonEncoder: JSONEncoder
    private let encryption: DataEncryption?
    private let internalMonitor: InternalMonitor?

    init(
        dataFormat: DataFormat,
        orchestrator: FilesOrchestrator,
        encryption: DataEncryption? = nil,
        internalMonitor: InternalMonitor? = nil
    ) {
        self.dataFormat = dataFormat
        self.orchestrator = orchestrator
        self.jsonEncoder = .default()
        self.encryption = encryption
        self.internalMonitor = internalMonitor
    }

    // MARK: - Writing data

    /// Encodes given value to JSON data and writes it to the file.
    func write<T: Encodable>(value: T) {
        do {
            var data = try encode(value: value)
            let file = try orchestrator.getWritableFile(writeSize: UInt64(data.count))

            if try file.size() > 0 {
                data.insert(dataFormat.separatorByte, at: 0)
            }

            try file.append(data: data)
        } catch {
            userLogger.error("🔥 Failed to write data: \(error)")
            internalMonitor?.sdkLogger.error("Failed to write data to file", error: error)
        }
    }

    /// Encodes the given encodable value and encrypt it if encryption is available.
    ///
    /// If encryption is available, encryption result is base64 encoded.
    ///
    /// - Parameter value: The value to encode.
    /// - Returns: Data representation of the value.
    private func encode<T: Encodable>(value: T) throws -> Data {
        let data = try jsonEncoder.encode(value)

        guard let encryption = encryption else {
            return data
        }

        return try encryption.encrypt(data: data)
            .base64EncodedData()
    }
}
