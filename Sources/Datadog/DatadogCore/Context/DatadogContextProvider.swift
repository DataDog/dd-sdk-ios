/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

/// Provides thread-safe access to Datadog Context.
///
/// The context can be accessed asynchronously for reads and writes.
///
///     provider.read { context in
///         // read value from the current context
///     }
///
///     provider.write { context in
///         // set mutable values of the context
///     }
///
/// The provider performs reads concurrently but uses barrier block for
/// write operations.
internal final class DatadogContextProvider {
    /// The current `context`.
    ///
    /// The value must be accessed from the `queue` only.
    private var context: DatadogContext

    /// The queue used to synchronize the access to the `DatadogContext`.
    ///
    /// Concurrent queue is used for performant reads, `.barrier` must be used
    /// to make writes exclusive.
    private let queue = DispatchQueue(
        label: "com.datadoghq.core-context",
        attributes: .concurrent
    )

    /// Creates a context provider to perform reads and writes on the
    /// shared Datadog context.
    ///
    /// - Parameters:
    ///   - context: The context inital value.
    ///   - serverDateProvider: The server date provider to synchronize the `serverTimeOffset`
    ///                         parameter.
    init(
        context: DatadogContext,
        serverDateProvider: ServerDateProvider
    ) {
        self.context = context
        self.sync(with: serverDateProvider)
    }

    /// Reads to the `context` asynchronously, without blocking the caller thread.
    func read(block: @escaping (DatadogContext) -> Void) {
        queue.async { block(self.context) }
    }

    /// Reads to the `context` synchronously, without blocking the caller thread.
    func read() -> DatadogContext {
        queue.sync { self.context }
    }

    /// Writes to the `context` asynchronously, without blocking the caller thread.
    func write(block: @escaping (inout DatadogContext) -> Void) {
        queue.async(flags: .barrier) { block(&self.context) }
    }
}

extension DatadogContextProvider {
    /// Synchronise the context with the given server date provider.
    ///
    /// This method does not keep a strong reference to the provider,
    /// it only calls the `synchronize` method.
    ///
    /// - Parameter provider: The server date provider.
    func sync(with provider: ServerDateProvider) {
        provider.synchronize { offset in
            self.write { $0.serverTimeOffset = offset }
        }
    }
}
