/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if canImport(CoreTelephony)

import XCTest
import CoreTelephony
import DatadogInternal
import TestUtilities

@testable import DatadogCore

class CarrierInfoSourceTests: XCTestCase {
    /// Mock `CTTelephonyNetworkInfo` when user's cellular service provider is available.
    private let availableCTTelephonyNetworkInfo = CTTelephonyNetworkInfoMock(
        serviceCurrentRadioAccessTechnology: ["000001": CTRadioAccessTechnologyLTE],
        serviceSubscriberCellularProviders: ["000001": CTCarrierMock(carrierName: "Carrier", isoCountryCode: "US", allowsVOIP: true)]
    )
    /// Mock `CTTelephonyNetworkInfo` when user's cellular service provider is unavailable.
    private let unavailableCTTelephonyNetworkInfo = CTTelephonyNetworkInfoMock(
        serviceCurrentRadioAccessTechnology: [:],
        serviceSubscriberCellularProviders: [:]
    )

    func testGivenCellularServiceAvailable_itProvidesInitialValue() {
        // Given
        let source = CarrierInfoSource(networkInfo: availableCTTelephonyNetworkInfo)

        // Then
        XCTAssertEqual(source.initialValue?.carrierName, "Carrier")
        XCTAssertEqual(source.initialValue?.carrierISOCountryCode, "US")
        XCTAssertEqual(source.initialValue?.carrierAllowsVOIP, true)
    }

    func testGivenCellularServiceUnAvailable_itProvidesNoInitialValue() {
        // Given
        let source = CarrierInfoSource(networkInfo: unavailableCTTelephonyNetworkInfo)

        // Then
        XCTAssertNil(source.initialValue)
    }

    func testGivenSubscribedInfoProvider_whenCarrierInfoChanges_itNotifiesSubscriber() async throws {
        var info: CarrierInfo? = nil
        let source = CarrierInfoSource(networkInfo: availableCTTelephonyNetworkInfo)
        var iterator = source.values.makeAsyncIterator()

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
        info = await iterator.next() ?? nil

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
