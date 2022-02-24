/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

#if canImport(CoreTelephony)
import CoreTelephony

/*
A collection of mocks for different `CoreTelephony` types.
It follows the mocking conventions described in `FoundationMocks.swift`.
 */

class CTCarrierMock: CTCarrier {
    private let _carrierName: String?
    private let _isoCountryCode: String?
    private let _allowsVOIP: Bool

    init(carrierName: String, isoCountryCode: String, allowsVOIP: Bool) {
        _carrierName = carrierName
        _isoCountryCode = isoCountryCode
        _allowsVOIP = allowsVOIP
    }

    override var carrierName: String? { _carrierName }
    override var isoCountryCode: String? { _isoCountryCode }
    override var allowsVOIP: Bool { _allowsVOIP }
}

class CTTelephonyNetworkInfoMock: CTTelephonyNetworkInfo {
    private var _serviceCurrentRadioAccessTechnology: [String: String]?
    private var _serviceSubscriberCellularProviders: [String: CTCarrier]?

    init(
        serviceCurrentRadioAccessTechnology: [String: String],
        serviceSubscriberCellularProviders: [String: CTCarrier]
    ) {
        _serviceCurrentRadioAccessTechnology = serviceCurrentRadioAccessTechnology
        _serviceSubscriberCellularProviders = serviceSubscriberCellularProviders
    }

    func changeCarrier(
        newCarrierName: String,
        newISOCountryCode: String,
        newAllowsVOIP: Bool,
        newRadioAccessTechnology: String
    ) {
        _serviceCurrentRadioAccessTechnology = [
            "000001": newRadioAccessTechnology
        ]
        _serviceSubscriberCellularProviders = [
            "000001": CTCarrierMock(carrierName: newCarrierName, isoCountryCode: newISOCountryCode, allowsVOIP: newAllowsVOIP)
        ]

        if #available(iOS 12.0, *) {
            serviceSubscriberCellularProvidersDidUpdateNotifier?("000001")
        }
    }

    // MARK: - iOS 12+

    override var serviceCurrentRadioAccessTechnology: [String: String]? { _serviceCurrentRadioAccessTechnology }
    override var serviceSubscriberCellularProviders: [String: CTCarrier]? { _serviceSubscriberCellularProviders }

    // MARK: - Prior to iOS 12

    override var currentRadioAccessTechnology: String? { _serviceCurrentRadioAccessTechnology?.first?.value }
    override var subscriberCellularProvider: CTCarrier? { _serviceSubscriberCellularProviders?.first?.value }
}

#endif
