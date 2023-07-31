/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

/// A type, writing data.
public protocol Writer {
    /// Encodes given encodable value and metadata, and writes to the destination.
    /// - Parameter value: Encodable value to write.
    /// - Parameter metadata: Encodable metadata to write.
    func write<T: Encodable, M: Encodable>(value: T, metadata: M?)
}

extension Writer {
    /// Encodes given encodable value and writes to the destination.
    /// Uses `write(value:metadata:)` with `nil` metadata.
    /// - Parameter value: Encodable value to write.
    public func write<T: Encodable>(value: T) {
        let metadata: Data? = nil
        write(value: value, metadata: metadata)
    }
}
