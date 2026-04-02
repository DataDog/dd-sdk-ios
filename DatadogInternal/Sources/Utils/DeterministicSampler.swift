/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

 import Foundation

/// Deterministic sampler that makes consistent sampling decisions for a given `seed`.
///
/// This sampler uses Knuth hashing to compute a uniform hash of the `seed`, allowing
/// deterministic sampling based on a sampling rate `samplingRate`.
///
/// Conforms to the `Sampling` protocol.
public struct DeterministicSampler: Sampling, Equatable, Sendable {
    enum Constants {
        /// Good number for Knuth hashing (large, prime, fit in 64 bit long)
        internal static let samplerHasher: UInt64 = 1_111_111_111_111_111_111
        internal static let maxID: UInt64 = 0xFFFFFFFFFFFFFFFF
    }

    /// The seed used as input for Knuth hashing. Stored so callers can inspect or compose samplers.
    public let seed: UInt64
    /// Value between `0.0` and `100.0`, where `0.0` means NO event will be sent and `100.0` means ALL events will be sent.
    public let samplingRate: SampleRate
    /// Persisted sampling decision for this seed and rate.
    public let isSampled: Bool

    /// Initializes a new instance of `DeterministicSampler`.
    ///
    /// - Parameters:
    ///   - seed: A 64-bit unsigned integer used as the base input for Knuth hashing.
    ///   - samplingRate: A percentage value between `0.0` and `100.0`.
    ///     - `0.0` disables sampling entirely (no data is sampled).
    ///     - `100.0` enables full sampling (all data is sampled).
    public init(seed: UInt64, samplingRate: SampleRate) {
        let normalizedSampleRate = samplingRate.normalized
        self.seed = seed
        self.samplingRate = normalizedSampleRate
        if normalizedSampleRate == 100.0 {
            self.isSampled = true
        } else {
            // We use overflow multiplication to create a "randomized" hash based on the `seed`
            let hash = seed &* Constants.samplerHasher
            let threshold = Double(Constants.maxID) * Double(samplingRate) / 100.0
            self.isSampled = Double(hash) < threshold
        }
    }

    /// Based on the `seed` and sampling rate, it returns consistent value decisions.
    /// - Returns: `true` if data should be "sampled".
    public func sample() -> Bool { isSampled }

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
        DeterministicSampler(seed: seed, samplingRate: samplingRate.composed(with: childRate.normalized))
    }
}

extension DeterministicSampler {
    /// Convenience initializer that derives the seed from a UUID value.
    ///
    /// The last 48 bits of the UUID (the node component) are extracted directly from
    /// memory and used as the seed, bypassing string conversion entirely.
    ///
    /// **seed=0 fallback:** When UUID memory layout is unexpected (asserted in debug),
    /// the seed defaults to 0. The Knuth hash of 0 is 0, which is always `<= threshold`
    /// for any `samplingRate > 0`, so invalid inputs are always sampled (fail-open).
    ///
    /// - Parameters:
    ///   - uuid: A `UUID` value.
    ///   - samplingRate: A percentage value between `0.0` and `100.0`.
    public init(uuid: UUID, samplingRate: SampleRate) {
        assert(MemoryLayout<UUID>.size == 16)
        let seed = withUnsafePointer(to: uuid.uuid) { uuidPointer in
            let buffer = UnsafeRawBufferPointer(start: uuidPointer, count: MemoryLayout<UUID>.size)
            let last8Bytes = buffer.loadUnaligned(fromByteOffset: 8, as: UInt64.self)
            return UInt64(bigEndian: last8Bytes) & 0x0000FFFFFFFFFFFF
        }
        self.init(seed: seed, samplingRate: samplingRate)
    }
}
