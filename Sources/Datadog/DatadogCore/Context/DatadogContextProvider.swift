/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
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
///
/// The context provider has the ability to a assign a value reader that complies to
/// ``ContextValueReader`` to a specific context property. e.g.:
///
///     let reader = ServerOffsetReader<TimeInterval>(initialValue: 0)
///     provider.assign(reader: reader, to: \.serverTimeOffset)
///
///
/// The context provider can subscribe a context property to a publisher that complies
/// to ``ContextValuePublisher``. e.g.:
///
///     let publisher = ServerOffsetPublisher<TimeInterval>(initialValue: 0)
///     provider.subscribe(\.serverTimeOffset, to: publisher)
///
/// All subscriptions will be cancelled when the provider is deallocated.
internal final class DatadogContextProvider {
    /// The current `context`.
    ///
    /// The value must be accessed from the `queue` only.
    private var context: DatadogContext {
        didSet { receivers.forEach { $0(context) } }
    }

    /// The queue used to synchronize the access to the `DatadogContext`.
    internal let queue = DispatchQueue(
        label: "com.datadoghq.core-context",
        qos: .utility
    )

    /// List of receivers to invoke when the context changes.
    private var receivers: [ContextValueReceiver<DatadogContext>]

    /// List of subscription of context values.
    private var subscriptions: [ContextValueSubscription]

    /// A reader for key-path values of the context.
    private var reader: KeyPathContextValueReader<DatadogContext>

    /// Creates a context provider to perform reads and writes on the
    /// shared Datadog context.
    ///
    /// - Parameter context: The inital context value.
    init(context: DatadogContext) {
        self.context = context
        self.receivers = []
        self.subscriptions = []
        self.reader = KeyPathContextValueReader()
    }

    deinit {
        subscriptions.forEach { $0.cancel() }
    }

    /// Reads current context.
    ///
    /// **Warning:** Must be called from the `queue`.
    private func unsafeRead() -> DatadogContext {
        reader.read(to: &self.context)
        return context
    }

    /// Publishes context changes to the given receiver.
    ///
    /// - Parameter receiver: The receiver closure.
    func publish(to receiver: @escaping ContextValueReceiver<DatadogContext>) {
        queue.async { self.receivers.append(receiver) }
    }

    /// Reads to the `context` synchronously, by blocking the caller thread.
    ///
    /// **Warning:** This method will block the caller thread by reading the context
    /// synchronously on a concurrent queue.
    /// 
    /// - Returns: The current context.
    func read() -> DatadogContext {
        queue.sync(execute: unsafeRead)
    }

    /// Reads to the `context` asynchronously, without blocking the caller thread.
    ///
    /// - Parameter block: The block closure called with the current context.
    func read(block: @escaping (DatadogContext) -> Void) {
        queue.async { block(self.unsafeRead()) }
    }

    /// Writes to the `context` asynchronously, without blocking the caller thread.
    ///
    /// - Parameter block: The block closure called with the current context.
    func write(block: @escaping (inout DatadogContext) -> Void) {
        queue.async { block(&self.context) }
    }

    /// Subscribes a context's property to a publisher.
    ///
    /// The context provider can subscribe a context property to a publisher that complies
    /// to ``ContextValuePublisher``. e.g.:
    ///
    ///     let publisher = ServerOffsetPublisher<TimeInterval>(initialValue: 0)
    ///     provider.subscribe(\.serverTimeOffset, to: publisher)
    ///
    /// - Parameters:
    ///   - keyPath: A context's key path that supports reading from and writing to the resulting value.
    ///   - publisher: The context value publisher.
    func subscribe<Publisher>(_ keyPath: WritableKeyPath<DatadogContext, Publisher.Value>, to publisher: Publisher) where Publisher: ContextValuePublisher {
        let subscription = publisher.subscribe { value in
            self.write { $0[keyPath: keyPath] = value }
        }

        write {
            $0[keyPath: keyPath] = publisher.initialValue
            self.subscriptions.append(subscription)
        }
    }

    /// Assigns a value reader to a context property.
    ///
    /// The context provider has the ability to a assign a value reader that complies to
    /// ``ContextValueReader`` to a specific context property. e.g.:
    ///
    ///     let reader = ServerOffsetReader<TimeInterval>()
    ///     provider.assign(reader: reader, to: \.serverTimeOffset)
    ///
    /// - Parameters:
    ///   - reader: The value reader.
    ///   - keyPath: A context's key path that supports reading from and writing to the resulting value.
    func assign<Reader>(reader: Reader, to keyPath: WritableKeyPath<DatadogContext, Reader.Value>) where Reader: ContextValueReader {
        queue.async {
            self.reader.append(reader: reader, receiver: keyPath)
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
