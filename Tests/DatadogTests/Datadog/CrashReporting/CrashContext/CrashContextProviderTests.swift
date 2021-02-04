/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import XCTest
@testable import Datadog

class CrashContextProviderTests: XCTestCase {
    func testWhenInitialized_itProvidesInitialContext() {
        let initialTrackingConsent: TrackingConsent = .mockRandom()

        // When
        let provider = CrashContextProvider(
            consentProvider: .init(initialConsent: initialTrackingConsent)
        )

        // Then
        XCTAssertEqual(
            provider.currentCrashContext.lastTrackingConsent,
            .init(trackingConsent: initialTrackingConsent)
        )
        XCTAssertNil(provider.currentCrashContext.lastRUMViewEvent)
    }

    func testWhenRUMViewChanges_itNotifiesNewContext() {
        let expectation = self.expectation(description: "Notify new crash context value")
        let randomRUMView: RUMViewEvent = .mockRandom()
        let provider = CrashContextProvider(
            consentProvider: .init(initialConsent: .mockRandom())
        )
        provider.onCrashContextChange = { newContext in
            XCTAssertEqual(newContext.lastRUMViewEvent, randomRUMView)
            expectation.fulfill()
        }

        // When
        provider.update(lastRUMViewEvent: randomRUMView)

        // Then
        waitForExpectations(timeout: 1, handler: nil)
        XCTAssertEqual(provider.currentCrashContext.lastRUMViewEvent, randomRUMView)
    }

    func testWhenTrackingConsentChanges_itNotifiesNewContext() {
        let expectation = self.expectation(description: "Notify new crash context value")
        let randomTrackingConsent: TrackingConsent = .mockRandom()
        let provider = CrashContextProvider(
            consentProvider: .init(initialConsent: .mockRandom())
        )
        provider.onCrashContextChange = { newContext in
            XCTAssertEqual(newContext.lastTrackingConsent, .init(trackingConsent: randomTrackingConsent))
            expectation.fulfill()
        }

        // When
        provider.update(lastTrackingConsent: randomTrackingConsent)

        // Then
        waitForExpectations(timeout: 1, handler: nil)
        XCTAssertEqual(
            provider.currentCrashContext.lastTrackingConsent,
            .init(trackingConsent: randomTrackingConsent)
        )
    }
}
