/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

/// Struct holding the active span and trace IDs, used by ``ActiveSpanProvider``.
public struct ActiveSpanIDs {
    public let traceID: TraceID
    public let activeSpanID: SpanID

    public init(traceID: TraceID, activeSpanID: SpanID) {
        self.traceID = traceID
        self.activeSpanID = activeSpanID
    }
}

/// Entities implementing this protocol can provide the currently active span and trace IDs, if any exists.
///
/// These entities act as a bridge between Trace and RUM. If Trace is enabled, they provide the active span and trace ID.
/// RUM (or any other module) can obtain this information from it.
public protocol ActiveSpanProvider {
    /// If there is a currently active span, returns an ``ActiveSpanIDs`` instance with the active span and trace IDs,
    /// or `nil` otherwise.
    ///
    /// - returns: An ``ActiveSpanIDs`` instance with the active span and trace IDs, or `nil` otherwise.
    func activeSpanIDs() -> ActiveSpanIDs?
}

/// This entity acts as a bridge between Trace and RUM. If Trace is enabled, it will provide an ``ActiveSpanProvider/ProviderFunction``
/// that itself provides the active span and trace ID. RUM (or any other module) can obtain this information from it.
public struct ActiveSpanProviderAdditionalContext: ActiveSpanProvider, AdditionalContext {
    public static var key: String { "active_span_provider" }

    /// Function that returns a ``ActiveSpanIDs`` struct with the currently active span and trace IDs, or `nil` if
    /// there is no currently active span.
    public typealias ProviderFunction = () -> (ActiveSpanIDs?)

    /// The provider function that obtains the active span and trace IDs.
    private let providerFunction: ProviderFunction

    /// Creates a new provider with the given provider function.
    /// - parameter providerFunction: The provider function. See ``ActiveSpanProvider/ProviderFunction`` for details.
    public init(providerFunction: @escaping ProviderFunction) {
        self.providerFunction = providerFunction
    }

    public func activeSpanIDs() -> ActiveSpanIDs? {
        providerFunction()
    }
}
