/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
@testable import DatadogSessionReplay
@testable import TestUtilities

internal struct Mock: Diffable, Equatable {
    let id: DiffableID
    var data: String = ""

    func isDifferent(than otherElement: Mock) -> Bool {
        return data != otherElement.data
    }
}

class DiffTests: XCTestCase {
    // MARK: - Property Tests

    func testDiffAgainstEqualSequenceShouldBeEmpty() throws {
        // Given
        let sequenceA: [Mock] = [Mock(id: 1), Mock(id: 2), Mock(id: 3)]
        let sequenceB = sequenceA

        // When
        let diff = try computeDiff(oldArray: sequenceA, newArray: sequenceB)

        // Then
        DDAssertReflectionEqual(diff.adds, [])
        DDAssertReflectionEqual(diff.updates, [])
        DDAssertReflectionEqual(diff.removes, [])
        XCTAssertTrue(diff.isEmpty)
    }

    func testDiffOfEmptySequencesShouldBeEmpty() throws {
        // Given
        let sequenceA: [Mock] = []
        let sequenceB: [Mock] = []

        // When
        let diff = try computeDiff(oldArray: sequenceA, newArray: sequenceB)

        // Then
        DDAssertReflectionEqual(diff.adds, [])
        DDAssertReflectionEqual(diff.updates, [])
        DDAssertReflectionEqual(diff.removes, [])
        XCTAssertTrue(diff.isEmpty)
    }

    func testDiffFromEmptySequenceShouldGiveOnlyUpdates() throws {
        // Given
        let sequenceA: [Mock] = []
        let sequenceB: [Mock] = [Mock(id: 1), Mock(id: 2), Mock(id: 3)]

        // When
        let diff = try computeDiff(oldArray: sequenceA, newArray: sequenceB)

        // Then
        DDAssertReflectionEqual(
            diff.adds,
            [
                .init(previousID: nil, new: Mock(id: 1)),
                .init(previousID: 1, new: Mock(id: 2)),
                .init(previousID: 2, new: Mock(id: 3))
            ]
        )
        DDAssertReflectionEqual(diff.updates, [])
        DDAssertReflectionEqual(diff.removes, [])
        XCTAssertFalse(diff.isEmpty)
    }

    func testDiffAgainstEmptySequenceShouldGiveOnlyRemovals() throws {
        // Given
        let sequenceA: [Mock] = [Mock(id: 1), Mock(id: 2), Mock(id: 3)]
        let sequenceB: [Mock] = []

        // When
        let diff = try computeDiff(oldArray: sequenceA, newArray: sequenceB)

        // Then
        DDAssertReflectionEqual(diff.adds, [])
        DDAssertReflectionEqual(diff.updates, [])
        DDAssertReflectionEqual(diff.removes, [.init(id: 1), .init(id: 2), .init(id: 3)])
        XCTAssertFalse(diff.isEmpty)
    }

    func testWhenApplyingDiffOnTopOfTheOriginalSequence_itShouldProduceTheOtherSequence() throws {
        // Test for short long sequences to cover more edge cases
        let testedLengths: [Int] = [2, 5, 500, 1_000]

        try testedLengths.forEach { length in
            // Given
            let originalSequence: [Mock] = (0..<length).map { Mock(id: $0) }

            var randomized = originalSequence
            randomized += ((length + 1)..<(length * 2)).map { Mock(id: $0) } // add new elements
            randomized.shuffle() // randomize order
            randomized = Array(randomized.prefix(.mockRandom(min: 0, max: randomized.count - 1))) // cut at random position

            let newSequence = Array(randomized)

            // When
            let diff = try computeDiff(oldArray: originalSequence, newArray: newSequence)

            // Then
            XCTAssertEqual(originalSequence.merge(diff: diff), newSequence)
        }
    }

    // MARK: - Test Additions

    func testAddingElementsAtTheEnd() throws {
        // Given
        let sequenceA: [Mock] = [Mock(id: 1), Mock(id: 2), Mock(id: 3)]
        let sequenceB: [Mock] = [Mock(id: 1), Mock(id: 2), Mock(id: 3), Mock(id: 4), Mock(id: 5)]

        // When
        let diff = try computeDiff(oldArray: sequenceA, newArray: sequenceB)

        // Then
        XCTAssertEqual(diff.adds.count, 2)
        DDAssertReflectionEqual(diff.adds[0], Diff.Add(previousID: 3, new: Mock(id: 4)))
        DDAssertReflectionEqual(diff.adds[1], Diff.Add(previousID: 4, new: Mock(id: 5)))
        DDAssertReflectionEqual(diff.updates, [])
        DDAssertReflectionEqual(diff.removes, [])
    }

    func testAddingElementsAtTheBeginning() throws {
        // Given
        let sequenceA: [Mock] = [Mock(id: 1), Mock(id: 2), Mock(id: 3)]
        let sequenceB: [Mock] = [Mock(id: 4), Mock(id: 5), Mock(id: 1), Mock(id: 2), Mock(id: 3)]

        // When
        let diff = try computeDiff(oldArray: sequenceA, newArray: sequenceB)

        // Then
        XCTAssertEqual(diff.adds.count, 2)
        DDAssertReflectionEqual(diff.adds[0], Diff.Add(previousID: nil, new: Mock(id: 4)))
        DDAssertReflectionEqual(diff.adds[1], Diff.Add(previousID: 4, new: Mock(id: 5)))
        DDAssertReflectionEqual(diff.updates, [])
        DDAssertReflectionEqual(diff.removes, [])
    }

    func testAddingElementsInTheMiddle() throws {
        // Given
        let sequenceA: [Mock] = [Mock(id: 1), Mock(id: 2), Mock(id: 3)]
        let sequenceB: [Mock] = [Mock(id: 1), Mock(id: 4), Mock(id: 2), Mock(id: 5), Mock(id: 3)]

        // When
        let diff = try computeDiff(oldArray: sequenceA, newArray: sequenceB)

        // Then
        XCTAssertEqual(diff.adds.count, 2)
        DDAssertReflectionEqual(diff.adds[0], Diff.Add(previousID: 1, new: Mock(id: 4)))
        DDAssertReflectionEqual(diff.adds[1], Diff.Add(previousID: 2, new: Mock(id: 5)))
        DDAssertReflectionEqual(diff.updates, [])
        DDAssertReflectionEqual(diff.removes, [])
    }

    // MARK: - Test Removals

    func testRemovingElementsAtTheEnd() throws {
        // Given
        let sequenceA: [Mock] = [Mock(id: 1), Mock(id: 2), Mock(id: 3)]
        let sequenceB: [Mock] = [Mock(id: 1)]

        // When
        let diff = try computeDiff(oldArray: sequenceA, newArray: sequenceB)

        // Then
        DDAssertReflectionEqual(diff.adds, [])
        DDAssertReflectionEqual(diff.updates, [])
        XCTAssertEqual(Set(diff.removes.map { $0.id }), [2, 3])
    }

    func testRemovingElementsAtTheBeginning() throws {
        // Given
        let sequenceA: [Mock] = [Mock(id: 1), Mock(id: 2), Mock(id: 3)]
        let sequenceB: [Mock] = [Mock(id: 3)]

        // When
        let diff = try computeDiff(oldArray: sequenceA, newArray: sequenceB)

        // Then
        DDAssertReflectionEqual(diff.adds, [])
        DDAssertReflectionEqual(diff.updates, [])
        XCTAssertEqual(Set(diff.removes.map { $0.id }), [1, 2])
    }

    func testRemovingElementsInTheMiddle() throws {
        // Given
        let sequenceA: [Mock] = [Mock(id: 1), Mock(id: 2), Mock(id: 3), Mock(id: 4)]
        let sequenceB: [Mock] = [Mock(id: 1), Mock(id: 4)]

        // When
        let diff = try computeDiff(oldArray: sequenceA, newArray: sequenceB)

        // Then
        DDAssertReflectionEqual(diff.adds, [])
        DDAssertReflectionEqual(diff.updates, [])
        XCTAssertEqual(Set(diff.removes.map { $0.id }), [2, 3])
    }

    // MARK: - Test Changing Order

    func testChangingOrderOfElementsAtTheBeginning() throws {
        // Given
        let sequenceA: [Mock] = [Mock(id: 1), Mock(id: 2), Mock(id: 3)]
        let sequenceB: [Mock] = [Mock(id: 2), Mock(id: 1), Mock(id: 3)]

        // When
        let diff = try computeDiff(oldArray: sequenceA, newArray: sequenceB)

        // Then
        XCTAssertEqual(diff.adds.count, 2)
        DDAssertReflectionEqual(diff.adds[0], Diff.Add(previousID: nil, new: Mock(id: 2)))
        DDAssertReflectionEqual(diff.adds[1], Diff.Add(previousID: 2, new: Mock(id: 1)))
        DDAssertReflectionEqual(diff.updates, [])
        XCTAssertEqual(Set(diff.removes.map { $0.id }), [2, 1])
    }

    func testChangingOrderOfElementsAtTheEnd() throws {
        // Given
        let sequenceA: [Mock] = [Mock(id: 1), Mock(id: 2), Mock(id: 3)]
        let sequenceB: [Mock] = [Mock(id: 1), Mock(id: 3), Mock(id: 2)]

        // When
        let diff = try computeDiff(oldArray: sequenceA, newArray: sequenceB)

        // Then
        XCTAssertEqual(diff.adds.count, 2)
        DDAssertReflectionEqual(diff.adds[0], Diff.Add(previousID: 1, new: Mock(id: 3)))
        DDAssertReflectionEqual(diff.adds[1], Diff.Add(previousID: 3, new: Mock(id: 2)))
        DDAssertReflectionEqual(diff.updates, [])
        XCTAssertEqual(Set(diff.removes.map { $0.id }), [3, 2])
    }

    func testChangingOrderOfElementsInTheMiddle() throws {
        // Given
        let sequenceA: [Mock] = [Mock(id: 1), Mock(id: 2), Mock(id: 3), Mock(id: 4)]
        let sequenceB: [Mock] = [Mock(id: 1), Mock(id: 3), Mock(id: 2), Mock(id: 4)]

        // When
        let diff = try computeDiff(oldArray: sequenceA, newArray: sequenceB)

        // Then
        XCTAssertEqual(diff.adds.count, 2)
        DDAssertReflectionEqual(diff.adds[0], Diff.Add(previousID: 1, new: Mock(id: 3)))
        DDAssertReflectionEqual(diff.adds[1], Diff.Add(previousID: 3, new: Mock(id: 2)))
        DDAssertReflectionEqual(diff.updates, [])
        XCTAssertEqual(Set(diff.removes.map { $0.id }), [3, 2])
    }

    func testChangingOrderOfAllElements() throws {
        // Given
        let sequenceA: [Mock] = [Mock(id: 1), Mock(id: 2), Mock(id: 3)]
        let sequenceB: [Mock] = [Mock(id: 2), Mock(id: 3), Mock(id: 1)]

        // When
        let diff = try computeDiff(oldArray: sequenceA, newArray: sequenceB)

        // Then
        XCTAssertEqual(diff.adds.count, 3)
        DDAssertReflectionEqual(diff.adds[0], Diff.Add(previousID: nil, new: Mock(id: 2)))
        DDAssertReflectionEqual(diff.adds[1], Diff.Add(previousID: 2, new: Mock(id: 3)))
        DDAssertReflectionEqual(diff.adds[2], Diff.Add(previousID: 3, new: Mock(id: 1)))
        DDAssertReflectionEqual(diff.updates, [])
        XCTAssertEqual(Set(diff.removes.map { $0.id }), [2, 3, 1])
    }

    // MARK: - Test Finding Updates

    func testUpdatingElementsAtTheBeginning() throws {
        // Given
        let sequenceA: [Mock] = [Mock(id: 1, data: "foo"), Mock(id: 2), Mock(id: 3)]
        let sequenceB: [Mock] = [Mock(id: 1, data: "bar"), Mock(id: 2), Mock(id: 3)]

        // When
        let diff = try computeDiff(oldArray: sequenceA, newArray: sequenceB)

        // Then
        DDAssertReflectionEqual(diff.adds, [])
        DDAssertReflectionEqual(diff.updates, [.init(from: sequenceA[0], to: sequenceB[0])])
        DDAssertReflectionEqual(diff.removes, [])
    }

    func testUpdatingElementsAtTheEnd() throws {
        // Given
        let sequenceA: [Mock] = [Mock(id: 1), Mock(id: 2), Mock(id: 3, data: "foo")]
        let sequenceB: [Mock] = [Mock(id: 1), Mock(id: 2), Mock(id: 3, data: "bar")]

        // When
        let diff = try computeDiff(oldArray: sequenceA, newArray: sequenceB)

        // Then
        DDAssertReflectionEqual(diff.adds, [])
        DDAssertReflectionEqual(diff.updates, [.init(from: sequenceA[2], to: sequenceB[2])])
        DDAssertReflectionEqual(diff.removes, [])
    }

    func testUpdatingElementsInTheMiddle() throws {
        // Given
        let sequenceA: [Mock] = [Mock(id: 1), Mock(id: 2, data: "foo"), Mock(id: 3)]
        let sequenceB: [Mock] = [Mock(id: 1), Mock(id: 2, data: "bar"), Mock(id: 3)]

        // When
        let diff = try computeDiff(oldArray: sequenceA, newArray: sequenceB)

        // Then
        DDAssertReflectionEqual(diff.adds, [])
        DDAssertReflectionEqual(diff.updates, [.init(from: sequenceA[1], to: sequenceB[1])])
        DDAssertReflectionEqual(diff.removes, [])
    }

    func testUpdatingAllElements() throws {
        // Given
        let sequenceA: [Mock] = [Mock(id: 1, data: "foo1"), Mock(id: 2, data: "foo2"), Mock(id: 3, data: "foo3")]
        let sequenceB: [Mock] = [Mock(id: 1, data: "bar1"), Mock(id: 2, data: "bar2"), Mock(id: 3, data: "bar3")]

        // When
        let diff = try computeDiff(oldArray: sequenceA, newArray: sequenceB)

        // Then
        DDAssertReflectionEqual(diff.adds, [])
        DDAssertReflectionEqual(
            diff.updates,
            [
                .init(from: sequenceA[0], to: sequenceB[0]),
                .init(from: sequenceA[1], to: sequenceB[1]),
                .init(from: sequenceA[2], to: sequenceB[2]),
            ]
        )
        DDAssertReflectionEqual(diff.removes, [])
    }

    func testUpdatesAreIgnoredWhenElementChangesItsPosition() throws {
        // Given
        let sequenceA: [Mock] = [Mock(id: 1, data: "foo"), Mock(id: 2), Mock(id: 3)]
        let sequenceB: [Mock] = [Mock(id: 2), Mock(id: 1, data: "bar"), Mock(id: 3)]

        // When
        let diff = try computeDiff(oldArray: sequenceA, newArray: sequenceB)

        // Then
        DDAssertReflectionEqual(
            diff.adds,
            [
                .init(previousID: nil, new: Mock(id: 2)),
                .init(previousID: 2, new: Mock(id: 1, data: "bar")),
            ]
        )
        DDAssertReflectionEqual(diff.updates, [])
        XCTAssertEqual(Set(diff.removes.map { $0.id }), [2, 1])
    }
}

// MARK: - Helpers

extension Array where Element: Diffable {
    func merge(diff: Diff<Element>) -> Self {
        var result: [Element]

        // First, do removals:
        let removedIDs = Set(diff.removes.map({ $0.id }))
        result = self.filter { !removedIDs.contains($0.id) }

        // Then, do additions:
        diff.adds.forEach { addition in
            if let previousID = addition.previousID {
                let beforeIndex = result.firstIndex(where: { $0.id == previousID })!
                result.insert(addition.new, at: beforeIndex + 1)
            } else {
                result.insert(addition.new, at: 0)
            }
        }

        return result
    }
}
