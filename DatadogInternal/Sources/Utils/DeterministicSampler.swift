/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

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

    public init(baseId: UInt64, samplingRate: SampleRate) {
        // We use overflow multiplication to create a "randomized" hash based on the input id
        let hash = baseId &* Constants.samplerHasher
        let threshold = Float(Constants.maxID) * samplingRate.percentageProportion
        self.samplingRate = samplingRate
        self.shouldSample = Float(hash) < threshold
    }

    public func sample() -> Bool { shouldSample }
}
