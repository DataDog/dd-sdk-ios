/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

/// The Trace context received from `Core`.
public enum TraceCoreContext {
    /// The APM configuration.
    public struct Configuration: AdditionalContext {
        public static let key = "trace_configuration"

        /// The sample rate for traces
        public let sampleRate: SampleRate

        /// Creates a Trace configuration.
        ///
        /// - Parameter sampleRate: The sample rate for traces
        public init(sampleRate: SampleRate) {
            self.sampleRate = sampleRate
        }
    }

    /// The Span context received from `Core`.
    public struct Span: AdditionalContext {
        public static let key = "span_context"

        /// The Trace ID
        public let traceID: String
        /// The Span ID
        public let spanID: String

        /// Creates a Span context.
        /// - Parameters:
        ///   - traceID: The Trace ID
        ///   - spanID: The Span ID
        public init(traceID: String, spanID: String) {
            self.traceID = traceID
            self.spanID = spanID
        }
    }

    /// This entity acts as a bridge between Trace and RUM. If Trace is enabled, it will provide an ``TraceCoreContext/TraceActiveSpanProvider/ProviderFunction``
    /// that itself provides the active span and trace ID. RUM (or any other module) can obtain this information from it.
    public struct ActiveSpanProvider: TraceActiveSpanProvider, AdditionalContext {
        public static var key: String { "active_span_provider" }

        /// Function that returns a ``ActiveSpanContext`` struct with the currently active span and trace IDs, or `nil` if
        /// there is no currently active span.
        public typealias ProviderFunction = @Sendable () -> (ActiveSpanContext?)

        /// The provider function that obtains the active span and trace IDs.
        private let providerFunction: ProviderFunction

        /// Creates a new provider with the given provider function.
        /// - parameter providerFunction: The provider function. See ``TraceCoreContext/TraceActiveSpanProvider/ProviderFunction`` for details.
        public init(providerFunction: @escaping ProviderFunction) {
            self.providerFunction = providerFunction
        }

        public func activeSpanContext() -> ActiveSpanContext? {
            providerFunction()
        }
    }
}
