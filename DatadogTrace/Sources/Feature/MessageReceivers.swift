/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

internal struct CoreContext {
    /// The RUM attributes that should be added as Span tags.
    ///
    /// These attributes are synchronized using a read-write lock.
    var rum: [String: String]?

    /// Provides the history of app foreground / background states.
    var applicationStateHistory: AppStateHistory?
}

internal final class ContextMessageReceiver: FeatureMessageReceiver {
    let bundleWithRumEnabled: Bool

    /// The up-to-date core context.
    ///
    /// The context is synchronized using a read-write lock.
    @ReadWriteLock
    var context: CoreContext = .init()

    init(bundleWithRumEnabled: Bool) {
        self.bundleWithRumEnabled = bundleWithRumEnabled
    }

    /// Process messages receives from the bus.
    ///
    /// - Parameters:
    ///   - message: The Feature message
    ///   - core: The core from which the message is transmitted.
    func receive(message: FeatureMessage, from core: DatadogCoreProtocol) -> Bool {
        switch message {
        case .context(let context):
            return update(context: context, from: core)
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

            if bundleWithRumEnabled, let rum = context.baggages[RUMContext.key] {
                do {
                    let context: RUMContext = try rum.decode()
                    $0.rum = [
                        "_dd.application.id": context.applicationID,
                        "_dd.session.id": context.sessionID
                    ]

                    $0.rum?["_dd.view.id"] = context.viewID
                    $0.rum?["_dd.action.id"] = context.userActionID
                } catch {
                    core.telemetry
                        .error("Fails to decode RUM context from Trace", error: error)
                }
            }
        }

        return true
    }
}
