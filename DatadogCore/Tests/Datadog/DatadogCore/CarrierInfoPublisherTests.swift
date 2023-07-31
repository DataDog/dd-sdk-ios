/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if canImport(CoreTelephony)

import XCTest
import CoreTelephony
import DatadogInternal
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

    func testGivenCellularServiceAvailableOnIOS12AndAbove_itProvidesInitialValue() {
        if #available(iOS 12, *) {
            // Given
            let publisher = iOS12CarrierInfoPublisher(networkInfo: availableCTTelephonyNetworkInfo)

            // Then
            XCTAssertEqual(publisher.initialValue?.carrierName, "Carrier")
            XCTAssertEqual(publisher.initialValue?.carrierISOCountryCode, "US")
            XCTAssertEqual(publisher.initialValue?.carrierAllowsVOIP, true)
        }
    }

    func testGivenCellularServiceUnAvailableOnIOS12AndAbove_itProvidesNoInitialValue() {
        if #available(iOS 12, *) {
            // Given
            let publisher = iOS12CarrierInfoPublisher(networkInfo: unavailableCTTelephonyNetworkInfo)

            // Then
            XCTAssertNil(publisher.initialValue)
        }
    }

    func testGivenCellularServiceUnavailableOnIOS11_whenReadingCurrentCarrierInfo_itReturnsNoValue() {
        // Given
        let reader = iOS11CarrierInfoReader(networkInfo: unavailableCTTelephonyNetworkInfo)

        // When
        var info: CarrierInfo? = nil
        reader.read(to: &info)

        // Then
        XCTAssertNil(info)
    }

    func testGivenSubscribediOS11CarrierInfoProvider_whenCarrierInfoChanges_itReadsNewValue() throws {
        // Given
        let reader = iOS11CarrierInfoReader(networkInfo: availableCTTelephonyNetworkInfo)

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

        var info: CarrierInfo? = nil
        reader.read(to: &info)

        // Then
        XCTAssertEqual(info?.carrierName, newCarrierName)
        XCTAssertEqual(info?.carrierISOCountryCode, newISOCountryCode)
        XCTAssertEqual(info?.carrierAllowsVOIP, newAllowsVOIP)
        XCTAssertEqual(info?.radioAccessTechnology, .init(newRadioAccessTechnology))
    }

    func testGivenSubscribediOS12CarrierInfoProvider_whenCarrierInfoChanges_itNotifiesSubscriber() throws {
        guard #available(iOS 12, *) else {
            return
        }

        let expectation = expectation(description: "Notify `CarrierInfo` change")
        var info: CarrierInfo? = nil
        let publisher = iOS12CarrierInfoPublisher(networkInfo: availableCTTelephonyNetworkInfo)

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
