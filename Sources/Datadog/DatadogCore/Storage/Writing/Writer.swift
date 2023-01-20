/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

/// A type, writing data.
public protocol Writer {
    func write<T: Encodable>(value: T)
}

/// Writer performing writes asynchronously on a given queue.
internal struct AsyncWriter: Writer {
    private let writer: Writer
    private let queue: DispatchQueue

    init(execute otherWriter: Writer, on queue: DispatchQueue) {
        self.writer = otherWriter
        self.queue = queue
    }

    func write<T>(value: T) where T: Encodable {
        queue.async { writer.write(value: value) }
    }
}

internal struct NOPWriter: Writer {
    func write<T>(value: T) where T: Encodable {}
}
