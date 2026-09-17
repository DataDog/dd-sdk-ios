/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

extension Sampler: AnyMockable, RandomMockable {
    public static func mockAny() -> Sampler {
        return .init(samplingRate: 50)
    }

    public static func mockRandom() -> Sampler {
        return .init(samplingRate: .random(in: (0.0...100.0)))
    }

    public static func mockKeepAll() -> Sampler {
        return .init(samplingRate: 100)
    }

    public static func mockRejectAll() -> Sampler {
        return .init(samplingRate: 0)
    }
}

extension DeterministicSampler {
    /// Returns a sampler that always samples (100% rate, seed=0).
    public static func mockKeepAll() -> DeterministicSampler {
        return .init(seed: 0, samplingRate: 100)
    }

    /// Returns a sampler that never samples (0% rate, seed=0).
    public static func mockRejectAll() -> DeterministicSampler {
        return .init(seed: 0, samplingRate: 0)
    }
}

/// A `RUMSessionSamplerProvider` that returns a decision the test controls, without a RUM feature.
///
/// Set `identity` to simulate an active session, or leave it `nil` to simulate RUM being enabled with
/// no session. The decision is derived the same way `RUMSessionSamplingStore` derives it, so a test
/// that asserts on a composed rate exercises the real composition.
public final class RUMSessionSamplerProviderMock: RUMSessionSamplerProvider {
    public struct Identity {
        public let sessionID: String
        public let sampler: DeterministicSampler

        public init(sessionID: String, sampler: DeterministicSampler) {
            self.sessionID = sessionID
            self.sampler = sampler
        }
    }

    /// The session the mock reports, or `nil` for "no active session".
    public var identity: Identity?

    /// Records the `(policy, rate)` pairs the subject asked for, so a test can assert on the policy.
    public private(set) var requests: [(policy: SamplingRatePolicy, rate: SampleRate)] = []

    public init(identity: Identity? = nil) {
        self.identity = identity
    }

    /// Convenience for a session seeded so that any rate above `0` keeps.
    ///
    /// The seed is `0`, whose Knuth hash is `0` and therefore below the threshold for every non-zero
    /// rate. That makes this the right mock for tests that only care about a session being present:
    /// the decision follows the rate alone, under either policy.
    ///
    /// There is deliberately no `rejectAll()` counterpart. A "reject" sampler is
    /// `DeterministicSampler(seed: 0, samplingRate: 0)`, and both policies rebuild the sampler from
    /// its *seed* at the caller's rate, so the `0` rate is discarded and the mock would keep
    /// everything. Tests that need a dropped session must pin a real seed, as
    /// `RUMSessionSamplerProviderMock(identity:)` allows.
    public static func keepAll(sessionID: String = "session-id") -> RUMSessionSamplerProviderMock {
        .init(identity: .init(sessionID: sessionID, sampler: .mockKeepAll()))
    }

    public func sessionSamplingSnapshot(for policy: SamplingRatePolicy, rate: SampleRate) -> SessionSamplingSnapshot? {
        requests.append((policy: policy, rate: rate))

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

        return SessionSamplingSnapshot(sessionID: identity.sessionID, isSampled: sampler.isSampled)
    }
}
