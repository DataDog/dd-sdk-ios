/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

/// Defines dependency between Session Replay (SR) and RUM modules.
/// It aims at centralizing documentation of contracts between both products.
internal struct RUMDependency {
    /// The key for referencing RUM baggage (RUM context) in `DatadogContext.featuresAttributes`.
    ///
    /// SR expects:
    /// - empty baggage (`[:]`) if current RUM session is not sampled,
    /// - baggage with `applicationIDKey`, `sessionIDKey` and `viewIDKey` keys if RUM session is sampled.
    static let rumBaggageKey = "rum"

    /// The key for referencing RUM application ID inside RUM baggage.
    ///
    /// SR expects non-optional value holding lowercased, standard UUID `String`.
    static let applicationIDKey = "application_id"

    /// The key for referencing RUM session ID inside RUM baggage.
    ///
    /// SR expects non-optional value holding lowercased, standard UUID `String`.
    static let sessionIDKey = "session_id"

    /// The key for referencing RUM view ID inside RUM baggage.
    ///
    /// SR expects non-optional value holding lowercased, standard UUID `String`.
    static let viewIDKey = "view.id"
}
