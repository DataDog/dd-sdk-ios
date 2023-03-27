/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

internal struct TracingMessageReceiver: FeatureMessageReceiver {
    /// Tracks RUM context to be associated with spans.
    let rum = TracingWithRUMIntegration()

    /// Process messages receives from the bus.
    ///
    /// - Parameters:
    ///   - message: The Feature message
    ///   - core: The core from which the message is transmitted.
    func receive(message: FeatureMessage, from core: DatadogCoreProtocol) -> Bool {
        switch message {
        case .context(let context):
            return update(context: context)
        default:
            return false
        }
    }

    /// Updates RUM attributes of the `Global.sharedTracer` if available.
    ///
    /// - Parameter context: The updated core context.
    private func update(context: DatadogContext) -> Bool {
        if let attributes: [String: String] = context.featuresAttributes["rum"]?.ids {
            rum.attributes = attributes
            return true
        }
        return false
    }
}
