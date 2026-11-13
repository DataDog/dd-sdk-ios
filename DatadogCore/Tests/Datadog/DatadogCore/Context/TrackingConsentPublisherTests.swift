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

        publisher.consent = .notGranted

        // TrackingConsentPublisher publishes in sync
        waitForExpectations(timeout: 0)
    }

    func testWhenConsentReturnsToAnEarlierValue_itPublishesANewRevision() {
        // Given
        let publisher = TrackingConsentPublisher(consent: .pending)
        var published: [TrackingConsentPublisher.Value] = []
        publisher.publish { published.append($0) }

        // When
        publisher.consent = .notGranted
        publisher.consent = .pending

        // Then
        XCTAssertEqual(published, [.init(consent: .notGranted, revision: 1), .init(consent: .pending, revision: 2)])
    }
}
