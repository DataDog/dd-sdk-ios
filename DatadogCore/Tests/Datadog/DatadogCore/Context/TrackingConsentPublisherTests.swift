/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
@testable import DatadogCore

class TrackingConsentPublisherTests: XCTestCase {
    func testInitialValue() throws {
        let publisher = TrackingConsentPublisher(consent: .pending)
        XCTAssertEqual(publisher.initialValue, .init(consent: .pending, revision: 0))
    }

    func testPublishTrackingConsent() throws {
        let expectation = expectation(description: "tracking consenr publisher publishes data")

        // Given
        let publisher = TrackingConsentPublisher(consent: .granted)

        // When
        publisher.publish {
            // Then
            XCTAssertEqual($0, .init(consent: .notGranted, revision: 1))
            expectation.fulfill()
        }

        publisher.update(.notGranted) {}

        // TrackingConsentPublisher publishes in sync
        waitForExpectations(timeout: 0)
    }

    func testWhenConsentReturnsToAnEarlierValue_itPublishesANewRevision() {
        // Given
        let publisher = TrackingConsentPublisher(consent: .pending)
        var published: [TrackingConsentPublisher.Value] = []
        publisher.publish { published.append($0) }

        // When
        publisher.update(.notGranted) {}
        publisher.update(.pending) {}

        // Then
        XCTAssertEqual(published, [.init(consent: .notGranted, revision: 1), .init(consent: .pending, revision: 2)])
    }

    func testWhenConsentDoesNotChange_itDoesNotPublish() {
        // Given
        let publisher = TrackingConsentPublisher(consent: .granted)
        var published: [TrackingConsentPublisher.Value] = []
        var changes = 0
        publisher.publish { published.append($0) }

        // When
        publisher.update(.granted) { changes += 1 }

        // Then
        XCTAssertEqual(published, [])
        XCTAssertEqual(changes, 0)
    }

    func testWhenConsentChanges_itCallsWhenChangedAfterPublishing() {
        // Given
        let publisher = TrackingConsentPublisher(consent: .granted)
        var calls: [String] = []
        publisher.publish { _ in calls.append("publish") }

        // When
        publisher.update(.notGranted) { calls.append("whenChanged") }

        // Then
        XCTAssertEqual(calls, ["publish", "whenChanged"])
        XCTAssertEqual(publisher.consent, .notGranted)
    }
}
