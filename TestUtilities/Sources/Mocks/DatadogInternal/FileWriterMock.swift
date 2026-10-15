/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

public class FileWriterMock: Writer {
    public init() { }

    /// Recorded event and metadata pairs, stored together so their order stays aligned under concurrent writes.
    @ReadWriteLock
    private var records: [(event: Encodable, metadata: Encodable)] = []

    /// Recorded events.
    public var events: [Encodable] { records.map { $0.event } }
    /// Recorded metadata.
    public var metadata: [Encodable] { records.map { $0.metadata } }

    /// Adds an `Encodable` event to the events stack.
    ///
    /// - Parameter value: The event value to record.
    public func write<T: Encodable, M: Encodable>(value: T, metadata: M, completion: @escaping CompletionHandler) {
        _records.mutate { $0.append((event: value, metadata: metadata)) }
        completion()
    }

    /// Returns all events of the given type.
    ///
    /// - Parameter type: The event type to retrieve.
    /// - Returns: A list of event of the give type.
    public func events<T>(ofType type: T.Type = T.self) -> [T] where T: Encodable {
        events.compactMap { $0 as? T }
    }

    /// Returns all metadata of the given type.
    ///
    /// - Parameter type: The metadata type to retrieve.
    /// - Returns: A list of metadata of the give type.
    public func metadata<T>(ofType type: T.Type = T.self) -> [T] where T: Encodable {
        metadata.compactMap { $0 as? T }
    }
}
