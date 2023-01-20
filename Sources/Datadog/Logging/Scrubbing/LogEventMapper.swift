/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

/// Data scrubbing interface.
///
/// It takes `LogEvent` and call the callback with the modified `LogEvent`.
/// Not calling the callback will drop the event.
public protocol LogEventMapper {
    /// Maps a log event for data scrubbing.
    ///
    /// This method allow async call to the callback closure.
    ///
    /// - Parameters:
    ///   - event: The event to map.
    ///   - callback: The mapper callback with the new event.
    func map(event: LogEvent, callback: @escaping (LogEvent) -> Void)
}

/// Synchronous log event mapper.
///
/// The class take a flat-map closure parameter for event scrubbing
internal final class SyncLogEventMapper: LogEventMapper {
    let mapper: (LogEvent) -> LogEvent?

    init(_ mapper: @escaping (LogEvent) -> LogEvent?) {
        self.mapper = mapper
    }

    func map(event: LogEvent, callback: @escaping (LogEvent) -> Void) {
        mapper(event).map(callback)
    }
}
