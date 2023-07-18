/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

/// JSON encoder used to encode data.
private let jsonEncoder: JSONEncoder = .dd.default()

/// Writes data to files.
internal struct FileWriter: Writer {
    /// Orchestrator producing reference to writable file.
    let orchestrator: FilesOrchestratorType
    /// Algorithm to encrypt written data.
    let encryption: DataEncryption?
    /// If this writer should force creation of a new file for writing events.
    let forceNewFile: Bool

    // MARK: - Writing data

    /// Encodes given encodable value and metadata, and writes it to the file.
    /// If encryption is available, the data is encrypted before writing.
    /// - Parameters:
    ///  - value: Encodable value to write.
    ///  - metadata: Encodable metadata to write.
    func write<T: Encodable, M: Encodable>(value: T, metadata: M?) {
        do {
            var encoded: Data = .init()
            if let metadata = metadata {
                let encodedMetadata = try encode(encodable: metadata, blockType: .eventMetadata)
                encoded.append(encodedMetadata)
            }

            let encodedValue = try encode(encodable: value, blockType: .event)
            encoded.append(encodedValue)

            // Make sure both event and event metadata are written to the same file.
            // This is to avoid a situation where event is written to one file and event metadata to another.
            // If this happens, the reader will not be able to match event with its metadata.
            let writeSize = UInt64(encoded.count)
            let file = try forceNewFile ? orchestrator.getNewWritableFile(writeSize: writeSize) : orchestrator.getWritableFile(writeSize: writeSize)
            try file.append(data: encoded)
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
    private func encode(encodable: Encodable, blockType: BlockType) throws -> Data {
        let data = try jsonEncoder.encode(encodable)
        return try DataBlock(
            type: blockType,
            data: encrypt(data: data)
        ).serialize(
            maxLength: orchestrator.performance.maxObjectSize
        )
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
