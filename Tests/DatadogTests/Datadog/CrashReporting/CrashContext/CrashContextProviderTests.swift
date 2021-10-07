/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import XCTest
@testable import Datadog
import CoreTelephony

/// This suite tests if `CrashContextProvider` gets updated by different SDK components, each updating
/// separate part of the `CrashContext` information.
class CrashContextProviderTests: XCTestCase {
    // MARK: - `TrackingConsent` Integration

    func testWhenTrackingConsentValueChangesInConsentProvider_thenCrashContextProviderNotifiesNewContext() {
        let expectation = self.expectation(description: "Notify new crash context")
        let initialTrackingConsent: TrackingConsent = .mockRandom()
        let randomTrackingConsent: TrackingConsent = .mockRandom(otherThan: initialTrackingConsent)

        let trackingConsentProvider = ConsentProvider(initialConsent: initialTrackingConsent)
        let crashContextProvider = CrashContextProvider(
            consentProvider: trackingConsentProvider,
            userInfoProvider: .mockAny(),
            networkConnectionInfoProvider: NetworkConnectionInfoProviderMock.mockAny(),
            carrierInfoProvider: CarrierInfoProviderMock.mockAny(),
            rumViewEventProvider: .mockRandom()
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
        let randomRUMViewEvent: RUMEvent<RUMViewEvent> = RUMEvent(model: RUMViewEvent.mockRandom())

        let rumViewEventProvider = ValuePublisher<RUMEvent<RUMViewEvent>?>(initialValue: randomRUMViewEvent)
        let crashContextProvider = CrashContextProvider(
            consentProvider: .mockAny(),
            userInfoProvider: .mockAny(),
            networkConnectionInfoProvider: NetworkConnectionInfoProviderMock.mockAny(),
            carrierInfoProvider: CarrierInfoProviderMock.mockAny(),
            rumViewEventProvider: rumViewEventProvider
        )

        let initialContext = crashContextProvider.currentCrashContext
        var updatedContext: CrashContext?

        // When
        let rumWithCrashContextIntegration = RUMWithCrashContextIntegration(rumViewEventProvider: rumViewEventProvider)
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
            networkConnectionInfoProvider: NetworkConnectionInfoProviderMock.mockAny(),
            carrierInfoProvider: CarrierInfoProviderMock.mockAny(),
            rumViewEventProvider: .mockRandom()
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
        let initialNetworkConnectionInfo: NetworkConnectionInfo = .mockRandom()
        let wrappedProvider = NetworkConnectionInfoProviderMock(networkConnectionInfo: initialNetworkConnectionInfo)
        let mainProvider = NetworkConnectionInfoProvider(wrappedProvider: wrappedProvider)

        let crashContextProvider = CrashContextProvider(
            consentProvider: .mockAny(),
            userInfoProvider: .mockAny(),
            networkConnectionInfoProvider: mainProvider,
            carrierInfoProvider: CarrierInfoProviderMock.mockAny(),
            rumViewEventProvider: .mockRandom()
        )

        let initialContext = crashContextProvider.currentCrashContext
        var updatedContext: CrashContext?

        // When
        crashContextProvider.onCrashContextChange = { newContext in
            updatedContext = newContext
            expectation.fulfill()
        }
        wrappedProvider.set(current: .mockRandom()) // change `NetworkConnectionInfo` in wrapped provider
        let currentNetworkConnectionInfo = mainProvider.current // obtain new info through the main provider

        // Then
        waitForExpectations(timeout: 1, handler: nil)
        XCTAssertEqual(initialContext.lastNetworkConnectionInfo, initialNetworkConnectionInfo)
        XCTAssertEqual(updatedContext?.lastNetworkConnectionInfo, currentNetworkConnectionInfo)
    }

    // MARK: - `CarrierInfo` Integration

    private let ctTelephonyNetworkInfoMock = CTTelephonyNetworkInfoMock(
        serviceCurrentRadioAccessTechnology: ["000001": CTRadioAccessTechnologyLTE],
        serviceSubscriberCellularProviders: ["000001": CTCarrierMock(carrierName: "Carrier", isoCountryCode: "US", allowsVOIP: true)]
    )

    func testGivenRunningOniOS11_whenCurrentValueIsObtainedFromCarrierInfoProvider_thenCrashContextProviderNotifiesNewContext() throws {
        let expectation = self.expectation(description: "Notify new crash context")
        let carrierInfoProvider = CarrierInfoProvider(
            wrappedProvider: iOS11CarrierInfoProvider(networkInfo: ctTelephonyNetworkInfoMock)
        )

        let crashContextProvider = CrashContextProvider(
            consentProvider: .mockAny(),
            userInfoProvider: .mockAny(),
            networkConnectionInfoProvider: NetworkConnectionInfoProviderMock.mockAny(),
            carrierInfoProvider: carrierInfoProvider,
            rumViewEventProvider: .mockRandom()
        )

        let initialContext = crashContextProvider.currentCrashContext
        var updatedContext: CrashContext?

        // When
        crashContextProvider.onCrashContextChange = { newContext in
            updatedContext = newContext
            expectation.fulfill()
        }
        ctTelephonyNetworkInfoMock.changeCarrier(
            newCarrierName: .mockRandom(),
            newISOCountryCode: .mockRandom(),
            newAllowsVOIP: .mockRandom(),
            newRadioAccessTechnology: [CTRadioAccessTechnologyLTE, CTRadioAccessTechnologyEdge].randomElement()!
        ) // change `CTCarrier` info
        _ = carrierInfoProvider.current // obtain `CarrierInfo` from provider

        // Then
        waitForExpectations(timeout: 1, handler: nil)
        let carrierInfoInInitialContext = try XCTUnwrap(initialContext.lastCarrierInfo)
        let carrierInfoInUpdatedContext = try XCTUnwrap(updatedContext?.lastCarrierInfo)
        XCTAssertNotEqual(carrierInfoInInitialContext, carrierInfoInUpdatedContext)
    }

    func testGivenRunningOniOS12AndAbove_whenCTCarrierChanges_thenCrashContextProviderNotifiesNewContext() throws {
        if #available(iOS 12, *) {
            let expectation = self.expectation(description: "Notify new crash context")
            let carrierInfoProvider = CarrierInfoProvider(
                wrappedProvider: iOS12CarrierInfoProvider(networkInfo: ctTelephonyNetworkInfoMock)
            )

            let crashContextProvider = CrashContextProvider(
                consentProvider: .mockAny(),
                userInfoProvider: .mockAny(),
                networkConnectionInfoProvider: NetworkConnectionInfoProviderMock.mockAny(),
                carrierInfoProvider: carrierInfoProvider,
                rumViewEventProvider: .mockRandom()
            )

            let initialContext = crashContextProvider.currentCrashContext
            var updatedContext: CrashContext?

            // When
            crashContextProvider.onCrashContextChange = { newContext in
                updatedContext = newContext
                expectation.fulfill()
            }
            ctTelephonyNetworkInfoMock.changeCarrier(
                newCarrierName: .mockRandom(),
                newISOCountryCode: .mockRandom(),
                newAllowsVOIP: .mockRandom(),
                newRadioAccessTechnology: [CTRadioAccessTechnologyLTE, CTRadioAccessTechnologyEdge].randomElement()!
            ) // change `CTCarrier` info

            // Then
            waitForExpectations(timeout: 1, handler: nil)
            let carrierInfoInInitialContext = try XCTUnwrap(initialContext.lastCarrierInfo)
            let carrierInfoInUpdatedContext = try XCTUnwrap(updatedContext?.lastCarrierInfo)
            XCTAssertNotEqual(carrierInfoInInitialContext, carrierInfoInUpdatedContext)
        }
    }

    // MARK: - Thread safety

    func testWhenContextIsWrittenAndReadFromDifferentThreads_itRunsAllOperationsSafely() {
        let consentProvider: ConsentProvider = .mockAny()
        let rumViewEventProvider: ValuePublisher<RUMEvent<RUMViewEvent>?> = .mockRandom()
        let userInfoProvider: UserInfoProvider = .mockAny()
        let networkInfoWrappedProvider = NetworkConnectionInfoProviderMock(networkConnectionInfo: .mockRandom())
        let networkInfoMainProvider = NetworkConnectionInfoProvider(wrappedProvider: networkInfoWrappedProvider)
        let carrierInfoWrappedProvider = CarrierInfoProviderMock(carrierInfo: .mockRandom())
        let carrierInfoMainProvider = CarrierInfoProvider(wrappedProvider: carrierInfoWrappedProvider)

        let provider = CrashContextProvider(
            consentProvider: consentProvider,
            userInfoProvider: userInfoProvider,
            networkConnectionInfoProvider: networkInfoMainProvider,
            carrierInfoProvider: carrierInfoMainProvider,
            rumViewEventProvider: .mockRandom()
        )

        withExtendedLifetime(provider) {
            // swiftlint:disable opening_brace
            callConcurrently(
                closures: [
                    { _ = provider.currentCrashContext },
                    { consentProvider.changeConsent(to: .mockRandom()) },
                    { userInfoProvider.value = .mockRandom() },
                    {
                        networkInfoWrappedProvider.set(current: .mockRandom())
                        _ = networkInfoMainProvider.current
                    },
                    {
                        carrierInfoWrappedProvider.set(current: .mockRandom())
                        _ = carrierInfoMainProvider.current
                    },
                    { rumViewEventProvider.publishSyncOrAsync(.mockRandom()) },
                ],
                iterations: 50
            )
            // swiftlint:enable opening_brace
        }
    }
}
