/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

/// http://xoshiro.di.unimi.it
/// by David Blackman and Sebastiano Vigna
internal struct XoshiroRandomNumberGenerator: RandomNumberGenerator {
    typealias StateType = (UInt64, UInt64, UInt64, UInt64)

    private var state: StateType = (0, 0, 0, 0)

    internal init(seed: StateType) {
        self.state = seed
    }

    internal init<T>(seed: T) where T: FixedWidthInteger {
        self.state = (
            UInt64(seed),
            UInt64(seed),
            UInt64(seed),
            UInt64(seed)
        )
    }

    internal mutating func next() -> UInt64 {
        // Derived from public domain implementation of xoshiro256**:
        let x = state.1 &* 5
        let result = ((x &<< 7) | (x &>> 57)) &* 9
        let t = state.1 &<< 17
        state.2 ^= state.0
        state.3 ^= state.1
        state.1 ^= state.2
        state.0 ^= state.3
        state.2 ^= t
        state.3 = (state.3 &<< 45) | (state.3 &>> 19)
        return result
    }
}
