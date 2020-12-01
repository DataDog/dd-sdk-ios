/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import XCTest
@testable import Datadog

private class ConsentSubscriberMock: ConsentSubscriber {
    var consentChange: (oldValue: TrackingConsent, newValue: TrackingConsent)?

    func consentChanged(from oldValue: TrackingConsent, to newValue: TrackingConsent) {
        consentChange = (oldValue: oldValue, newValue: newValue)
    }
}

class ConsentProviderTests: XCTestCase {
    func testGivenInitialConsentSet_whenTheValueChanges_itCanBeRetrieved() {
        let initialConsent: TrackingConsent = [.granted, .notGranted, .pending].randomElement()!
        let newConsent: TrackingConsent = [.granted, .notGranted, .pending].randomElement()!

        // Given
        let provider = ConsentProvider(initialConsent: initialConsent)
        XCTAssertEqual(provider.currentValue, initialConsent)

        // When
        provider.changeConsent(to: newConsent)

        // Then
        XCTAssertEqual(provider.currentValue, newConsent)
    }

    func testGivenInitialConsentSet_whenTheValueChanges_itNotifiesAllSubscribers() {
        let initialConsent: TrackingConsent = [.granted, .notGranted, .pending].randomElement()!
        let newConsent: TrackingConsent = [.granted, .notGranted, .pending].randomElement()!
        let subscribers = (0..<5).map { _ in ConsentSubscriberMock() }

        // Given
        let provider = ConsentProvider(initialConsent: initialConsent)
        subscribers.forEach { subscriber in
            provider.subscribe(consentSubscriber: subscriber)
        }

        // When
        provider.changeConsent(to: newConsent)

        // Then
        subscribers.forEach { subscriber in
            XCTAssertEqual(subscriber.consentChange?.oldValue, initialConsent)
            XCTAssertEqual(subscriber.consentChange?.newValue, newConsent)
        }
    }
}
