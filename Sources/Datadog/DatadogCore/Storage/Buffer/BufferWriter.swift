/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

internal final class BufferWriter: Writer {

    let file: URL

    let queue: DispatchQueue

    /// JSON encoder used to encode data.
    let encoder: JSONEncoder

    let encryption: DataEncryption?

    init(
        file: URL,
        queue: DispatchQueue,
        encoder: JSONEncoder = .default(),
        encryption: DataEncryption? = nil
    ) {
        self.file = file
        self.queue = queue
        self.encoder = encoder
        self.encryption = encryption
    }
    
    /// Encodes given value to JSON data and writes it to the file.
    func write<T: Encodable>(value: T) {
        do {
            guard let writer = DataBlockWriter(url: file) else {
                throw InternalError(description: "Unable to open output file stream")
            }

            let block = try encode(event: value)
            try writer.write(block)
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
    private func encode<T: Encodable>(event: T) throws -> DataBlock {
        let data = try encoder.encode(event)
        return try DataBlock(
            type: .event,
            data: encrypt(data: data)
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
