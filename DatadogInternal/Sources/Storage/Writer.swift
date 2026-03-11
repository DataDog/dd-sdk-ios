/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

/// A type, writing data.
public protocol Writer: Sendable {
    /// Encodes given encodable value and metadata, and writes to the destination.
    /// - Parameters:
    ///   - value: Encodable value to write.
    ///   - metadata: Encodable metadata to write.
    func write<T: Encodable, M: Encodable>(value: T, metadata: M?) async
}

extension Writer {
    /// Encodes given encodable value and writes to the destination.
    /// Uses `write(value:metadata:)` with `nil` metadata.
    ///
    /// - Parameter value: Encodable value to write.
    public func write<T: Encodable>(value: T) async {
        let metadata: Data? = nil
        await write(value: value, metadata: metadata)
    }

    /// Encodes given encodable value and metadata, and writes to the destination.
    ///
    /// Fire-and-forget variant for use in synchronous contexts.
    /// Encoding and I/O are dispatched to a `Task`.
    ///
    /// - Parameters:
    ///   - value: Encodable value to write.
    ///   - metadata: Encodable metadata to write.
    public func write<T: Encodable, M: Encodable>(value: T, metadata: M?) {
        let writer = UnsafeSendableWriter(writer: self, value: value, metadata: metadata)
        Task { await writer.perform() }
    }

    /// Encodes given encodable value and writes to the destination.
    ///
    /// Fire-and-forget variant for use in synchronous contexts.
    /// Encoding and I/O are dispatched to a `Task`.
    ///
    /// - Parameter value: Encodable value to write.
    public func write<T: Encodable>(value: T) {
        let metadata: Data? = nil
        let writer = UnsafeSendableWriter(writer: self, value: value, metadata: metadata)
        Task { await writer.perform() }
    }
}

/// Wraps a non-Sendable `Encodable` value and a `Writer` so they can cross
/// a `Task` isolation boundary. The caller must ensure the captured value is
/// not accessed concurrently after constructing this box.
private struct UnsafeSendableWriter<T: Encodable, M: Encodable>: @unchecked Sendable {
    let writer: any Writer
    let value: T
    let metadata: M?

    func perform() async {
        await writer.write(value: value, metadata: metadata)
    }
}
