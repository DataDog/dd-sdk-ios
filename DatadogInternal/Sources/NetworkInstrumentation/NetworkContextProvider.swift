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
    /// Defines keys referencing RUM baggage in `DatadogContext.featuresAttributes`.
    internal enum RUMBaggageKeys {
        /// The key references RUM view event.
        /// The view event associated with the key conforms to `Codable`.
        static let viewEvent = "rum-view-event"

        /// The key references a `true` value if the RUM view is reset.
        static let viewReset = "rum-view-reset"

        /// The key references RUM session state.
        /// The state associated with the key conforms to `Codable`.
        static let sessionState = "rum-session-state"

        /// This key references the global log attributes
        static let logAttributes = "global-log-attributes"

        /// The key referencing ``DatadogInternal.GlobalRUMAttributes`` value holding RUM global attributes.
        static let rumAttributes = "global-rum-attributes"
    }

    func receive(message: FeatureMessage, from core: DatadogCoreProtocol) -> Bool {
        switch message {
        case .context(let context):
            update(context: context, to: core)
        default:
            return false
        }

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
