/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

/// Defines keys referencing RUM baggage in `DatadogContext.featuresAttributes`.
internal enum RUMBaggageKeys {
    /// The key references RUM view event.
    /// The view event associated with the key conforms to `Codable`.
    static let viewEvent = "view-event"

    /// The key references a `true` value if the RUM view is reset.
    static let viewReset = "view-reset"

    /// The key references RUM session state.
    /// The state associated with the key conforms to `Codable`.
    static let sessionState = "session-state"
}
