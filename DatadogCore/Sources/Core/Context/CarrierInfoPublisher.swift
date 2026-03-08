/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

#if os(iOS) && !targetEnvironment(macCatalyst) && !os(visionOS)

import CoreTelephony

/// Produces `CarrierInfo` updates via `AsyncStream` backed by `CTTelephonyNetworkInfo`.
/// A new value is emitted whenever the user's cellular provider changes (e.g. SIM swap).
internal struct CarrierInfoSource: ContextValueSource {
    let initialValue: CarrierInfo?
    let values: AsyncStream<CarrierInfo?>

    init(networkInfo: CTTelephonyNetworkInfo = .init()) {
        self.initialValue = CarrierInfo(networkInfo, service: networkInfo.serviceCurrentRadioAccessTechnology?.keys.first)

        self.values = AsyncStream { continuation in
            networkInfo.serviceSubscriberCellularProvidersDidUpdateNotifier = { key in
                let info = CarrierInfo(networkInfo, service: key)
                continuation.yield(info)
            }

            nonisolated(unsafe) let networkInfo = networkInfo
            continuation.onTermination = { _ in
                networkInfo.serviceSubscriberCellularProvidersDidUpdateNotifier = nil
            }
        }
    }
}

extension CarrierInfo {
    init?(_ info: CTTelephonyNetworkInfo, service key: String?) {
        guard let key = key,
           let radioTechnology = info.serviceCurrentRadioAccessTechnology?[key],
           let carrier = info.serviceSubscriberCellularProviders?[key]
        else {
            return nil // the service is not registered on any network
        }

        self.init(
            carrierName: carrier.carrierName,
            carrierISOCountryCode: carrier.isoCountryCode,
            carrierAllowsVOIP: carrier.allowsVOIP,
            radioAccessTechnology: .init(radioTechnology)
        )
    }
}

extension CarrierInfo.RadioAccessTechnology {
    init(_ radioAccessTechnology: String) {
        switch radioAccessTechnology {
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

#endif
