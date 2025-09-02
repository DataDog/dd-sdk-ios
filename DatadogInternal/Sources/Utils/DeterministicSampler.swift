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
        // We use overflow multiplication to create a "randomized" hash based on the `seed`
        let hash = seed &* Constants.samplerHasher
        let threshold = Float(Constants.maxID) * samplingRate.percentageProportion
        self.samplingRate = samplingRate
        self.shouldSample = Float(hash) < threshold
    }

    /// Based on the `seed` and sampling rate, it returns consistent value decisions.
    /// - Returns: `true` if data should be "sampled".
    public func sample() -> Bool { shouldSample }
}
