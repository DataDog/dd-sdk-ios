/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if canImport(CoreTelephony)
import CoreTelephony

/*
A collection of mocks for different `CoreTelephony` types.
It follows the mocking conventions described in `FoundationMocks.swift`.
 */

public class CTCarrierMock: CTCarrier {
    private let _carrierName: String?
    private let _isoCountryCode: String?
    private let _allowsVOIP: Bool

    public init(carrierName: String, isoCountryCode: String, allowsVOIP: Bool) {
        _carrierName = carrierName
        _isoCountryCode = isoCountryCode
        _allowsVOIP = allowsVOIP
    }

    override public var carrierName: String? { _carrierName }
    override public var isoCountryCode: String? { _isoCountryCode }
    override public var allowsVOIP: Bool { _allowsVOIP }
}

public class CTTelephonyNetworkInfoMock: CTTelephonyNetworkInfo {
    private var _serviceCurrentRadioAccessTechnology: [String: String]?
    private var _serviceSubscriberCellularProviders: [String: CTCarrier]?

    public init(
        serviceCurrentRadioAccessTechnology: [String: String],
        serviceSubscriberCellularProviders: [String: CTCarrier]
    ) {
        _serviceCurrentRadioAccessTechnology = serviceCurrentRadioAccessTechnology
        _serviceSubscriberCellularProviders = serviceSubscriberCellularProviders
    }

    public func changeCarrier(
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

        serviceSubscriberCellularProvidersDidUpdateNotifier?("000001")
    }

    override public var serviceCurrentRadioAccessTechnology: [String: String]? { _serviceCurrentRadioAccessTechnology }
    override public var serviceSubscriberCellularProviders: [String: CTCarrier]? { _serviceSubscriberCellularProviders }
}

#endif
