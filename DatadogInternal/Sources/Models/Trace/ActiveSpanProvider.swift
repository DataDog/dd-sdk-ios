/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

/// Struct holding the active span information, used by ``ActiveSpanProvider``.
///
/// This struct's purpose is to hold all the necessary information to enrich a RUM resource event
/// with span related information. The backend will use this information when generating a span out
/// of a RUM resource to correctly link the span to a trace and parent, with the same sampling
/// priority and decision mechanism as the trace's root span.
public struct ActiveSpanContext: Sendable {
    /// Trace ID of the currently active span.
    public let traceID: TraceID
    /// ID of the currently active span. This should be the RUM resource event parent span ID.
    public let activeSpanID: SpanID
    /// Sampling priority of the trace with ID ``traceID``.
    public let samplingPriority: SamplingPriority
    /// Sampling decision mechanism of the trace with ID ``traceID``.
    public let samplingMechanismType: SamplingMechanismType

    public init(traceID: TraceID, activeSpanID: SpanID, samplingPriority: SamplingPriority, samplingMechanismType: SamplingMechanismType) {
        self.traceID = traceID
        self.activeSpanID = activeSpanID
        self.samplingPriority = samplingPriority
        self.samplingMechanismType = samplingMechanismType
    }
}

/// Entities implementing this protocol can provide the currently active span information.
///
/// These entities act as a bridge between Trace and RUM. If Trace is enabled, they provide the active span and trace ID,
/// and sampling priority information. RUM (or any other module) can obtain this information from it.
public protocol ActiveSpanProvider: Sendable {
    /// If there is a currently active span, returns an ``ActiveSpanContext`` instance with the active span and trace IDs,
    /// or `nil` otherwise.
    ///
    /// - returns: An ``ActiveSpanContext`` instance with the active span and trace IDs, or `nil` otherwise.
    func activeSpanContext() -> ActiveSpanContext?
}

/// This entity acts as a bridge between Trace and RUM. If Trace is enabled, it will provide an ``ActiveSpanProvider/ProviderFunction``
/// that itself provides the active span and trace ID. RUM (or any other module) can obtain this information from it.
public struct ActiveSpanProviderAdditionalContext: ActiveSpanProvider, AdditionalContext {
    public static var key: String { "active_span_provider" }

    /// Function that returns a ``ActiveSpanContext`` struct with the currently active span and trace IDs, or `nil` if
    /// there is no currently active span.
    public typealias ProviderFunction = @Sendable () -> (ActiveSpanContext?)

    /// The provider function that obtains the active span and trace IDs.
    private let providerFunction: ProviderFunction

    /// Creates a new provider with the given provider function.
    /// - parameter providerFunction: The provider function. See ``ActiveSpanProvider/ProviderFunction`` for details.
    public init(providerFunction: @escaping ProviderFunction) {
        self.providerFunction = providerFunction
    }

    public func activeSpanContext() -> ActiveSpanContext? {
        providerFunction()
    }
}
