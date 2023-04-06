/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

/// The set of messages that can be transimtted on the Features message bus.
public enum FeatureMessage {
    /// An error message.
    case error(
        message: String,
        baggage: FeatureBaggage
    )

    /// An encodable event that will be transmitted
    /// as-is through a Feature.
    case event(
        target: String,
        event: AnyEncodable
    )

    /// A custom message with generic encodable
    /// attributes.
    case custom(
        key: String,
        baggage: FeatureBaggage
    )

    /// A core context message.
    ///
    /// The core will send updated context throught the bus. Do not send new context values
    /// from a Feature or Integration.
    case context(DatadogContext)

    /// A telemtry message.
    ///
    /// The core can send telemtry data coming from all Features.
    case telemetry(TelemetryMessage)
}
