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
        XCTAssertEqual(counts, [1.0])
        XCTAssertEqual(offset, 10)
    }

    func testAddMultipleValues_sameIndex() {
        var store = CollapsingLowestDenseStore(maxNumBins: 128)
        store.add(index: 5, count: 1.0)
        store.add(index: 5, count: 3.0)

        XCTAssertEqual(store.count, 4.0)

        let (counts, _) = store.contiguousBins()
        XCTAssertEqual(counts, [4.0])
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
        XCTAssertEqual(offset, 5)
        XCTAssertEqual(counts.count, 6) // indices 5..10
        XCTAssertEqual(counts[0], 1.0) // index 5
        XCTAssertEqual(counts[1], 0.0) // index 6
        XCTAssertEqual(counts[2], 2.0) // index 7
        XCTAssertEqual(counts[5], 3.0) // index 10
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
        XCTAssertEqual(offset, 5)
        XCTAssertEqual(counts[0], 2.0) // index 5
        XCTAssertEqual(counts[5], 1.0) // index 10
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
        XCTAssertEqual(offset, -5)
        XCTAssertEqual(counts.count, 3) // -5, -4, -3
        XCTAssertEqual(counts[0], 1.0) // index -5
        XCTAssertEqual(counts[2], 2.0) // index -3
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
        XCTAssertEqual(indexOffset, 7)
        XCTAssertEqual(counts.count, 4) // indices 7, 8, 9, 10

        // index 0 collapsed into the lowest valid bin (7), index 10 stays at position 3
        XCTAssertEqual(counts[0], 1.0) // collapsed value at index 7
        XCTAssertEqual(counts[3], 1.0) // original value at index 10

        let totalCount = counts.reduce(0, +)
        XCTAssertEqual(totalCount, 2.0)
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

    // MARK: - Large Sparse Range

    func testSparseRange_withinMaxBins() {
        var store = CollapsingLowestDenseStore(maxNumBins: 2_048)
        store.add(index: 0, count: 1.0)
        store.add(index: 100, count: 1.0)

        XCTAssertEqual(store.count, 2.0)
        XCTAssertEqual(store.minIndex, 0)
        XCTAssertEqual(store.maxIndex, 100)

        let (counts, _) = store.contiguousBins()
        XCTAssertEqual(counts.count, 101)
        XCTAssertEqual(counts[0], 1.0)
        XCTAssertEqual(counts[100], 1.0)
    }
}
