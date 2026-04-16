/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

internal final class SamplerProvider: TracerSamplerProvider, @unchecked Sendable {
    /// Holds both the tracer sampler, and the RUM deterministic sampler, if any.
    ///
    /// These two samplers are wrapped together in a struct so they can be updated atomically.
    private struct Samplers: Sendable {
        /// Sampler that should be used by tracing operations with the configured sampling rate.
        ///
        /// This sampler is provided directly to the Trace feature operations that use the default sample rate
        /// (defined in the Trace configuration) and used as the basis for creating samplers with custom
        /// sample rates.
        ///
        /// Refer to ``TracerSamplerProvider`` documentation for details on why using a dynamic
        /// sampler provider.
        let sampler: Sampling

        /// The deterministic sampler ``sampler`` should be based on.
        ///
        /// This is the sampler used by RUM. When available, ``sampler`` should be generated using the
        /// same seed as `deterministicSampler`.
        let deterministicSampler: DeterministicSampler?
    }

    @ReadWriteLock
    private var samplers: Samplers

    /// Creates a `SamplerProvider` with the given sampler rate.
    ///
    /// The sampler obtained by calling ``sampler`` will always use the provided sampler rate. To obtain a
    /// sampler using a different sampler rate, use ``makeSamplerFor(samplingRate:)``.
    ///
    /// - parameters:
    ///   - sampleRate: The sample rate as described above.
    init(sampleRate: SampleRate) {
        samplers = Samplers(
            sampler: Self.makeCurrentSamplerFor(deterministicSampler: nil, using: sampleRate),
            deterministicSampler: nil
        )
    }

    /// Sampler appropriate for tracing operations with the configured sampling rate.
    ///
    /// Provide this sample directly to the Trace feature operations that use the default sample rate
    /// (defined in the Trace configuration) and used as the basis for creating samplers with custom
    /// sample rates.
    ///
    /// Refer to ``TracerSamplerProvider`` documentation for more details.
    var sampler: any Sampling {
        samplers.sampler
    }

    /// Obtains a sampler with a custom rate appropriate for tracing operations.
    ///
    /// For operations that require a sampling rate different than the default one (defined in
    /// the Trace feature configuration), use this function to create a sampler.
    ///
    /// Refer to ``TracerSamplerProvider`` documentation for more details.
    ///
    /// - parameters:
    ///   - samplingRate: The desired sampling rate (between 0 and 100).
    ///
    /// - returns: The appropriate sampler to be used for tracing operations with custom
    /// sampling rates.
    func makeSamplerFor(samplingRate: DatadogInternal.SampleRate) -> any Sampling {
        Self.makeCurrentSamplerFor(deterministicSampler: samplers.deterministicSampler, using: samplingRate)
    }

    /// Updates this sampler with a possible deterministic sampler from the RUM session.
    ///
    /// Call this function when a new RUM context is broadcasted through the message bus.
    /// This generates the most appropriate sampler for Trace. If a sampled RUM session exists,
    /// the sampler will be deterministic, based on the same seed.
    ///
    /// - parameters:
    ///   - deterministicSampler: The RUM sampler if it exists, `nil` otherwise.
    func updateWith(deterministicSampler: DeterministicSampler?) {
        _samplers.mutate {
            $0 = .init(
                sampler: Self.makeCurrentSamplerFor(deterministicSampler: deterministicSampler, using: $0.sampler.samplingRate),
                deterministicSampler: deterministicSampler
            )
        }
    }

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
    private static func makeCurrentSamplerFor(deterministicSampler: DeterministicSampler?, using samplingRate: SampleRate) -> Sampling {
        if let deterministicSampler {
            return DeterministicSampler(seed: deterministicSampler.seed, samplingRate: samplingRate)
        } else {
            return Sampler(samplingRate: samplingRate)
        }
    }
}
