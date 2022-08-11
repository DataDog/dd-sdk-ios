/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

/// A type, writing data.
internal protocol Writer {
    func write<T: Encodable>(value: T)
}

/// Writer performing writes asynchronously on a given queue.
internal protocol AsyncWriter: Writer {
    /// Queue used for asynchronous writes.
    var queue: DispatchQueue { get }

    func flushAndCancelSynchronously()
}
