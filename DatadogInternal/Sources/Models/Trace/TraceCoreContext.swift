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
}
