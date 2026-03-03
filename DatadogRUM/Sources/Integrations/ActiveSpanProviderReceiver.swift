/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

/// Entities implementing this protocol may contain an ``ActiveSpanProvider``.
internal protocol ActiveSpanProviderContainer {
    var activeSpanProvider: ActiveSpanProvider? { get }
}

/// Handles messages with updated `DatadogCore` instances, and keeps the `ActiveSpanProvider` in a variable.
/// See ``ActiveSpanProvider`` documentation for details on why this is needed.
internal struct ActiveSpanProviderReceiver: FeatureMessageReceiver, ActiveSpanProviderContainer {
    /// This contains an ``ActiveSpanProvider`` if the Trace feature is enabled, or `nil` otherwise.
    @ReadWriteLock
    private(set) var activeSpanProvider: ActiveSpanProvider?

    func receive(message: FeatureMessage, from core: any DatadogCoreProtocol) -> Bool {
        switch message {
        case .context(let datadogContext):
            _activeSpanProvider.mutate {
                $0 = datadogContext.additionalContext(ofType: ActiveSpanProviderAdditionalContext.self)
            }

            return true
        default:
            return false
        }
    }
}
