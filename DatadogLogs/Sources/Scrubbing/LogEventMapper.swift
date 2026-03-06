/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

/// Data scrubbing interface.
///
/// It takes a `LogEvent` and returns the modified event.
/// Returning `nil` will drop the event.
public protocol LogEventMapper: Sendable {
    /// Maps a log event for data scrubbing.
    ///
    /// - Parameter event: The event to map.
    /// - Returns: The mapped event, or `nil` to drop it.
    func map(event: LogEvent) async -> LogEvent?
}

/// Synchronous log event mapper.
///
/// Wraps a flat-map closure for event scrubbing.
internal final class SyncLogEventMapper: LogEventMapper, @unchecked Sendable {
    let mapper: (LogEvent) -> LogEvent?

    init(_ mapper: @escaping (LogEvent) -> LogEvent?) {
        self.mapper = mapper
    }

    func map(event: LogEvent) async -> LogEvent? {
        mapper(event)
    }
}
