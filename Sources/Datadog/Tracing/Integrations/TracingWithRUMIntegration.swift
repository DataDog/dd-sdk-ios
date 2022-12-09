/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

/// Provides the current RUM context tags for produced `Spans`.
internal final class TracingWithRUMIntegration {
    /// The RUM attributes that should be added as Span tags.
    ///
    /// These attributes are synchronized using a fair and recursive lock.
    var attribues: [String: Encodable]? {
        get { synchronize { _attribues } }
        set { synchronize { _attribues = newValue } }
    }

    /// Fair and recursive lock.
    private let lock = NSRecursiveLock()

    /// Unsafe attributes.
    private var _attribues: [String: Encodable]?

    private func synchronize<T>(_ block: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return block()
    }
}
