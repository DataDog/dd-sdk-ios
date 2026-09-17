/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

/// A `Sampling` that reports a decision which was already made.
///
/// Used to hand a ``SessionSamplingSnapshot`` decision back through the `Sampling` interface that
/// the Trace feature operations expect.
private struct DecidedSampler: Sampling {
    let samplingRate: SampleRate
    let isSampled: Bool

    func sample() -> Bool { isSampled }
}

internal final class SamplerProvider: TracerSamplerProvider, @unchecked Sendable {
    /// The sampling rate defined in the Trace feature configuration.
    private let sampleRate: SampleRate

    /// Resolves synchronous access to the RUM session, or `nil` when RUM is not enabled on the core.
    ///
    /// This is a closure rather than a stored reference for two reasons: RUM can be enabled after
    /// Trace, so the lookup has to happen at read time; and a feature must not retain its core.
    private let sessionSampling: () -> RUMSessionSamplerProvider?

    /// Creates a `SamplerProvider` with the given sampler rate.
    ///
    /// The sampler obtained by calling ``sampler`` will always use the provided sampler rate. To obtain a
    /// sampler using a different sampler rate, use ``makeSamplerFor(samplingRate:)``.
    ///
    /// - parameters:
    ///   - sampleRate: The sample rate as described above.
    ///   - sessionSampling: Resolves the RUM session sampling state on the core Trace is registered
    ///   in. Defaults to always returning `nil`, which makes every sampler random.
    init(sampleRate: SampleRate, sessionSampling: @escaping () -> RUMSessionSamplerProvider? = { nil }) {
        self.sampleRate = sampleRate
        self.sessionSampling = sessionSampling
    }

    /// Sampler appropriate for tracing operations with the configured sampling rate.
    ///
    /// Provide this sample directly to the Trace feature operations that use the default sample rate
    /// (defined in the Trace configuration) and used as the basis for creating samplers with custom
    /// sample rates.
    ///
    /// Refer to ``TracerSamplerProvider`` documentation for more details.
    var sampler: any Sampling {
        makeSamplerFor(samplingRate: sampleRate)
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
        // `.featureRate`, not `.combinedWithSessionRate`: `Trace.Configuration.sampleRate` is an
        // absolute trace sampling rate, so the RUM session contributes only the seed. A Trace rate of
        // 20% keeps 20% of traces whether RUM samples sessions at 100% or at 10%. Composing the two
        // here would silently turn that 20% into 2%.
        //
        // The session is read synchronously, on the calling thread. Trace used to receive it over the
        // message bus, which left every span created before the first RUM context landed sampled at
        // random and therefore inconsistent with its session.
        guard let snapshot = sessionSampling()?.sessionSamplingSnapshot(for: .featureRate, rate: samplingRate) else {
            // No RUM session: nothing to be consistent with, so sample randomly.
            return Sampler(samplingRate: samplingRate)
        }

        return DecidedSampler(samplingRate: samplingRate.normalizedSampleRate, isSampled: snapshot.isSampled)
    }
}
