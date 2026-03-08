/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

/// Declares that a type can produce a sequence of values over time via `AsyncStream`.
///
/// Unlike the previous callback-based `ContextValuePublisher`, this protocol uses
/// structured concurrency: consumers iterate `values` with `for await`, and
/// cancellation is automatic when the consuming `Task` is cancelled.
///
/// Example usage with `DatadogContextProvider`:
///
///     let source = NWPathMonitorSource()
///     provider.observe(source) { $0.networkConnectionInfo = $1 }
///
internal protocol ContextValueSource: Sendable {
    /// The kind of values produced by this source.
    associatedtype Value

    /// The value before any asynchronous updates arrive.
    var initialValue: Value { get }

    /// An asynchronous stream of value updates.
    /// The stream should terminate (via `continuation.finish()`) when the
    /// source is no longer producing values, or it can stay open indefinitely
    /// (cancellation of the consuming task will handle cleanup).
    var values: AsyncStream<Value> { get }
}
