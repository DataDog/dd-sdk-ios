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

    private var subscriptions: [ContextValueSubscription] = []
    private var networkConnectionInfoReader: AnyContextValueReader<NetworkConnectionInfo?>
    private var carrierInfoReader: AnyContextValueReader<CarrierInfo?>

    /// Creates a context provider to perform reads and writes on the
    /// shared Datadog context.
    ///
    /// - Parameters:
    ///   - context:                        The context inital context value.
    ///   - serverOffsetPublisher:          The server date publisher to synchronize the `context.serverTimeOffset`
    ///                                     parameter.
    ///   - networkConnectionInfoPublisher: The network info publisher to synchronize the
    ///                                     `context.networkConnectionInfo` parameter.
    ///   - carrierInfoPublisher:           The carrier info publisher to synchronize the `context.carrierInfo`
    ///                                     parameter.
    init(
        context: DatadogContext,
        serverOffsetPublisher: ServerOffsetPublisher,
        networkConnectionInfoPublisher: AnyNetworkConnectionInfoPublisher,
        carrierInfoPublisher: AnyCarrierInfoPublisher
    ) {
        self.context = context
        self.context.serverTimeOffset = serverOffsetPublisher.initialValue
        self.networkConnectionInfoReader = networkConnectionInfoPublisher.eraseToAnyReader()
        self.carrierInfoReader = carrierInfoPublisher.eraseToAnyReader()

        self.subscriptions = [
            serverOffsetPublisher.subscribe { offset in
                self.write { $0.serverTimeOffset = offset }
            },
            networkConnectionInfoPublisher.set(queue: queue).subscribe { info in
                self.write { $0.networkConnectionInfo = info }
            },
            carrierInfoPublisher.subscribe { info in
                self.write { $0.carrierInfo = info }
            },
        ]
    }

    deinit {
        subscriptions.forEach { $0.cancel() }
    }

    /// Reads to the `context` asynchronously, without blocking the caller thread.
    func read(block: @escaping (DatadogContext) -> Void) {
        queue.async {
            var context = self.context
            self.networkConnectionInfoReader.read { context.networkConnectionInfo = $0 }
            self.carrierInfoReader.read { context.carrierInfo = $0 }
            block(context)
        }
    }

    /// Writes to the `context` asynchronously, without blocking the caller thread.
    func write(block: @escaping (inout DatadogContext) -> Void) {
        queue.async(flags: .barrier) { block(&self.context) }
    }
}
