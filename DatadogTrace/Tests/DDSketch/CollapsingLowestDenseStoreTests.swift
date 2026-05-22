/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

@testable import DatadogTrace
import XCTest

final class CollapsingLowestDenseStoreTests: XCTestCase {
    // MARK: - Basic Operations

    func testEmpty_contiguousBins() {
        let store = CollapsingLowestDenseStore(maxNumBins: 128)
        let (counts, offset) = store.contiguousBins()
        XCTAssertTrue(counts.isEmpty)
        XCTAssertEqual(offset, 0)
        XCTAssertEqual(store.count, 0)
    }

    func testAddSingleValue() {
        var store = CollapsingLowestDenseStore(maxNumBins: 128)
        store.add(index: 10, count: 1.0)

        XCTAssertEqual(store.count, 1.0)
        XCTAssertEqual(store.minIndex, 10)
        XCTAssertEqual(store.maxIndex, 10)

        let (counts, offset) = store.contiguousBins()
        XCTAssertEqual(Array(counts), [1.0])
        XCTAssertEqual(offset, 10)
    }

    func testAddMultipleValues_sameIndex() {
        var store = CollapsingLowestDenseStore(maxNumBins: 128)
        store.add(index: 5, count: 1.0)
        store.add(index: 5, count: 3.0)

        XCTAssertEqual(store.count, 4.0)

        let (counts, _) = store.contiguousBins()
        XCTAssertEqual(Array(counts), [4.0])
    }

    func testAddMultipleValues_differentIndices() {
        var store = CollapsingLowestDenseStore(maxNumBins: 128)
        store.add(index: 5, count: 1.0)
        store.add(index: 7, count: 2.0)
        store.add(index: 10, count: 3.0)

        XCTAssertEqual(store.count, 6.0)
        XCTAssertEqual(store.minIndex, 5)
        XCTAssertEqual(store.maxIndex, 10)

        let (counts, offset) = store.contiguousBins()
        let countsArray = Array(counts)
        XCTAssertEqual(offset, 5)
        XCTAssertEqual(countsArray.count, 6) // indices 5..10
        XCTAssertEqual(countsArray[0], 1.0) // index 5
        XCTAssertEqual(countsArray[1], 0.0) // index 6
        XCTAssertEqual(countsArray[2], 2.0) // index 7
        XCTAssertEqual(countsArray[5], 3.0) // index 10
    }

    func testAddZeroCount_noEffect() {
        var store = CollapsingLowestDenseStore(maxNumBins: 128)
        store.add(index: 5, count: 0)
        XCTAssertEqual(store.count, 0)
        let (counts, _) = store.contiguousBins()
        XCTAssertTrue(counts.isEmpty)
    }

    // MARK: - Extend Low

    func testAddLowerIndex_extendsRange() {
        var store = CollapsingLowestDenseStore(maxNumBins: 128)
        store.add(index: 10, count: 1.0)
        store.add(index: 5, count: 2.0)

        XCTAssertEqual(store.minIndex, 5)
        XCTAssertEqual(store.maxIndex, 10)
        XCTAssertEqual(store.count, 3.0)

        let (counts, offset) = store.contiguousBins()
        let countsArray = Array(counts)
        XCTAssertEqual(offset, 5)
        XCTAssertEqual(countsArray[0], 2.0) // index 5
        XCTAssertEqual(countsArray[5], 1.0) // index 10
    }

    // MARK: - Collapsing

    func testCollapse_whenExceedingMaxBins() {
        var store = CollapsingLowestDenseStore(maxNumBins: 4)

        // Add values at indices 0..4 (needs 5 bins, exceeds max of 4)
        for i in 0...4 {
            store.add(index: i, count: 1.0)
        }

        XCTAssertEqual(store.count, 5.0)
        XCTAssertTrue(store.isCollapsed)

        let (counts, _) = store.contiguousBins()
        XCTAssertLessThanOrEqual(counts.count, 4)

        // Total count must be preserved even after collapsing
        let totalCount = counts.reduce(0, +)
        XCTAssertEqual(totalCount, 5.0)
    }

    func testCollapse_preservesTotalCount() {
        var store = CollapsingLowestDenseStore(maxNumBins: 3)

        for i in 0..<10 {
            store.add(index: i, count: Double(i + 1))
        }

        let expectedTotal: Double = (1...10).reduce(0) { $0 + Double($1) } // 55
        XCTAssertEqual(store.count, expectedTotal)

        let (counts, _) = store.contiguousBins()
        let totalCount = counts.reduce(0, +)
        XCTAssertEqual(totalCount, expectedTotal)
    }

    // MARK: - Negative Indices

    func testNegativeIndices() {
        var store = CollapsingLowestDenseStore(maxNumBins: 128)
        store.add(index: -5, count: 1.0)
        store.add(index: -3, count: 2.0)

        XCTAssertEqual(store.count, 3.0)
        XCTAssertEqual(store.minIndex, -5)
        XCTAssertEqual(store.maxIndex, -3)

        let (counts, offset) = store.contiguousBins()
        let countsArray = Array(counts)
        XCTAssertEqual(offset, -5)
        XCTAssertEqual(countsArray.count, 3) // -5, -4, -3
        XCTAssertEqual(countsArray[0], 1.0) // index -5
        XCTAssertEqual(countsArray[2], 2.0) // index -3
    }

    // MARK: - Collapsing After Already Collapsed

    func testCollapse_addBelow_goesToFirstBin() {
        var store = CollapsingLowestDenseStore(maxNumBins: 3)
        store.add(index: 0, count: 1.0)
        store.add(index: 1, count: 1.0)
        store.add(index: 2, count: 1.0)
        store.add(index: 3, count: 1.0) // triggers collapse

        XCTAssertTrue(store.isCollapsed)

        // Adding below minimum should go to the lowest valid bin
        store.add(index: -10, count: 5.0)
        XCTAssertEqual(store.count, 9.0) // 4 original + 5 new

        let (counts, _) = store.contiguousBins()
        let totalCount = counts.reduce(0, +)
        XCTAssertEqual(totalCount, 9.0)
    }

    func testCollapse_downward_restructuresBins() {
        var store = CollapsingLowestDenseStore(maxNumBins: 4)
        store.add(index: 10, count: 1.0)
        store.add(index: 0, count: 1.0) // triggers downward collapse

        XCTAssertTrue(store.isCollapsed)
        XCTAssertEqual(store.count, 2.0)

        // adjustedMin = 10 - 4 + 1 = 7, so bins should cover 7...10
        XCTAssertEqual(store.minIndex, 7)
        XCTAssertEqual(store.maxIndex, 10)

        let (counts, indexOffset) = store.contiguousBins()
        let countsArray = Array(counts)
        XCTAssertEqual(indexOffset, 7)
        XCTAssertEqual(countsArray.count, 4) // indices 7, 8, 9, 10

        // index 0 collapsed into the lowest valid bin (7), index 10 stays at position 3
        XCTAssertEqual(countsArray[0], 1.0) // collapsed value at index 7
        XCTAssertEqual(countsArray[3], 1.0) // original value at index 10

        let totalCount = countsArray.reduce(0, +)
        XCTAssertEqual(totalCount, 2.0)
    }

    func testCollapse_whenNewValueFarAboveRange_resetsToFloor() {
        // When the new value is so far above the existing range that
        // `adjustedMin >= maxIndex`, the entire previous range collapses into the
        // new floor in a single step. This exercises the early-return branch of
        // `collapse()`.
        var store = CollapsingLowestDenseStore(maxNumBins: 3)
        store.add(index: 0, count: 2.0)
        store.add(index: 1, count: 3.0)
        // adjustedMin = 100 - 3 + 1 = 98, which is >> maxIndex (1).
        store.add(index: 100, count: 1.0)

        XCTAssertTrue(store.isCollapsed)
        XCTAssertEqual(store.count, 6.0)
        XCTAssertEqual(store.minIndex, 98)
        XCTAssertEqual(store.maxIndex, 100)

        let (counts, indexOffset) = store.contiguousBins()
        XCTAssertEqual(indexOffset, 98)
        // All previous counts (2 + 3 = 5) folded into the new floor at index 98;
        // the new value (1) lands at the new top index 100.
        XCTAssertEqual(Array(counts), [5.0, 0.0, 1.0])
    }

    func testCollapse_monotonicallyIncreasing_staysBounded() {
        var store = CollapsingLowestDenseStore(maxNumBins: 10)

        for i in 0...1_000 {
            store.add(index: i, count: 1.0)
        }

        XCTAssertEqual(store.count, 1_001)
        XCTAssertLessThanOrEqual(store.bins.count, 10)

        let (counts, _) = store.contiguousBins()
        XCTAssertLessThanOrEqual(counts.count, 10)

        let totalCount = counts.reduce(0, +)
        XCTAssertEqual(totalCount, 1_001)
    }

    // MARK: - Example-Based Collapse

    func testFixture_upwardCollapseProducesExpectedBinLayout() {
        // Concrete example pinning the upward-collapse layout end-to-end:
        // five consecutive adds at indices 0..4 into a store with maxNumBins = 4
        // force a collapse where indices 0 and 1 fold into the new floor (bin 1).
        var store = CollapsingLowestDenseStore(maxNumBins: 4)
        for i in 0...4 {
            store.add(index: i, count: 1.0)
        }

        // After the collapse: adjustedMin = 4 - 4 + 1 = 1.
        //   bin 1 = 2 (folded from old indices 0 and 1)
        //   bin 2 = 1 (preserved)
        //   bin 3 = 1 (preserved)
        //   bin 4 = 1 (newly added)
        XCTAssertTrue(store.isCollapsed)
        XCTAssertEqual(store.count, 5.0)
        XCTAssertEqual(store.minIndex, 1)
        XCTAssertEqual(store.maxIndex, 4)

        let (counts, indexOffset) = store.contiguousBins()
        XCTAssertEqual(indexOffset, 1)
        XCTAssertEqual(Array(counts), [2.0, 1.0, 1.0, 1.0])
    }

    // MARK: - Defensive Initialization

    func testInit_clampsZeroMaxNumBinsToOne() {
        // A non-positive `maxNumBins` would have no sensible interpretation; the SDK
        // must not crash on internal misuse, so the store clamps to 1 and stays operational.
        var store = CollapsingLowestDenseStore(maxNumBins: 0)
        XCTAssertEqual(store.maxNumBins, 1)

        store.add(index: 5, count: 1.0)
        store.add(index: 6, count: 1.0) // would trigger collapse since maxNumBins == 1
        XCTAssertEqual(store.count, 2.0)
        XCTAssertTrue(store.isCollapsed)
    }

    func testInit_clampsNegativeMaxNumBinsToOne() {
        var store = CollapsingLowestDenseStore(maxNumBins: -10)
        XCTAssertEqual(store.maxNumBins, 1)

        store.add(index: 0, count: 3.0)
        XCTAssertEqual(store.count, 3.0)
    }

    // MARK: - Large Sparse Range

    func testSparseRange_withinMaxBins() {
        var store = CollapsingLowestDenseStore(maxNumBins: 2_048)
        store.add(index: 0, count: 1.0)
        store.add(index: 100, count: 1.0)

        XCTAssertEqual(store.count, 2.0)
        XCTAssertEqual(store.minIndex, 0)
        XCTAssertEqual(store.maxIndex, 100)

        let (counts, _) = store.contiguousBins()
        let countsArray = Array(counts)
        XCTAssertEqual(countsArray.count, 101)
        XCTAssertEqual(countsArray[0], 1.0)
        XCTAssertEqual(countsArray[100], 1.0)
    }
}
