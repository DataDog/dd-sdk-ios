/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

/// Writes data to files.
internal final class FileWriter: Writer {
    /// Orchestrator producing reference to writable file.
    private let orchestrator: FilesOrchestrator
    /// JSON encoder used to encode data.
    private let jsonEncoder: JSONEncoder
    private let encryption: DataEncryption?

    init(
        orchestrator: FilesOrchestrator,
        encryption: DataEncryption? = nil
    ) {
        self.orchestrator = orchestrator
        self.jsonEncoder = .default()
        self.encryption = encryption
    }

    // MARK: - Writing data

    /// Encodes given value to JSON data and writes it to the file.
    func write<T: Encodable>(value: T) {
        do {
            let data = try encode(event: value)
            let file = try orchestrator.getWritableFile(writeSize: UInt64(data.count))
            try file.append(data: data)
        } catch {
            DD.logger.error("Failed to write data", error: error)
            DD.telemetry.error("Failed to write data to file", error: error)
        }
    }

    /// Encodes the given encodable value and encrypt it if encryption is available.
    ///
    /// The returned data format:
    ///
    ///     +- 2 bytes -+-  4 bytes -+- n bytes  -|
    ///     |    0x00   | block size | block data |
    ///     +-----------+------------+------------+
    ///
    /// Where the 2 first bytes represents the `block type` of
    /// an event.
    ///
    /// - Parameter event: The value to encode.
    /// - Returns: Data representation of the value.
    private func encode<T: Encodable>(event: T) throws -> Data {
        let data = try jsonEncoder.encode(event)
        return try DataBlock(
            type: .event,
            data: encrypt(data: data)
        ).serialize()
    }

    /// Encrypts data if encryption is available.
    ///
    /// If no encryption, the data is returned.
    ///
    /// - Parameter data: The data to encrypt.
    /// - Returns: Encrypted data.
    private func encrypt(data: Data) throws -> Data {
        guard let encryption = encryption else {
            return data
        }

        return try encryption.encrypt(data: data)
    }
}
