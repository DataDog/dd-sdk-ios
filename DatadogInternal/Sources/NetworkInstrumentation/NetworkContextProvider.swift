/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

/// An interface for writing and reading  the `NetworkContext`
internal protocol NetworkContextProvider: AnyObject {
    /// Returns current `NetworkContext` value.
    var currentNetworkContext: NetworkContext? { get }
}

/// Manages the `NetworkContext` reads and writes in a thread-safe manner.
internal class NetworkContextCoreProvider: NetworkContextProvider {
    // MARK: - NetworkContextProviderType
    @ReadWriteLock
    var currentNetworkContext: NetworkContext?
}

extension NetworkContextCoreProvider: FeatureMessageReceiver {
    func receive(message: FeatureMessage, from core: DatadogCoreProtocol) -> Bool {
        guard case let .context(context) = message else {
            return false
        }

        update(context: context, to: core)
        return true
    }

    /// Updates crash context.
    ///
    /// - Parameter context: The updated core context.
    private func update(context: DatadogContext, to core: DatadogCoreProtocol) {
        do {
            self.currentNetworkContext = NetworkContext(rumContext: try context.baggages["rum"]?.decode())
        } catch {
            core.telemetry
                .error("Fails to decode RUM Context from Trace", error: error)
        }
    }
}
