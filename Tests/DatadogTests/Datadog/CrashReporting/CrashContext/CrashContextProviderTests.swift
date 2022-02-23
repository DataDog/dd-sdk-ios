/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import XCTest
#if canImport(CoreTelephony)
import CoreTelephony
#endif

@testable import Datadog

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
            rumViewEventProvider: .mockRandom(),
            rumSessionStateProvider: .mockAny(),
            appStateListener: AppStateListenerMock.mockAny()
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

    func testWhenRUMWithCrashContextIntegrationIsUpdatedWithRUMViewEvent_thenCrashContextProviderNotifiesNewContext() {
        let expectation = self.expectation(description: "Notify new crash context")
        let initialRUMViewEvent: RUMViewEvent = .mockRandom()
        let randomRUMViewEvent: RUMViewEvent = .mockRandom()

        let rumViewEventProvider = ValuePublisher<RUMViewEvent?>(initialValue: initialRUMViewEvent)
        let crashContextProvider = CrashContextProvider(
            consentProvider: .mockAny(),
            userInfoProvider: .mockAny(),
            networkConnectionInfoProvider: NetworkConnectionInfoProviderMock.mockAny(),
            carrierInfoProvider: CarrierInfoProviderMock.mockAny(),
            rumViewEventProvider: rumViewEventProvider,
            rumSessionStateProvider: .mockAny(),
            appStateListener: AppStateListenerMock.mockAny()
        )

        let initialContext = crashContextProvider.currentCrashContext
        var updatedContext: CrashContext?

        // When
        let rumWithCrashContextIntegration = RUMWithCrashContextIntegration(
            rumViewEventProvider: rumViewEventProvider,
            rumSessionStateProvider: .mockAny()
        )
        crashContextProvider.onCrashContextChange = { newContext in
            updatedContext = newContext
            expectation.fulfill()
        }
        rumWithCrashContextIntegration.update(lastRUMViewEvent: randomRUMViewEvent)

        // Then
        waitForExpectations(timeout: 1, handler: nil)
        XCTAssertEqual(initialContext.lastRUMViewEvent, initialRUMViewEvent)
        XCTAssertEqual(updatedContext?.lastRUMViewEvent, randomRUMViewEvent)
    }

    // MARK: - RUM Session State Integration

    func testWhenRUMWithCrashContextIntegrationIsUpdatedWithRUMSessionState_thenCrashContextProviderNotifiesNewContext() {
        let expectation = self.expectation(description: "Notify new crash context")
        let initialRUMSessionState: RUMSessionState = .mockRandom()
        let randomRUMSessionState: RUMSessionState = .mockRandom()

        let rumSessionStateProvider = ValuePublisher<RUMSessionState?>(initialValue: initialRUMSessionState)
        let crashContextProvider = CrashContextProvider(
            consentProvider: .mockAny(),
            userInfoProvider: .mockAny(),
            networkConnectionInfoProvider: NetworkConnectionInfoProviderMock.mockAny(),
            carrierInfoProvider: CarrierInfoProviderMock.mockAny(),
            rumViewEventProvider: .mockRandom(),
            rumSessionStateProvider: rumSessionStateProvider,
            appStateListener: AppStateListenerMock.mockAny()
        )

        let initialContext = crashContextProvider.currentCrashContext
        var updatedContext: CrashContext?

        // When
        let rumWithCrashContextIntegration = RUMWithCrashContextIntegration(
            rumViewEventProvider: .mockRandom(),
            rumSessionStateProvider: rumSessionStateProvider
        )
        crashContextProvider.onCrashContextChange = { newContext in
            updatedContext = newContext
            expectation.fulfill()
        }
        rumWithCrashContextIntegration.update(lastRUMSessionState: randomRUMSessionState)

        // Then
        waitForExpectations(timeout: 1, handler: nil)
        XCTAssertEqual(initialContext.lastRUMSessionState, initialRUMSessionState)
        XCTAssertEqual(updatedContext?.lastRUMSessionState, randomRUMSessionState)
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
            rumViewEventProvider: .mockRandom(),
            rumSessionStateProvider: .mockAny(),
            appStateListener: AppStateListenerMock.mockAny()
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

    func testWhenCurrentValueIsObtainedFromNetworkConnectionInfoProvider_thenCrashContextProviderNotifiesNewContext() throws {
        let expectation = self.expectation(description: "Notify new crash context")
        let initialNetworkConnectionInfo: NetworkConnectionInfo = .mockRandom()
        let wrappedProvider = NetworkConnectionInfoProviderMock(networkConnectionInfo: initialNetworkConnectionInfo)
        let mainProvider = NetworkConnectionInfoProvider(wrappedProvider: wrappedProvider)

        let crashContextProvider = CrashContextProvider(
            consentProvider: .mockAny(),
            userInfoProvider: .mockAny(),
            networkConnectionInfoProvider: mainProvider,
            carrierInfoProvider: CarrierInfoProviderMock.mockAny(),
            rumViewEventProvider: .mockRandom(),
            rumSessionStateProvider: .mockAny(),
            appStateListener: AppStateListenerMock.mockAny()
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
        let updatedNetworkConnectionInfo = try XCTUnwrap(updatedContext?.lastNetworkConnectionInfo)
        XCTAssertEqual(initialContext.lastNetworkConnectionInfo, initialNetworkConnectionInfo, "It must store initial network info")
        XCTAssertEqual(updatedNetworkConnectionInfo, currentNetworkConnectionInfo, "It must store updated network info")
    }

    // MARK: - `CarrierInfo` Integration
    #if !os(tvOS)

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
            rumViewEventProvider: .mockRandom(),
            rumSessionStateProvider: .mockAny(),
            appStateListener: AppStateListenerMock.mockAny()
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
                rumViewEventProvider: .mockRandom(),
                rumSessionStateProvider: .mockAny(),
                appStateListener: AppStateListenerMock.mockAny()
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
    #endif

    // MARK: - `AppStateListener` Integration

    func testWhenAppStateChangeIsTrackedByAppStateListener_thenCrashContextProviderNotifiesNewContext() {
        let expectation = self.expectation(description: "Notify new crash context")

        let notificationCenter = NotificationCenter()
        let appStateListener = AppStateListener(
            dateProvider: SystemDateProvider(),
            initialAppState: .active,
            notificationCenter: notificationCenter
        )

        let crashContextProvider = CrashContextProvider(
            consentProvider: .mockAny(),
            userInfoProvider: .mockAny(),
            networkConnectionInfoProvider: NetworkConnectionInfoProviderMock.mockAny(),
            carrierInfoProvider: CarrierInfoProviderMock.mockAny(),
            rumViewEventProvider: .mockRandom(),
            rumSessionStateProvider: .mockAny(),
            appStateListener: appStateListener
        )

        let initialContext = crashContextProvider.currentCrashContext
        var updatedContext: CrashContext?

        // When
        crashContextProvider.onCrashContextChange = { newContext in
            updatedContext = newContext
            expectation.fulfill()
        }
        notificationCenter.post(name: UIApplication.didEnterBackgroundNotification, object: nil) // app goes to background

        // Then
        waitForExpectations(timeout: 1, handler: nil)
        XCTAssertTrue(initialContext.lastIsAppInForeground, "It must track initial app state ('foreground')")
        XCTAssertEqual(updatedContext?.lastIsAppInForeground, false, "It must track app state update (to 'background')")
    }

    // MARK: - Thread safety

    func testWhenContextIsWrittenAndReadFromDifferentThreads_itRunsAllOperationsSafely() {
        let consentProvider: ConsentProvider = .mockAny()
        let rumViewEventProvider: ValuePublisher<RUMViewEvent?> = .mockRandom()
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
            rumViewEventProvider: .mockRandom(),
            rumSessionStateProvider: .mockAny(),
            appStateListener: AppStateListenerMock.mockAny()
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
