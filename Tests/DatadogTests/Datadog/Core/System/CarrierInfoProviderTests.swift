/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

#if canImport(CoreTelephony)

import XCTest
import CoreTelephony

@testable import Datadog

class CarrierInfoProviderTests: XCTestCase {
    /// Mock `CTTelephonyNetworkInfo` when user’s cellular service provider is available.
    private let availableCTTelephonyNetworkInfo = CTTelephonyNetworkInfoMock(
        serviceCurrentRadioAccessTechnology: ["000001": CTRadioAccessTechnologyLTE],
        serviceSubscriberCellularProviders: ["000001": CTCarrierMock(carrierName: "Carrier", isoCountryCode: "US", allowsVOIP: true)]
    )
    /// Mock `CTTelephonyNetworkInfo` when user’s cellular service provider is unavailable.
    private let unavailableCTTelephonyNetworkInfo = CTTelephonyNetworkInfoMock(
        serviceCurrentRadioAccessTechnology: [:],
        serviceSubscriberCellularProviders: [:]
    )

    func testItIsAvailableOnMobile() {
        XCTAssertNotNil(CarrierInfoProvider())
    }

    func testGivenCellularServiceAvailableOnIOS11_whenReadingCurrentCarrierInfo_itReturnsValue() {
        // Given
        let iOS11Provider = iOS11CarrierInfoProvider(networkInfo: availableCTTelephonyNetworkInfo)

        // When
        let iOS11CarrierInfo = CarrierInfoProvider(wrappedProvider: iOS11Provider).current

        // Then
        XCTAssertEqual(iOS11CarrierInfo?.carrierName, "Carrier")
        XCTAssertEqual(iOS11CarrierInfo?.carrierISOCountryCode, "US")
        XCTAssertEqual(iOS11CarrierInfo?.carrierAllowsVOIP, true)
    }

    func testGivenCellularServiceAvailableOnIOS12AndAbove_whenReadingCurrentCarrierInfo_itReturnsValue() {
        if #available(iOS 12, *) {
            // Given
            let iOS12Provider = iOS12CarrierInfoProvider(networkInfo: availableCTTelephonyNetworkInfo)

            // When
            let iOS12CarrierInfo = CarrierInfoProvider(wrappedProvider: iOS12Provider).current

            // Then
            XCTAssertEqual(iOS12CarrierInfo?.carrierName, "Carrier")
            XCTAssertEqual(iOS12CarrierInfo?.carrierISOCountryCode, "US")
            XCTAssertEqual(iOS12CarrierInfo?.carrierAllowsVOIP, true)
        }
    }

    func testGivenCellularServiceUnavailableOnIOS11_whenReadingCurrentCarrierInfo_itReturnsNoValue() {
        // Given
        let iOS11Provider = iOS11CarrierInfoProvider(networkInfo: unavailableCTTelephonyNetworkInfo)

        // When
        let iOS11CarrierInfo = CarrierInfoProvider(wrappedProvider: iOS11Provider).current

        // Then
        XCTAssertNil(iOS11CarrierInfo)
    }

    func testGivenCellularServiceUnavailableOnIOS12AndAbove_whenReadingCurrentCarrierInfo_itReturnsNoValue() {
        if #available(iOS 12, *) {
            // Given
            let iOS12Provider = iOS12CarrierInfoProvider(networkInfo: unavailableCTTelephonyNetworkInfo)

            // When
            let iOS12CarrierInfo = CarrierInfoProvider(wrappedProvider: iOS12Provider).current

            // Then
            XCTAssertNil(iOS12CarrierInfo)
        }
    }

    func testGivenSubscribediOS11CarrierInfoProvider_whenCarrierInfoChanges_itNotifiesSubscribersAfterReadingValue() throws {
        let notifyCarrierInfoChangeExpectation = expectation(description: "Notify `CarrierInfo` change")
        var recordedChange: (old: CarrierInfo?, new: CarrierInfo?)? = nil

        // Given
        let subscriber = ValueObserverMock<CarrierInfo?> { oldValue, newValue in
            recordedChange = (old: oldValue, new: newValue)
            notifyCarrierInfoChangeExpectation.fulfill()
        }

        let iOS11Provider = iOS11CarrierInfoProvider(networkInfo: availableCTTelephonyNetworkInfo)
        iOS11Provider.subscribe(subscriber)

        let initialCarrierInfo = iOS11Provider.current

        // When
        availableCTTelephonyNetworkInfo.changeCarrier(
            newCarrierName: .mockRandom(),
            newISOCountryCode: .mockRandom(),
            newAllowsVOIP: .mockRandom(),
            newRadioAccessTechnology: [CTRadioAccessTechnologyGPRS, CTRadioAccessTechnologyEdge].randomElement()!
        )

        // Then
        let newCarrierInfo = iOS11Provider.current

        waitForExpectations(timeout: 1, handler: nil)
        let notifiedCarrierInfoChange = try XCTUnwrap(recordedChange)
        XCTAssertEqual(notifiedCarrierInfoChange.old, initialCarrierInfo)
        XCTAssertEqual(notifiedCarrierInfoChange.new, newCarrierInfo)
    }

    func testGivenSubscribediOS12CarrierInfoProvider_whenCarrierInfoChanges_itNotifiesSubscribers() throws {
        if #available(iOS 12, *) {
            let notifyCarrierInfoChangeExpectation = expectation(description: "Notify `CarrierInfo` change")
            var recordedChange: (old: CarrierInfo?, new: CarrierInfo?)? = nil

            // Given
            let subscriber = ValueObserverMock<CarrierInfo?> { oldValue, newValue in
                recordedChange = (old: oldValue, new: newValue)
                notifyCarrierInfoChangeExpectation.fulfill()
            }

            let iOS12Provider = iOS12CarrierInfoProvider(networkInfo: availableCTTelephonyNetworkInfo)
            iOS12Provider.subscribe(subscriber)

            let initialCarrierInfo = iOS12Provider.current

            // When
            availableCTTelephonyNetworkInfo.changeCarrier(
                newCarrierName: .mockRandom(),
                newISOCountryCode: .mockRandom(),
                newAllowsVOIP: .mockRandom(),
                newRadioAccessTechnology: [CTRadioAccessTechnologyGPRS, CTRadioAccessTechnologyEdge].randomElement()!
            )

            // Then
            waitForExpectations(timeout: 1, handler: nil)

            let newCarrierInfo = iOS12Provider.current

            let notifiedCarrierInfoChange = try XCTUnwrap(recordedChange)
            XCTAssertEqual(notifiedCarrierInfoChange.old, initialCarrierInfo)
            XCTAssertEqual(notifiedCarrierInfoChange.new, newCarrierInfo)
        }
    }

    func testDifferentCarrierInfoRadioAccessTechnologies() {
        func initializeFrom(coreTelephonyConstant: String) -> CarrierInfo.RadioAccessTechnology {
            return CarrierInfo.RadioAccessTechnology(ctRadioAccessTechnologyConstant: coreTelephonyConstant)
        }

        XCTAssertEqual(initializeFrom(coreTelephonyConstant: CTRadioAccessTechnologyGPRS), .GPRS)
        XCTAssertEqual(initializeFrom(coreTelephonyConstant: CTRadioAccessTechnologyEdge), .Edge)
        XCTAssertEqual(initializeFrom(coreTelephonyConstant: CTRadioAccessTechnologyWCDMA), .WCDMA)
        XCTAssertEqual(initializeFrom(coreTelephonyConstant: CTRadioAccessTechnologyHSDPA), .HSDPA)
        XCTAssertEqual(initializeFrom(coreTelephonyConstant: CTRadioAccessTechnologyHSUPA), .HSUPA)
        XCTAssertEqual(initializeFrom(coreTelephonyConstant: CTRadioAccessTechnologyCDMA1x), .CDMA1x)
        XCTAssertEqual(initializeFrom(coreTelephonyConstant: CTRadioAccessTechnologyCDMAEVDORev0), .CDMAEVDORev0)
        XCTAssertEqual(initializeFrom(coreTelephonyConstant: CTRadioAccessTechnologyCDMAEVDORevA), .CDMAEVDORevA)
        XCTAssertEqual(initializeFrom(coreTelephonyConstant: CTRadioAccessTechnologyCDMAEVDORevB), .CDMAEVDORevB)
        XCTAssertEqual(initializeFrom(coreTelephonyConstant: CTRadioAccessTechnologyeHRPD), .eHRPD)
        XCTAssertEqual(initializeFrom(coreTelephonyConstant: CTRadioAccessTechnologyLTE), .LTE)
        XCTAssertEqual(initializeFrom(coreTelephonyConstant: "invalid"), .unknown)
    }
}

#endif
