/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
@_spi(Internal)
import DatadogInternal

/// Writes data to files.
internal struct FileWriter: Writer {
    /// Orchestrator producing reference to writable file.
    let orchestrator: FilesOrchestratorType
    /// Algorithm to encrypt written data.
    let encryption: DataEncryption?
    /// JSON encoder used to encode data.
    private let jsonEncoder: JSONEncoder
    /// Telemetry interface.
    let telemetry: Telemetry

    init(
        orchestrator: FilesOrchestratorType,
        encryption: DataEncryption?,
        telemetry: Telemetry,
        jsonEncoder: JSONEncoder = .dd.default()
    ) {
        self.orchestrator = orchestrator
        self.encryption = encryption
        self.jsonEncoder = jsonEncoder
        self.telemetry = telemetry
    }

    // MARK: - Writing data

    /// Encodes given encodable value and metadata, and writes it to the file.
    /// If encryption is available, the data is encrypted before writing.
    /// - Parameters:
    ///  - value: Encodable value to write.
    ///  - metadata: Encodable metadata to write.
    func write<T: Encodable, M: Encodable>(value: T, metadata: M?, completion: @escaping CompletionHandler) {
        defer { completion() }

        var encoded: Data = .init()
        if let metadata = metadata {
            do {
                try encode(value: metadata, blockType: .eventMetadata, into: &encoded)
            } catch {
                DD.logger.error("(\(orchestrator.trackName)) Failed to encode metadata", error: error)
                telemetry.error("(\(orchestrator.trackName)) Failed to encode metadata", error: error)
            }
        }

        do {
            try encode(value: value, blockType: .event, into: &encoded)
        } catch {
            DD.logger.error("(\(orchestrator.trackName)) Failed to encode value", error: error)
            telemetry.error("(\(orchestrator.trackName)) Failed to encode value", error: error)
            return
        }

        // Make sure both event and event metadata are written to the same file.
        // This is to avoid a situation where event is written to one file and event metadata to another.
        // If this happens, the reader will not be able to match event with its metadata.
        let writeSize = UInt64(encoded.count)
        let file: WritableFile
        do {
            file = try orchestrator.getWritableFile(writeSize: writeSize)
        } catch {
            DD.logger.error("(\(orchestrator.trackName)) Failed to get writable file for \(writeSize) bytes", error: error)
            telemetry.error("(\(orchestrator.trackName)) Failed to get writable file for \(writeSize) bytes", error: error)
            return
        }

        do {
            try file.append(data: encoded)
#if DD_BENCHMARK
            bench.meter.counter(metric: "ios.benchmark.bytes_written")
                .increment(by: encoded.count, attributes: ["track": orchestrator.trackName])
#endif
        } catch {
            DD.logger.error("(\(orchestrator.trackName)) Failed to write \(writeSize) bytes to file", error: error)
            telemetry.error("(\(orchestrator.trackName)) Failed to write \(writeSize) bytes to file", error: error)
        }
    }

    /// Encodes the given encodable value, encrypts it if encryption is available, and appends it
    /// to the given buffer.
    ///
    /// The appended data format:
    ///
    ///     +- 2 bytes -+-  4 bytes -+- n bytes  -|
    ///     |    0x00   | block size | block data |
    ///     +-----------+------------+------------+
    ///
    /// Where the 2 first bytes represents the `block type` of
    /// an event.
    ///
    /// The value is encoded, encrypted and length-checked before any byte is appended, so a thrown
    /// error leaves `buffer` unchanged — a partially appended block can never be written to disk.
    ///
    /// - Parameters:
    ///   - value: The value to encode.
    ///   - blockType: The type of the block to append.
    ///   - buffer: The buffer to append the serialized block to.
    private func encode<T: Encodable>(value: T, blockType: BatchBlockType, into buffer: inout Data) throws {
        let data = try jsonEncoder.dd.encodeWithAttributeRecovery(value)
        try BatchDataBlock(
            type: blockType,
            data: encrypt(data: data)
        ).serialize(
            into: &buffer,
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
