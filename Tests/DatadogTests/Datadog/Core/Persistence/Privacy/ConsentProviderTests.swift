/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import XCTest
@testable import Datadog

class ConsentProviderTests: XCTestCase {
    func testGivenInitialConsentSet_whenTheValueChanges_itCanBeRetrieved() {
        let initialConsent: TrackingConsent = .mockRandom()
        let newConsent: TrackingConsent = .mockRandom(otherThan: initialConsent)

        // Given
        let provider = ConsentProvider(initialConsent: initialConsent)
        XCTAssertEqual(provider.currentValue, initialConsent)

        // When
        provider.changeConsent(to: newConsent)

        // Then
        XCTAssertEqual(provider.currentValue, newConsent)
    }

    func testGivenInitialConsentSet_whenTheValueChanges_itNotifiesAllSubscribers() {
        let initialConsent: TrackingConsent = .mockRandom()
        let newConsent: TrackingConsent = .mockRandom(otherThan: initialConsent)

        let expectation = self.expectation(description: "Notify all 5 observers")
        expectation.expectedFulfillmentCount = 5
        let subscribers = (0..<5).map { _ in
            ValueObserverMock<TrackingConsent> { _, _ in expectation.fulfill() }
        }

        // Given
        let provider = ConsentProvider(initialConsent: initialConsent)
        subscribers.forEach { subscriber in provider.subscribe(subscriber) }

        // When
        provider.changeConsent(to: newConsent)

        // Then
        waitForExpectations(timeout: 0.5, handler: nil)
        subscribers.forEach { subscriber in
            XCTAssertEqual(subscriber.lastChange?.oldValue, initialConsent)
            XCTAssertEqual(subscriber.lastChange?.newValue, newConsent)
        }
    }
}
