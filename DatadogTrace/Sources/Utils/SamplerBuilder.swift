/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

/// Helper type containing function for creating samplers appropriate for the Trace feature.
internal enum SamplerBuilder {
    /// Creates the most appropriate sampler for the tracing feature.
    ///
    /// Refer to ``TracerSamplerProvider`` documentation for details on why using a dynamic
    /// sampler provider.
    ///
    /// - parameters:
    ///   - deterministicSampler: If a deterministic sampler provided by RUM exists, it must be
    ///   passed in this parameter. Otherwise, pass `nil`.
    ///   - samplingRate: The desired sampling rate. This can either be the value defined in the
    ///   Trace feature configuration, or a custom value for a situation where a custom sampling rate
    ///   was requested.
    static func makeCurrentSamplerFor(deterministicSampler: DeterministicSampler?, using samplingRate: SampleRate) -> Sampling {
        if let deterministicSampler {
            return DeterministicSampler(seed: deterministicSampler.seed, samplingRate: samplingRate)
        } else {
            return Sampler(samplingRate: samplingRate)
        }
    }
}
