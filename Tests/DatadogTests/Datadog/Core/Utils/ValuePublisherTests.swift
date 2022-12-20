/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
@testable import Datadog

class ValuePublisherTests: XCTestCase {
    func testWhenInitialized_itStoresInitialValue() {
        let randomInt: Int = .mockRandom()

        // When
        let publisher = ValuePublisher<Int>(initialValue: randomInt)

        // Then
        XCTAssertEqual(publisher.currentValue, randomInt)
    }

    func testWhenValueChanges_itStoresUpdatedValue() {
        let publisher = ValuePublisher<Int>(initialValue: .mockRandom())

        // When
        let randomInt: Int = .mockRandom()
        publisher.publishSyncOrAsync(randomInt)

        // Then
        XCTAssertEqual(publisher.currentValue, randomInt)
    }

    func testWhenValueChanges_itNotifiesObservers() {
        let numberOfObservers = 10
        let initialValue: Int = .mockRandom()
        let newValue: Int = .mockRandom()

        let expectation = self.expectation(description: "All observers received new value")
        expectation.expectedFulfillmentCount = numberOfObservers

        let observers: [ValueObserverMock<Int>] = (0..<numberOfObservers).map { _ in
            ValueObserverMock<Int> { old, new in
                XCTAssertEqual(old, initialValue)
                XCTAssertEqual(new, newValue)
                expectation.fulfill()
            }
        }

        let publisher = ValuePublisher<Int>(initialValue: initialValue)
        observers.forEach { publisher.subscribe($0) }

        // When
        publisher.publishSyncOrAsync(newValue)

        // Then
        waitForExpectations(timeout: 1, handler: nil)
    }

    func testWhenNonEquatableValueChanges_itNotifiesObserversOnAllChanges() {
        struct NonEquatableValue {
            let value: Int
        }

        let expectation = self.expectation(description: "Notify observer on 6 changes")
        expectation.expectedFulfillmentCount = 6

        let publisher = ValuePublisher<NonEquatableValue>(
            initialValue: NonEquatableValue(value: .mockRandom())
        )
        let observer = ValueObserverMock<NonEquatableValue> { old, new in
            expectation.fulfill()
        }
        publisher.subscribe(observer)

        // When
        let changes = [1, 1, 2, 2, 3, 3].map { NonEquatableValue(value: $0) }
        changes.forEach { nextChange in publisher.publishSyncOrAsync(nextChange) }

        // Then
        waitForExpectations(timeout: 1, handler: nil)
    }

    func testWhenEquatableValueChanges_itNotifiesObserversOnDistinctChanges() {
        struct EquatableValue: Equatable {
            let value: Int
        }

        let expectation = self.expectation(description: "Notify observer on 3 distinct changes")
        expectation.expectedFulfillmentCount = 3

        let publisher = ValuePublisher<EquatableValue>(
            initialValue: EquatableValue(value: .mockRandom())
        )
        let observer = ValueObserverMock<EquatableValue> { old, new in
            XCTAssertNotEqual(old, new)
            expectation.fulfill()
        }
        publisher.subscribe(observer)

        // When
        let changes = [1, 1, 2, 2, 3, 3].map { EquatableValue(value: $0) }
        changes.forEach { nextChange in publisher.publishSyncOrAsync(nextChange) }

        // Then
        waitForExpectations(timeout: 1, handler: nil)
    }

    func testWhenValueMutates_itStoresMutatedValue() {
        struct MutableData {
            var array = [Int]()
        }

        let randomInfo = MutableData()

        // When
        let publisher = ValuePublisher<MutableData>(initialValue: randomInfo)
        DispatchQueue.concurrentPerform(iterations: 5) { i in
            publisher.mutateAsync { info in
                info.array.append(i)
            }
        }

        // Then
        let retrievedData = publisher.currentValue
        XCTAssertEqual(Set(retrievedData.array), Set(0..<5))
    }

    // MARK: - Thread safety

    func testValueCanBeWrittenAndReadOnAnyThread() {
        let publisher = ValuePublisher<Int>(initialValue: .mockRandom())

        // swiftlint:disable opening_brace
        callConcurrently(
            closures: [
                { publisher.publishSyncOrAsync(.mockRandom()) },
                { publisher.publishSyncOrAsync(publisher.currentValue % 2) },
                { _ = publisher.currentValue },
                { publisher.subscribe(ValueObserverMock<Int>()) }
            ],
            iterations: 50
        )
        // swiftlint:enable opening_brace
    }

    func testSubscribersAreNotifiedOnSingleThread() {
        let publisher = ValuePublisher<Int>(initialValue: .mockRandom())

        // State mutated by the `ValueObserverMock<Int>` - the `ValuePublisher` ensures its thread safety
        var mutableState: Bool = .random()

        let observer = ValueObserverMock<Int> { _, _ in
            mutableState.toggle()
        }
        publisher.subscribe(observer)

        DispatchQueue.concurrentPerform(iterations: 100) { _ in
            publisher.publishSyncOrAsync(.mockRandom())
        }
    }
}
