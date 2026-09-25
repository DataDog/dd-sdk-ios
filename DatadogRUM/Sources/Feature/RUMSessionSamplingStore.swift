/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

/// The RUM session identity, and the sampling decisions derived from it, readable synchronously.
///
/// RUM owns the session identity. Other features normally learn about it through the core context,
/// which costs three asynchronous hops; the ones that mutate outgoing requests cannot afford them
/// and read this instead. See ``RUMSessionSamplerProvider``.
///
/// This is a separate object from ``RUMFeature`` so the URLSession handler can hold it directly,
/// and so `RUMFeature` has a single place to write the identity to.
internal final class RUMSessionSamplingStore: RUMSessionSamplerProvider {
    /// The session ID and its sampler, held together.
    ///
    /// They are stored as one value, under one lock, so a reader can never pair a session ID with a
    /// decision that was made for a different session.
    private struct Identity {
        let sessionID: String
        let sampler: DeterministicSampler
    }

    @ReadWriteLock
    private var identity: Identity?

    func decision(for policy: SamplingRatePolicy, rate: SampleRate) -> SessionSamplingDecision? {
        // A single read of `identity` yields one consistent pair. Deriving the decision from it is
        // pure, so a session change during this call cannot split the ID from the decision.
        guard let identity else {
            return nil
        }

        let sampler: DeterministicSampler
        switch policy {
        case .featureRate:
            sampler = DeterministicSampler(seed: identity.sampler.seed, samplingRate: rate)
        case .combinedWithSessionRate:
            sampler = identity.sampler.combined(with: rate)
        }

        return SessionSamplingDecision(sessionID: identity.sessionID, isSampled: sampler.isSampled)
    }

    /// Records the session that is now current.
    func setSession(id sessionID: String, sampler: DeterministicSampler) {
        identity = Identity(sessionID: sessionID, sampler: sampler)
    }

    /// Clears the current session, so readers fall back to their own sampling.
    func clearSession() {
        identity = nil
    }
}
