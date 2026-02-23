/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

/// Deterministic sampler that makes consistent sampling decisions for a given `seed`.
///
/// This sampler uses Knuth hashing to compute a uniform hash of the `seed`, allowing
/// deterministic sampling based on a sampling rate `samplingRate`.
///
/// Conforms to the `Sampling` protocol.
public struct DeterministicSampler: Sampling {
    enum Constants {
        /// Good number for Knuth hashing (large, prime, fit in 64 bit long)
        internal static let samplerHasher: UInt64 = 1_111_111_111_111_111_111
        internal static let maxID: UInt64 = 0xFFFFFFFFFFFFFFFF
    }

    /// The seed used as input for Knuth hashing. Stored so callers can inspect or compose samplers.
    public let seed: UInt64
    /// Value between `0.0` and `100.0`, where `0.0` means NO event will be sent and `100.0` means ALL events will be sent.
    public let samplingRate: SampleRate
    /// Persisted sampling decision.
    private let shouldSample: Bool

    /// Initializes a new instance of `DeterministicSampler`.
    ///
    /// - Parameters:
    ///   - seed: A 64-bit unsigned integer used as the base input for Knuth hashing.
    ///   - samplingRate: A percentage value between `0.0` and `100.0`.
    ///     - `0.0` disables sampling entirely (no data is sampled).
    ///     - `100.0` enables full sampling (all data is sampled).
    public init(seed: UInt64, samplingRate: SampleRate) {
        self.seed = seed
        // We use overflow multiplication to create a "randomized" hash based on the `seed`
        self.samplingRate = samplingRate
        if samplingRate >= 100.0 {
            self.shouldSample = true
        } else if samplingRate <= 0.0 {
            self.shouldSample = false
        } else {
            let hash = seed &* Constants.samplerHasher
            let threshold = Double(Constants.maxID) * Double(samplingRate) / 100.0
            self.shouldSample = Double(hash) <= threshold
        }
    }

    /// Convenience initializer that derives the seed from a session UUID string.
    ///
    /// The last segment of the UUID (the 12-hex-character node component) is parsed as a
    /// hexadecimal `UInt64` and used as the seed. Falls back to `0` for malformed inputs.
    ///
    /// **seed=0 fallback:** When UUID parsing fails, seed defaults to 0. The Knuth hash
    /// of 0 is 0, which is always `<= threshold` for any `samplingRate > 0`, so malformed
    /// UUIDs are always sampled (fail-open). This is intentional — a broken UUID should
    /// not silently drop data.
    ///
    /// - Parameters:
    ///   - sessionID: A UUID string in the standard `xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx` format.
    ///   - samplingRate: A percentage value between `0.0` and `100.0`.
    public init(sessionID: String, samplingRate: SampleRate) {
        let seed = sessionID.split(separator: "-").last.flatMap { UInt64($0, radix: 16) } ?? 0
        self.init(seed: seed, samplingRate: samplingRate)
    }

    /// Returns a new `DeterministicSampler` that applies both this sampler's rate and `childRate`,
    /// while preserving the same seed so sampling decisions remain consistent.
    ///
    /// Use this when a child feature has its own sampling rate that must be applied on top of a
    /// parent session sampling rate. The composed rate ensures the Knuth-hash invariant is kept:
    /// the same seed always produces the same decision for a given effective rate.
    ///
    /// **Float precision note:** `SampleRate` is a `Float`, which limits composed rates to
    /// approximately 6 decimal digits of precision. For typical integer or single-decimal rates
    /// (e.g. 50.0, 12.5) this has no observable impact.
    ///
    /// - Parameter childRate: The child feature's sampling rate (0.0–100.0).
    /// - Returns: A new sampler with `samplingRate.composed(with: childRate)` as its rate.
    public func combined(with childRate: SampleRate) -> DeterministicSampler {
        DeterministicSampler(seed: seed, samplingRate: samplingRate.composed(with: childRate))
    }

    /// Based on the `seed` and sampling rate, it returns consistent value decisions.
    /// - Returns: `true` if data should be "sampled".
    public func sample() -> Bool { shouldSample }
}

extension DeterministicSampler: Equatable {
    public static func == (lhs: DeterministicSampler, rhs: DeterministicSampler) -> Bool {
        lhs.seed == rhs.seed && lhs.samplingRate == rhs.samplingRate
    }
}
