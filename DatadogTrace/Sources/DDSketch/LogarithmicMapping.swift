/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

/// Maps positive `Double` values to integer bin indices using logarithmic scaling.
///
/// Ported from the Go reference:
/// https://github.com/DataDog/sketches-go/blob/master/ddsketch/mapping/logarithmic_mapping.go
///
/// The mapping guarantees that any value `v` mapped to index `i` satisfies:
///   `value(at: i)` is within `relativeAccuracy` of `v`.
internal struct LogarithmicMapping {
    /// Ratio controlling bin width: `(1 + relativeAccuracy) / (1 - relativeAccuracy)`.
    let gamma: Double

    /// Precomputed `1.0 / log(gamma)` for fast index computation.
    let multiplier: Double

    /// Offset applied to the index (0.0 for standard usage).
    let indexOffset: Double

    /// Smallest positive value that can be mapped to a valid `Int32` index.
    let minIndexableValue: Double

    /// Largest positive value that can be mapped to a valid `Int32` index.
    let maxIndexableValue: Double

    /// The target relative accuracy, in (0, 1). A value of 0.01 means 1% accuracy.
    let relativeAccuracy: Double

    /// Largest exponent that does not overflow `exp()` for IEEE 754 doubles.
    /// `exp(709.78...)` reaches `Double.greatestFiniteMagnitude`; `710` returns `+infinity`.
    /// Used as a conservative ceiling when deriving `maxIndexableValue`. Matches the
    /// Go reference: https://github.com/DataDog/sketches-go/blob/master/ddsketch/mapping/logarithmic_mapping.go
    private static let maxSafeExpArgument: Double = 709.0

    /// Lower bound for the `relativeAccuracy` clamp. Values below this would make
    /// `gamma` round to `1.0` in double precision and `multiplier = 1 / log(gamma)`
    /// non-finite, which would later trap when converting raw indices to `Int`.
    private static let minSafeRelativeAccuracy: Double = 0.0001

    /// Upper bound for the `relativeAccuracy` clamp. Values too close to `1.0`
    /// produce a tiny `(1 - r)` denominator and an enormous `gamma`. The bound
    /// here is generous; the production value used by `DDSketch.makeForStats()`
    /// is `0.01`.
    private static let maxSafeRelativeAccuracy: Double = 0.9999

    init(relativeAccuracy: Double) {
        // An SDK must never crash the host app on internal misuse. The math is
        // only well-defined for `relativeAccuracy` in `(0, 1)`, and even then the
        // open-interval boundaries produce non-finite intermediate values that
        // would trap downstream. We clamp to a safe inner range; the resulting
        // sketch stays operational and only this one sketch is affected.
        let clamped = Swift.min(
            Swift.max(relativeAccuracy, LogarithmicMapping.minSafeRelativeAccuracy),
            LogarithmicMapping.maxSafeRelativeAccuracy
        )

        self.relativeAccuracy = clamped
        self.gamma = (1 + clamped) / (1 - clamped)
        self.multiplier = 1.0 / log(gamma)
        self.indexOffset = 0.0

        self.minIndexableValue = max(
            exp((Double(Int32.min) - indexOffset) / multiplier + 1),
            Double.leastNormalMagnitude * gamma
        )

        self.maxIndexableValue = min(
            exp((Double(Int32.max) - indexOffset) / multiplier - 1),
            exp(LogarithmicMapping.maxSafeExpArgument) / (2.0 * gamma / (1.0 + gamma))
        )
    }

    /// Returns the bin index for a positive value.
    func index(for value: Double) -> Int {
        let rawIndex = log(value) * multiplier + indexOffset
        if rawIndex >= 0 {
            return Int(rawIndex)
        }
        return Int(rawIndex) - 1
    }

    /// Returns a representative value for a given bin index.
    /// The returned value is within `relativeAccuracy` of any value mapped to this index.
    func value(at index: Int) -> Double {
        return lowerBound(index: index) * (1 + relativeAccuracy)
    }

    /// Returns the lower bound of the bin at the given index.
    func lowerBound(index: Int) -> Double {
        return exp((Double(index) - indexOffset) / multiplier)
    }
}
