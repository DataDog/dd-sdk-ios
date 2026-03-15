/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

public class FileWriterMock: Writer, @unchecked Sendable {
    public init() { }

    @ReadWriteLock
    private var _events: [Encodable] = []
    @ReadWriteLock
    private var _metadata: [Encodable] = []

    /// Recorded events.
    public var events: [Encodable] { _events }
    /// Recorded metadata.
    public var metadata: [Encodable] { _metadata }

    /// Callback called after an event is written.
    public var onWrite: (() -> Void)?

    /// Waits asynchronously until at least `count` events have been written.
    /// Useful when writes happen inside Tasks that the test cannot `await` directly.
    public func waitForEvents(count: Int, timeout: TimeInterval = 1.0) async {
        let deadline = Date().addingTimeInterval(timeout)
        while events.count < count && Date() < deadline {
            try? await Task.sleep(nanoseconds: 10_000_000) // 10ms
        }
    }

    /// Adds an `Encodable` event to the events stack.
    ///
    /// - Parameter value: The event value to record.
    public func write<T: Encodable, M: Encodable>(value: T, metadata: M?) {
        __events.mutate { $0.append(value) }
        if let metadata = metadata {
            __metadata.mutate { $0.append(metadata) }
        }
        onWrite?()
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
