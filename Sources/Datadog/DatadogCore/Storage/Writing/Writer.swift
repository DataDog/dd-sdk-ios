/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

/// A type, writing data.
public protocol Writer {
    /// Writes given `value` to underlying file.
    ///
    /// - Parameters:
    ///   - value: data to be written.
    ///   - forceNewBatch: `true` to enforce that data will be written to a separate file than any previous data.
    ///                     Default is `false`, which means the core uses its own heuristic to split data between files.
    func write<T: Encodable>(value: T, forceNewBatch: Bool)
}

internal extension Writer {
    func write<T: Encodable>(value: T) {
        write(value: value, forceNewBatch: false)
    }
}

/// Writer performing writes asynchronously on a given queue.
internal protocol AsyncWriter: Writer {
    /// Queue used for asynchronous writes.
    var queue: DispatchQueue { get }

    func flushAndCancelSynchronously()
}
