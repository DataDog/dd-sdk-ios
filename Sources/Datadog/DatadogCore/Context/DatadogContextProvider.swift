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

    private var subscriptions: [ContextValueSubscription]
    private var reader: KeyPathContextValueReader<DatadogContext>

    /// Creates a context provider to perform reads and writes on the
    /// shared Datadog context.
    ///
    /// - Parameter context: The inital context value.
    init(context: DatadogContext) {
        self.context = context
        self.subscriptions = []
        self.reader = KeyPathContextValueReader()
    }

    deinit {
        subscriptions.forEach { $0.cancel() }
    }

    /// Reads to the `context` asynchronously, without blocking the caller thread.
    func read(block: @escaping (DatadogContext) -> Void) {
        queue.async {
            var context = self.context
            self.reader.read(to: &context)
            block(context)
        }
    }

    /// Writes to the `context` asynchronously, without blocking the caller thread.
    func write(block: @escaping (inout DatadogContext) -> Void) {
        queue.async(flags: .barrier) { block(&self.context) }
    }

    /// Subscribes a context's key path to a publisher.
    ///
    /// - Parameters:
    ///   - keyPath: A context's key path that supports reading from and writing to the resulting value.
    ///   - publisher: The context value publisher.
    func subscribe<Publisher>(_ keyPath: WritableKeyPath<DatadogContext, Publisher.Value>, to publisher: Publisher) where Publisher: ContextValuePublisher {
        let subscription = publisher.subscribe { value in
            self.write { $0[keyPath: keyPath] = value }
        }

        subscriptions.append(subscription)
    }

    /// Assigns a value reader to a context property.
    ///
    /// - Parameters:
    ///   - reader: The value reader.
    ///   - keyPath: A context's key path that supports reading from and writing to the resulting value.
    func assign<Reader>(reader: Reader, to keyPath: WritableKeyPath<DatadogContext, Reader.Value>) where Reader: ContextValueReader {
        self.reader.append(reader: reader, receiver: keyPath)
    }
}
