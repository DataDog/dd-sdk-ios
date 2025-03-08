/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

internal struct CoreContext {
    struct RUMSession: Decodable { let sessionUUID: String }

    /// Provides the history of app foreground / background states.
    var applicationStateHistory: AppStateHistory?

    /// Provides the current active RUM Session information, if any
    var rumSession: RUMSession?
}

internal final class ContextMessageReceiver: FeatureMessageReceiver {
    /// The up-to-date core context.
    ///
    /// The context is synchronized using a read-write lock.
    @ReadWriteLock
    var context: CoreContext = .init()

    /// Process messages receives from the bus.
    ///
    /// - Parameters:
    ///   - message: The Feature message
    ///   - core: The core from which the message is transmitted.
    func receive(message: FeatureMessage, from core: DatadogCoreProtocol) -> Bool {
        switch message {
        case .context(let context):
            return update(context: context, from: core)
        case .telemetry(let telemetry):
            return false
        case .baggage(let label, let baggage) where label == "rum-session-state":
            do {
                try _context.mutate { $0.rumSession = try baggage.decode() }
            } catch {
                core.telemetry
                    .error("Fails to decode RUM Session State from Trace", error: error)
            }
            return false
        default:
            return false
        }
    }

    /// Updates context of the `DatadogTracer` if available.
    ///
    /// - Parameter context: The updated core context.
    private func update(context: DatadogContext, from core: DatadogCoreProtocol) -> Bool {
        _context.mutate {
            $0.applicationStateHistory = context.applicationStateHistory
        }

        return true
    }
}
