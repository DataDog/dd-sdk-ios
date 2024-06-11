/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

#if os(iOS) && !targetEnvironment(macCatalyst) && !(swift(>=5.9) && os(visionOS))

import CoreTelephony

/// It reads `CarrierInfo?` from `CTTelephonyNetworkInfo` only when `CTCarrier` has changed (e.g. when the SIM card was swapped).
internal struct CarrierInfoPublisher: ContextValuePublisher {
    let initialValue: CarrierInfo?

    private let networkInfo: CTTelephonyNetworkInfo

    init(networkInfo: CTTelephonyNetworkInfo = .init()) {
        self.networkInfo = networkInfo
        self.initialValue = CarrierInfo(networkInfo, service: networkInfo.serviceCurrentRadioAccessTechnology?.keys.first)
    }

    func publish(to receiver: @escaping ContextValueReceiver<CarrierInfo?>) {
        // The `serviceSubscriberCellularProvidersDidUpdateNotifier` block object executes on the default priority
        // global dispatch queue when the user’s cellular provider information changes.
        // This occurs, for example, if a user swaps the device’s SIM card with one from another provider, while the app is running.
        // ref.: https://developer.apple.com/documentation/coretelephony/cttelephonynetworkinfo/3024512-servicesubscribercellularprovide
        networkInfo.serviceSubscriberCellularProvidersDidUpdateNotifier = { key in
            // On iOS12+ `CarrierInfo` subscribers are notified on actual change to cellular provider.
            let info = CarrierInfo(self.networkInfo, service: key)
            receiver(info)
        }
    }

    func cancel() {
        networkInfo.serviceSubscriberCellularProvidersDidUpdateNotifier = nil
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
