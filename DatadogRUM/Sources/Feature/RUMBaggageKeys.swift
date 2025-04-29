/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

/// Defines keys referencing RUM baggage in `DatadogContext.featuresAttributes`.
internal enum RUMBaggageKeys {
    /// The key references RUM session state.
    /// The state associated with the key conforms to `Codable`.
    static let sessionState = "rum-session-state"

    /// The key references ``DatadogInternal.GlobalRUMAttributes`` value holding RUM attributes.
    /// It is sent after each change to RUM attributes in `RUMMonitor`.
    static let attributes = "global-rum-attributes"
}
