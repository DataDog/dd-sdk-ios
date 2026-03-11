/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

/// Provides serialized access to Datadog Context.
///
/// The context can be read or mutated through async calls:
///
///     let context = await provider.read()
///     await provider.write { context in
///         context.version = "2.0"
///     }
///
internal actor DatadogContextProvider {
    /// The current `context`.
    private var context: DatadogContext

    /// List of receivers to invoke when the context changes.
    private var receivers: [@Sendable (DatadogContext) -> Void]

    /// Tasks consuming `ContextValueSource` streams.
    private var observations: [Task<Void, Never>]

    /// Creates a context provider to perform reads and writes on the
    /// shared Datadog context.
    ///
    /// - Parameter context: The initial context value.
    init(context: DatadogContext) {
        self.context = context
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
        receivers.append(receiver)
    }

    /// Returns a snapshot of the current context.
    func read() -> DatadogContext {
        context
    }

    /// Mutates the context and notifies all receivers.
    ///
    /// - Parameter block: The mutation block applied to the context.
    func write(block: @Sendable (inout DatadogContext) -> Void) {
        block(&context)
        for receiver in receivers {
            receiver(context)
        }
    }

    /// Subscribes to a ``ContextValueSource`` and applies each emitted value
    /// to the context using the provided `update` closure.
    ///
    /// The source's ``ContextValueSource/initialValue`` is applied immediately.
    /// Subsequent values from the source's ``ContextValueSource/values`` stream
    /// are applied as they arrive.
    ///
    /// Example:
    ///
    ///     await provider.subscribe(to: NWPathMonitorSource()) { $0.networkConnectionInfo = $1 }
    ///
    /// - Parameters:
    ///   - source: The context value source to subscribe to.
    ///   - update: A closure that applies a new value to the context.
    func subscribe<Source: ContextValueSource>(
        to source: Source,
        update: @escaping @Sendable (inout DatadogContext, Source.Value) -> Void
    ) {
        write { context in
            update(&context, source.initialValue)
        }

        let task = Task { [weak self] in
            for await value in source.values {
                await self?.write { context in
                    update(&context, value)
                }
            }
        }

        observations.append(task)
    }

#if DD_SDK_COMPILED_FOR_TESTING
    func replace(context newContext: DatadogContext) {
        context = newContext
    }
#endif
}
