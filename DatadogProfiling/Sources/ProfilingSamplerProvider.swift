/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import DatadogInternal

/// Stores the continuous profiling sampling state derived from the current RUM session.
///
/// This type separates static SDK configuration from the dynamic, session-linked sampling decision:
/// - `isContinuousProfilingConfigured` reflects the configured `continuousSampleRate`
/// - `continuousProfilingSampled` reflects the current RUM-linked sampling result
///
/// The provider intentionally stores only the resolved sampling result, not the deterministic sampler
/// itself. This keeps all profiling sampling reads contextualized in one place and allows other
/// components to react to three distinct states:
/// - `nil`: no RUM sampling decision received yet
/// - `true`: the current RUM session samples continuous profiling in
/// - `false`: the current RUM session samples continuous profiling out
internal final class ProfilingSamplerProvider: @unchecked Sendable {
    private let continuousSampleRate: SampleRate

    /// Session-linked sampling result for continuous profiling.
    ///
    /// The value is `nil` until a RUM context provides a `sessionSampler`. Once a context is received,
    /// the value becomes the result of composing the RUM session sampler with `continuousSampleRate`.
    @ReadWriteLock
    private(set) var continuousProfilingSampled: Bool?

    /// `true` when continuous profiling is configured with a sample rate greater than zero.
    let isContinuousProfilingConfigured: Bool

    init(continuousSampleRate: SampleRate) {
        self.continuousSampleRate = continuousSampleRate.normalized
        self.continuousProfilingSampled = nil
        self.isContinuousProfilingConfigured = continuousSampleRate > 0
    }

    /// Updates the session-linked sampling result from the current RUM session sampler.
    func updateWith(deterministicSampler: DeterministicSampler) {
        continuousProfilingSampled = deterministicSampler.combined(with: continuousSampleRate).sample()
    }
}
