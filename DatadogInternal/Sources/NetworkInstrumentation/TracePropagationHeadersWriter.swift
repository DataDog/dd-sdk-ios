/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

/// Available strategies for sampling trace propagation headers.
public enum TraceSamplingStrategy {
    /// Trace propagation headers will be sampled same as propagated span.
    ///
    /// Use this option to leverage head-based sampling, where the decision to keep or drop the trace
    /// is determined from the first span of the trace, the head, when the trace is created. With `.headBased`
    /// strategy, this decision is propagated through the request context to downstream services.
    case headBased
    /// Trace propagation headers will be sampled independently from sampling decision in propagated span.
    ///
    /// Use this option to apply the provided `sampleRate` for determining the decision to keep or drop the trace
    /// in downstream services independently of sampling their parent span.
    case custom(sampleRate: Float)

    internal func sampler(for traceContext: TraceContext) -> Sampling {
        switch self {
        case .headBased:
            return DeterministicSampler(shouldSample: traceContext.isKept, samplingRate: traceContext.sampleRate)
        case .custom(let sampleRate):
            return Sampler(samplingRate: sampleRate)
        }
    }
}

/// Write interface for a custom carrier
public protocol TracePropagationHeadersWriter {
    var traceHeaderFields: [String: String] { get }

    func write(traceContext: TraceContext)
}
