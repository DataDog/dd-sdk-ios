/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if canImport(CoreTelephony) && !os(macOS)

import XCTest
import CoreTelephony
import DatadogInternal
import TestUtilities

@testable import DatadogCore

class CarrierInfoPublisherTests: XCTestCase {
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

    private var isIOS16OrAbove: Bool {
        if #available(iOS 16, *) {
            return true
        }
        return false
    }

    func testGivenCellularServiceAvailable_itProvidesInitialValue() throws {
        try XCTSkipIf(isIOS16OrAbove, "`CarrierInfo` is always nil on iOS 16+ — see testGivenIOS16OrAbove_itProvidesNoInitialValue")

        // Given
        let publisher = CarrierInfoPublisher(networkInfo: availableCTTelephonyNetworkInfo)

        // Then
        XCTAssertEqual(publisher.initialValue?.carrierName, "Carrier")
        XCTAssertEqual(publisher.initialValue?.carrierISOCountryCode, "US")
        XCTAssertEqual(publisher.initialValue?.carrierAllowsVOIP, true)
    }

    func testGivenCellularServiceUnAvailable_itProvidesNoInitialValue() throws {
        try XCTSkipIf(isIOS16OrAbove, "`CarrierInfo` is always nil on iOS 16+ — see testGivenIOS16OrAbove_itProvidesNoInitialValue")

        // Given
        let publisher = CarrierInfoPublisher(networkInfo: unavailableCTTelephonyNetworkInfo)

        // Then
        XCTAssertNil(publisher.initialValue)
    }

    func testGivenSubscribedInfoProvider_whenCarrierInfoChanges_itNotifiesSubscriber() throws {
        try XCTSkipIf(isIOS16OrAbove, "`CarrierInfo` is always nil on iOS 16+ — see testGivenIOS16OrAbove_itNeverNotifiesSubscriber")

        let expectation = expectation(description: "Notify `CarrierInfo` change")
        var info: CarrierInfo? = nil
        let publisher = CarrierInfoPublisher(networkInfo: availableCTTelephonyNetworkInfo)

        // Given
        publisher.publish {
            info = $0
            expectation.fulfill()
        }

        let newCarrierName: String = .mockRandom()
        let newISOCountryCode: String = .mockRandom()
        let newAllowsVOIP: Bool = .mockRandom()
        let newRadioAccessTechnology: String = [CTRadioAccessTechnologyGPRS, CTRadioAccessTechnologyEdge].randomElement()!

        // When
        availableCTTelephonyNetworkInfo.changeCarrier(
            newCarrierName: newCarrierName,
            newISOCountryCode: newISOCountryCode,
            newAllowsVOIP: newAllowsVOIP,
            newRadioAccessTechnology: newRadioAccessTechnology
        )

        // Then
        waitForExpectations(timeout: 1, handler: nil)

        XCTAssertEqual(info?.carrierName, newCarrierName)
        XCTAssertEqual(info?.carrierISOCountryCode, newISOCountryCode)
        XCTAssertEqual(info?.carrierAllowsVOIP, newAllowsVOIP)
        XCTAssertEqual(info?.radioAccessTechnology, .init(newRadioAccessTechnology))
    }

    func testGivenIOS16OrAbove_itProvidesNoInitialValue() throws {
        try XCTSkipIf(!isIOS16OrAbove, "This behavior only applies from iOS 16 onward")

        // Given
        let publisher = CarrierInfoPublisher(networkInfo: availableCTTelephonyNetworkInfo)

        // Then
        XCTAssertNil(publisher.initialValue, "`CarrierInfo` must be nil on iOS 16+ since `CTCarrier` is deprecated with no replacement")
    }

    func testGivenIOS16OrAbove_itNeverNotifiesSubscriber() throws {
        try XCTSkipIf(!isIOS16OrAbove, "This behavior only applies from iOS 16 onward")

        var receivedUpdate = false
        let publisher = CarrierInfoPublisher(networkInfo: availableCTTelephonyNetworkInfo)

        // Given
        publisher.publish { _ in receivedUpdate = true }

        // When
        availableCTTelephonyNetworkInfo.changeCarrier(
            newCarrierName: .mockRandom(),
            newISOCountryCode: .mockRandom(),
            newAllowsVOIP: .mockRandom(),
            newRadioAccessTechnology: CTRadioAccessTechnologyLTE
        )

        // Then
        XCTAssertFalse(receivedUpdate, "No update should be received on iOS 16+ as there is no subscription set up")
    }

    func testDifferentCarrierInfoRadioAccessTechnologies() {
        XCTAssertEqual(CarrierInfo.RadioAccessTechnology(CTRadioAccessTechnologyGPRS), .GPRS)
        XCTAssertEqual(CarrierInfo.RadioAccessTechnology(CTRadioAccessTechnologyEdge), .Edge)
        XCTAssertEqual(CarrierInfo.RadioAccessTechnology(CTRadioAccessTechnologyWCDMA), .WCDMA)
        XCTAssertEqual(CarrierInfo.RadioAccessTechnology(CTRadioAccessTechnologyHSDPA), .HSDPA)
        XCTAssertEqual(CarrierInfo.RadioAccessTechnology(CTRadioAccessTechnologyHSUPA), .HSUPA)
        XCTAssertEqual(CarrierInfo.RadioAccessTechnology(CTRadioAccessTechnologyCDMA1x), .CDMA1x)
        XCTAssertEqual(CarrierInfo.RadioAccessTechnology(CTRadioAccessTechnologyCDMAEVDORev0), .CDMAEVDORev0)
        XCTAssertEqual(CarrierInfo.RadioAccessTechnology(CTRadioAccessTechnologyCDMAEVDORevA), .CDMAEVDORevA)
        XCTAssertEqual(CarrierInfo.RadioAccessTechnology(CTRadioAccessTechnologyCDMAEVDORevB), .CDMAEVDORevB)
        XCTAssertEqual(CarrierInfo.RadioAccessTechnology(CTRadioAccessTechnologyeHRPD), .eHRPD)
        XCTAssertEqual(CarrierInfo.RadioAccessTechnology(CTRadioAccessTechnologyLTE), .LTE)
        XCTAssertEqual(CarrierInfo.RadioAccessTechnology("invalid"), .unknown)
    }
}

#endif
