/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

@testable import DatadogTrace
import XCTest

final class LogarithmicMappingTests: XCTestCase {
    // MARK: - Initialization

    func testInit_relativeAccuracyOf1Percent() {
        let mapping = LogarithmicMapping(relativeAccuracy: 0.01)

        XCTAssertEqual(mapping.relativeAccuracy, 0.01)
        XCTAssertEqual(mapping.gamma, (1.01) / (0.99), accuracy: 1e-12)
        XCTAssertEqual(mapping.multiplier, 1.0 / log(mapping.gamma), accuracy: 1e-12)
        XCTAssertEqual(mapping.indexOffset, 0.0)
    }

    // MARK: - Index Computation

    func testIndex_oneReturnsZeroOrNegativeOne() {
        let mapping = LogarithmicMapping(relativeAccuracy: 0.01)
        let idx = mapping.index(for: 1.0)
        // log(1.0) = 0.0, so index should be 0 or -1 depending on floor behavior
        XCTAssertTrue(idx == 0 || idx == -1)
    }

    func testIndex_monotonicallyIncreasing() {
        let mapping = LogarithmicMapping(relativeAccuracy: 0.01)
        let values: [Double] = [0.001, 0.01, 0.1, 1, 10, 100, 1_000, 10_000, 1_000_000]
        var previousIndex = Int.min

        for value in values {
            let idx = mapping.index(for: value)
            XCTAssertGreaterThanOrEqual(idx, previousIndex, "index must increase for value \(value)")
            previousIndex = idx
        }
    }

    func testIndex_closeValues_sameOrAdjacentBins() {
        let mapping = LogarithmicMapping(relativeAccuracy: 0.01)
        let v1 = 100.0
        let v2 = 100.5
        let idx1 = mapping.index(for: v1)
        let idx2 = mapping.index(for: v2)
        // Close values within 1% should be in same or adjacent bin
        XCTAssertTrue(abs(idx1 - idx2) <= 1)
    }

    // MARK: - Relative Accuracy Guarantee

    func testRelativeAccuracy_valuesAreWithinBounds() {
        let accuracy = 0.01
        let mapping = LogarithmicMapping(relativeAccuracy: accuracy)
        let testValues: [Double] = [0.1, 1.0, 10.0, 100.0, 1_000.0, 50_000.0, 1_000_000.0]

        for value in testValues {
            let idx = mapping.index(for: value)
            let lower = mapping.lowerBound(index: idx)
            let upper = mapping.lowerBound(index: idx + 1)

            XCTAssertLessThanOrEqual(
                lower,
                value * (1 + accuracy),
                "lower bound \(lower) should be <= value*1.01 (\(value * 1.01)) for value \(value)"
            )
            XCTAssertGreaterThanOrEqual(
                upper,
                value * (1 - accuracy),
                "upper bound \(upper) should be >= value*0.99 (\(value * 0.99)) for value \(value)"
            )
        }
    }

    // MARK: - Value at Index

    func testValue_roundTrip() {
        let accuracy = 0.01
        let mapping = LogarithmicMapping(relativeAccuracy: accuracy)

        for value in [1.0, 50.0, 1_000.0, 500_000.0] {
            let idx = mapping.index(for: value)
            let recovered = mapping.value(at: idx)
            let relativeError = abs(recovered - value) / value
            XCTAssertLessThan(
                relativeError,
                accuracy * 2,
                "recovered value \(recovered) should be close to \(value)"
            )
        }
    }

    // MARK: - Boundary Values

    func testMinIndexableValue_isPositive() {
        let mapping = LogarithmicMapping(relativeAccuracy: 0.01)
        XCTAssertGreaterThan(mapping.minIndexableValue, 0)
    }

    func testMaxIndexableValue_isFinite() {
        let mapping = LogarithmicMapping(relativeAccuracy: 0.01)
        XCTAssertTrue(mapping.maxIndexableValue.isFinite)
        XCTAssertGreaterThan(mapping.maxIndexableValue, 1e300)
    }

    func testMinIndexableValue_producesValidIndex() {
        let mapping = LogarithmicMapping(relativeAccuracy: 0.01)
        let idx = mapping.index(for: mapping.minIndexableValue)
        XCTAssertGreaterThanOrEqual(idx, Int(Int32.min))
    }

    func testMaxIndexableValue_producesValidIndex() {
        let mapping = LogarithmicMapping(relativeAccuracy: 0.01)
        let idx = mapping.index(for: mapping.maxIndexableValue)
        XCTAssertLessThanOrEqual(idx, Int(Int32.max))
    }

    // MARK: - Different Accuracies

    func testHigherAccuracy_producesMoreBins() {
        let coarse = LogarithmicMapping(relativeAccuracy: 0.05)
        let fine = LogarithmicMapping(relativeAccuracy: 0.01)

        let idxCoarse = coarse.index(for: 1_000_000.0) - coarse.index(for: 1.0)
        let idxFine = fine.index(for: 1_000_000.0) - fine.index(for: 1.0)

        XCTAssertGreaterThan(
            idxFine,
            idxCoarse,
            "finer accuracy should use more bins for the same range"
        )
    }
}
