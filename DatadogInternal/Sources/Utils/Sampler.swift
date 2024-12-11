/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

/// Alias to represent the sample rate type.
/// The value is between `0.0` and `100.0`, where `0.0` means NO event will be sent and `100.0` means ALL events will be sent.
public typealias SampleRate = Float

/// Protocol for determining sampling decisions.
public protocol Sampling {
    /// Determines whether sampling should be performed.
    ///
    /// - Returns: A boolean value indicating whether sampling should occur.
    ///            `true` if the sample should be kept, `false` if it should be dropped.
    func sample() -> Bool
}

/// Sampler, deciding if events should be sent do Datadog or dropped.
public struct Sampler: Sampling {
    /// Value between `0.0` and `100.0`, where `0.0` means NO event will be sent and `100.0` means ALL events will be sent.
    public let samplingRate: SampleRate

    public init(samplingRate: SampleRate) {
        self.samplingRate = max(0, min(100, samplingRate))
    }

    /// Based on the sampling rate, it returns random value deciding if an event should be "sampled" or not.
    /// - Returns: `true` if event should be sent to Datadog and `false` if it should be dropped.
    public func sample() -> Bool {
        return Float.random(in: 0.0..<100.0) < samplingRate
    }
}

/// A sampler that determines sampling decisions deterministically (the same each time).
internal struct DeterministicSampler: Sampling {
    enum Constants {
        /// Good number for Knuth hashing (large, prime, fit in 64 bit long)
        internal static let samplerHasher: UInt64 = 1_111_111_111_111_111_111
        internal static let maxID: UInt64 = 0xFFFFFFFFFFFFFFFF
    }

    /// Value between `0.0` and `100.0`, where `0.0` means NO event will be sent and `100.0` means ALL events will be sent.
    let samplingRate: SampleRate
    /// Persisted sampling decision.
    private let shouldSample: Bool

    init(shouldSample: Bool, samplingRate: SampleRate) {
        self.samplingRate = samplingRate
        self.shouldSample = shouldSample
    }

    init(baseId: UInt64, samplingRate: SampleRate) {
        // We use overflow multiplication to create a "randomized" hash based on the input id
        let hash = baseId &* Constants.samplerHasher
        let threshold = Float(Constants.maxID) * samplingRate.percentageProportion
        self.samplingRate = samplingRate
        self.shouldSample = Float(hash) < threshold
    }

    func sample() -> Bool { shouldSample }
}

extension SampleRate {
    /// Maximum sampling rate. It means every event is kept.
    public static let maxSampleRate: Self = 100.0

    /// Represents the percentage expressed as a decimal between 0 and 1. For example, 0.25 means 25%.
    public var percentageProportion: Self { self / 100.0 }

    /// Composes two sample rates. For example, one SampleRate of 20% composed with another of 15% will return a percentage of 3%.
    public func composed(with sampleRate: SampleRate) -> Self {
        self.percentageProportion * sampleRate.percentageProportion * 100
    }
}
