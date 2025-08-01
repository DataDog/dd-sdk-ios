/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

public class FileWriterMock: Writer {
    public init() { }

    /// Recorded events.
    public private(set) var events: [Encodable] = []
    /// Recorded metadata.
    public private(set) var metadata: [Encodable] = []

    /// Adds an `Encodable` event to the events stack.
    ///
    /// - Parameter value: The event value to record.
    public func write<T: Encodable, M: Encodable>(value: T, metadata: M, completion: @escaping CompletionHandler) {
        events.append(value)
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
