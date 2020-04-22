/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import CoreTelephony

/// Network connection details specific to cellular radio access.
internal struct CarrierInfo {
    // swiftlint:disable identifier_name
    enum RadioAccessTechnology: String, Encodable, CaseIterable {
        case GPRS
        case Edge
        case WCDMA
        case HSDPA
        case HSUPA
        case CDMA1x
        case CDMAEVDORev0
        case CDMAEVDORevA
        case CDMAEVDORevB
        case eHRPD
        case LTE
        case unknown
    }
    // swiftlint:enable identifier_name

    let carrierName: String?
    let carrierISOCountryCode: String?
    let carrierAllowsVOIP: Bool
    let radioAccessTechnology: RadioAccessTechnology
}

internal protocol CarrierInfoProviderType {
    var current: CarrierInfo? { get }
}

extension CarrierInfo.RadioAccessTechnology {
    init(ctRadioAccessTechnologyConstant: String) {
        switch ctRadioAccessTechnologyConstant {
        case CTRadioAccessTechnologyGPRS: self = .GPRS
        case CTRadioAccessTechnologyEdge: self = .Edge
        case CTRadioAccessTechnologyWCDMA: self = .WCDMA
        case CTRadioAccessTechnologyHSDPA: self = .HSDPA
        case CTRadioAccessTechnologyHSUPA: self = .HSUPA
        case CTRadioAccessTechnologyCDMA1x: self = .CDMA1x
        case CTRadioAccessTechnologyCDMAEVDORev0: self = .CDMAEVDORev0
        case CTRadioAccessTechnologyCDMAEVDORevA: self = .CDMAEVDORevA
        case CTRadioAccessTechnologyCDMAEVDORevB: self = .CDMAEVDORevB
        case CTRadioAccessTechnologyeHRPD: self = .eHRPD
        case CTRadioAccessTechnologyLTE: self = .LTE
        default: self = .unknown
        }
    }
}

internal class CarrierInfoProvider: CarrierInfoProviderType {
    private let networkInfo: CTTelephonyNetworkInfo

    init(networkInfo: CTTelephonyNetworkInfo = CTTelephonyNetworkInfo()) {
        self.networkInfo = networkInfo
    }

    var current: CarrierInfo? {
        let carrier: CTCarrier?
        let radioTechnology: String?

        if #available(iOS 12, *) {
            guard let cellularProviderKey = networkInfo.serviceCurrentRadioAccessTechnology?.keys.first else {
                return nil
            }
            radioTechnology = networkInfo.serviceCurrentRadioAccessTechnology?[cellularProviderKey]
            carrier = networkInfo.serviceSubscriberCellularProviders?[cellularProviderKey]
        } else {
            radioTechnology = networkInfo.currentRadioAccessTechnology
            carrier = networkInfo.subscriberCellularProvider
        }

        guard let radioAccessTechnology = radioTechnology,
            let currentCTCarrier = carrier else {
                return nil
        }

        return CarrierInfo(
            carrierName: currentCTCarrier.carrierName,
            carrierISOCountryCode: currentCTCarrier.isoCountryCode,
            carrierAllowsVOIP: currentCTCarrier.allowsVOIP,
            radioAccessTechnology: .init(ctRadioAccessTechnologyConstant: radioAccessTechnology)
        )
    }
}
