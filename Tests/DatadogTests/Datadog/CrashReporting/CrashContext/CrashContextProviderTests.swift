/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import XCTest
@testable import Datadog

/// This suite tests if `CrashContextProvider` gets updated by different SDK components, each delivering
/// separate part of the `CrashContext` information.
///
/// Individual tests should not rely directly on `update(_:)` methods of the `CrashContextProvider`.
/// Instead, they should instantiate and mock the `update(_:)` caller to test and document the integration.
class CrashContextProviderTests: XCTestCase {
    // MARK: - `TrackingConsent` Integration

    func testWhenTrackingConsentValueChangesInConsentProvider_thenCrashContextProviderNotifiesNewContext() {
        let expectation = self.expectation(description: "Notify new crash context")
        let initialTrackingConsent: TrackingConsent = .mockRandom()
        let randomTrackingConsent: TrackingConsent = .mockRandom()

        let trackingConsentProvider = ConsentProvider(initialConsent: initialTrackingConsent)
        let crashContextProvider = CrashContextProvider(
            consentProvider: trackingConsentProvider,
            userInfoProvider: .mockAny(),
            networkConnectionInfoProvider: NetworkConnectionInfoProviderMock.mockAny()
        )

        let initialContext = crashContextProvider.currentCrashContext
        var updatedContext: CrashContext?

        // When
        crashContextProvider.onCrashContextChange = { newContext in
            updatedContext = newContext
            expectation.fulfill()
        }
        trackingConsentProvider.changeConsent(to: randomTrackingConsent)

        // Then
        waitForExpectations(timeout: 1, handler: nil)
        XCTAssertEqual(initialContext.lastTrackingConsent, initialTrackingConsent)
        XCTAssertEqual(updatedContext?.lastTrackingConsent, randomTrackingConsent)
    }

    // MARK: - `RUMViewEvent` Integration

    func testWhenRUMWithCrashContextIntegrationIsUpdated_thenCrashContextProviderNotifiesNewContext() {
        let expectation = self.expectation(description: "Notify new crash context")
        let randomRUMViewEvent: RUMEvent<RUMViewEvent> = .mockRandomWith(model: RUMViewEvent.mockRandom())

        let crashContextProvider = CrashContextProvider(
            consentProvider: .mockAny(),
            userInfoProvider: .mockAny(),
            networkConnectionInfoProvider: NetworkConnectionInfoProviderMock.mockAny()
        )
        let rumWithCrashContextIntegration = RUMWithCrashContextIntegration(crashContextProvider: crashContextProvider)

        let initialContext = crashContextProvider.currentCrashContext
        var updatedContext: CrashContext?

        // When
        crashContextProvider.onCrashContextChange = { newContext in
            updatedContext = newContext
            expectation.fulfill()
        }
        rumWithCrashContextIntegration.update(lastRUMViewEvent: randomRUMViewEvent)

        // Then
        waitForExpectations(timeout: 1, handler: nil)
        XCTAssertNil(initialContext.lastRUMViewEvent)
        XCTAssertEqual(updatedContext?.lastRUMViewEvent, randomRUMViewEvent)
    }

    // MARK: - `UserInfo` Integration

    func testWhenUserInfoValueChangesInUserInfoProvider_thenCrashContextProviderNotifiesNewContext() {
        let expectation = self.expectation(description: "Notify new crash context")
        let initialUserInfo: UserInfo = .mockRandom()
        let randomUserInfo: UserInfo = .mockRandom()

        let userInfoProvider = UserInfoProvider()
        userInfoProvider.value = initialUserInfo

        let crashContextProvider = CrashContextProvider(
            consentProvider: .mockAny(),
            userInfoProvider: userInfoProvider,
            networkConnectionInfoProvider: NetworkConnectionInfoProviderMock.mockAny()
        )

        let initialContext = crashContextProvider.currentCrashContext
        var updatedContext: CrashContext?

        // When
        crashContextProvider.onCrashContextChange = { newContext in
            updatedContext = newContext
            expectation.fulfill()
        }
        userInfoProvider.value = randomUserInfo

        // Then
        waitForExpectations(timeout: 1, handler: nil)
        XCTAssertEqual(initialContext.lastUserInfo, initialUserInfo)
        XCTAssertEqual(updatedContext?.lastUserInfo, randomUserInfo)
    }

    // MARK: - `NetworkConnectionInfo` Integration

    func testWhenCurrentValueIsObtainedFromNetworkConnectionInfoProvider_thenCrashContextProviderNotifiesNewContext() {
        let expectation = self.expectation(description: "Notify new crash context")
        let networkConnectionInfoProvider = NetworkConnectionInfoProvider()

        let crashContextProvider = CrashContextProvider(
            consentProvider: .mockAny(),
            userInfoProvider: .mockAny(),
            networkConnectionInfoProvider: networkConnectionInfoProvider
        )

        let initialContext = crashContextProvider.currentCrashContext
        var updatedContext: CrashContext?

        // When
        crashContextProvider.onCrashContextChange = { newContext in
            updatedContext = newContext
            expectation.fulfill()
        }
        let currentNetworkConnectionInfo = networkConnectionInfoProvider.current

        // Then
        waitForExpectations(timeout: 1, handler: nil)
        XCTAssertEqual(initialContext.lastNetworkConnectionInfo, currentNetworkConnectionInfo)
        XCTAssertEqual(updatedContext?.lastNetworkConnectionInfo, currentNetworkConnectionInfo)
    }

    // MARK: - Thread safety

    func testWhenContextIsWrittenAndReadFromDifferentThreads_itRunsAllOperationsSafely() {
        let consentProvider: ConsentProvider = .mockAny()
        let userInfoProvider: UserInfoProvider = .mockAny()
        let networkConnectionInfoProvider: NetworkConnectionInfoProviderMock = .mockAny()

        let provider = CrashContextProvider(
            consentProvider: consentProvider,
            userInfoProvider: userInfoProvider,
            networkConnectionInfoProvider: networkConnectionInfoProvider
        )

        withExtendedLifetime(provider) {
            // swiftlint:disable opening_brace
            callConcurrently(
                closures: [
                    { _ = provider.currentCrashContext },
                    { consentProvider.changeConsent(to: .mockRandom()) },
                    { userInfoProvider.value = .mockRandom() },
                    { _ = networkConnectionInfoProvider.current },
                    { provider.update(lastRUMViewEvent: .mockRandomWith(model: RUMViewEvent.mockRandom())) },
                ],
                iterations: 50
            )
            // swiftlint:enable opening_brace
        }
    }
}
