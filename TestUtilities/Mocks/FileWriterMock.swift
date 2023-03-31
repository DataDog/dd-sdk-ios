/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import Datadog

public class FileWriterMock: Writer {
    public init() { }

    /// Recorded events.
    internal private(set) var events: [Encodable] = []

    /// Adds an `Encodable` event to the events stack.
    ///
    /// - Parameter value: The event value to record.
    public func write<T>(value: T) where T: Encodable {
        events.append(value)
    }

    /// Returns all events of the given type.
    ///
    /// - Parameter type: The event type to retrieve.
    /// - Returns: A list of event of the give type.
    public func events<T>(ofType type: T.Type = T.self) -> [T] where T: Encodable {
        events.compactMap { $0 as? T }
    }
}
