/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

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
///
/// The context provider can observe a ``ContextValueSource`` and apply its
/// updates to a specific context property:
///
///     let source = ServerOffsetSource(provider: serverDateProvider)
///     provider.observe(source) { $0.serverTimeOffset = $1 }
///
/// All observations will be cancelled when the provider is deallocated.
internal final class DatadogContextProvider: @unchecked Sendable {
    static let defaultQueue = DispatchQueue(
        label: "com.datadoghq.core-context",
        qos: .utility
    )
    /// The current `context`.
    ///
    /// The value must be accessed from the `queue` only.
    private var context: DatadogContext

    /// The queue used to synchronize the access to the `DatadogContext`.
    internal let queue: DispatchQueue

    /// List of receivers to invoke when the context changes.
    private var receivers: [@Sendable (DatadogContext) -> Void]

    /// Tasks consuming `ContextValueSource` streams.
    private var observations: [Task<Void, Never>]

    /// Creates a context provider to perform reads and writes on the
    /// shared Datadog context.
    ///
    /// - Parameters:
    ///   - context: The initial context value.
    ///   - queue: The queue to synchronize the access to the `DatadogContext`.
    init(context: DatadogContext, queue: DispatchQueue = DatadogContextProvider.defaultQueue) {
        self.context = context
        self.queue = queue
        self.receivers = []
        self.observations = []
    }

    deinit {
        observations.forEach { $0.cancel() }
    }

    /// Publishes context changes to the given receiver.
    ///
    /// - Parameter receiver: The receiver closure.
    func publish(to receiver: @escaping @Sendable (DatadogContext) -> Void) {
        queue.async { self.receivers.append(receiver) }
    }

    /// Reads to the `context` synchronously, by blocking the caller thread.
    ///
    /// **Warning:** This method will block the caller thread by reading the context
    /// synchronously on a concurrent queue.
    /// 
    /// - Returns: The current context.
    func read() -> DatadogContext {
        queue.sync { context }
    }

    /// Reads to the `context` asynchronously, without blocking the caller thread.
    ///
    /// - Parameter block: The block closure called with the current context.
    func read(block: @escaping (DatadogContext) -> Void) {
        queue.async { block(self.context) }
    }

    /// Writes to the `context` asynchronously, without blocking the caller thread.
    ///
    /// - Parameter block: The block closure called with the current context.
    func write(block: @escaping (inout DatadogContext) -> Void) {
        queue.async {
            block(&self.context)
            self.receivers.forEach { receiver in
                receiver(self.context)
            }
        }
    }

    /// Observes a ``ContextValueSource`` and applies each emitted value to
    /// the context using the provided `update` closure.
    ///
    /// The source's ``ContextValueSource/initialValue`` is applied immediately.
    /// Subsequent values from the source's ``ContextValueSource/values`` stream
    /// are applied as they arrive.
    ///
    /// Example:
    ///
    ///     provider.observe(NWPathMonitorSource()) { $0.networkConnectionInfo = $1 }
    ///
    /// - Parameters:
    ///   - source: The context value source to observe.
    ///   - update: A closure that applies a new value to the context.
    func observe<Source: ContextValueSource>(
        _ source: Source,
        update: @escaping @Sendable (inout DatadogContext, Source.Value) -> Void
    ) {
        write { context in
            update(&context, source.initialValue)
        }

        let task = Task { [weak self] in
            for await value in source.values {
                self?.write { context in
                    update(&context, value)
                }
            }
        }

        queue.async {
            self.observations.append(task)
        }
    }

#if DD_SDK_COMPILED_FOR_TESTING
    func replace(context newContext: DatadogContext) {
        queue.async {
            self.context = newContext
        }
    }
#endif
}

extension DatadogContextProvider: Flushable {
    /// Awaits completion of all asynchronous operations.
    ///
    /// **blocks the caller thread**
    func flush() {
        queue.sync { }
    }
}
