/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

#if os(iOS)
import CoreTelephony
#endif

extension CarrierInfo.RadioAccessTechnology {
    init(_ radioAccessTechnology: String) {
        switch radioAccessTechnology {
        #if os(iOS) && !targetEnvironment(macCatalyst)
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
        #endif
        default: self = .unknown
        }
    }
}

/// Platform-agnostic carrier info provider. It wraps the platform-specific provider inside.
internal struct AnyCarrierInfoPublisher: ContextValuePublisher, ContextValueReader {
    var initialValue: CarrierInfo? { publisher.initialValue }

    private let publisher: AnyContextValuePublisher<CarrierInfo?>
    private let reader: AnyContextValueReader<CarrierInfo?>

    init<Publisher>(_ publisher: Publisher) where Publisher: ContextValuePublisher, Publisher: ContextValueReader, Publisher.Value == CarrierInfo? {
        self.publisher = publisher.eraseToAnyPublisher()
        self.reader = publisher.eraseToAnyReader()
    }

    init() {
        #if os(iOS)
        if #available(iOS 12.0, *) {
            self.init(iOS12CarrierInfoPublisher())
        } else {
            self.init(iOS11CarrierInfoReader())
        }
        #else
        self.init(NOPCarrierInfoPublisher())
        #endif
    }

    func read(_ receiver: ContextValueReceiver<CarrierInfo?>) {
        reader.read(receiver)
    }

    func publish(to receiver: @escaping ContextValueReceiver<CarrierInfo?>) {
        publisher.publish(to: receiver)
    }

    func cancel() {
        publisher.cancel()
    }
}

/// Dummy provider for platforms which doesn't support carrier info.
internal struct NOPCarrierInfoPublisher: ContextValuePublisher, ContextValueReader {
    let initialValue: CarrierInfo? = nil

    func read(_ receiver: ContextValueReceiver<CarrierInfo?>) {
        // no-op
    }

    func publish(to receiver: @escaping ContextValueReceiver<CarrierInfo?>) {
        // no-op
    }

    func cancel() {
        // no-op
    }
}

#if os(iOS)
/// Carrier info provider for iOS 12 and above.
/// It reads `CarrierInfo?` from `CTTelephonyNetworkInfo` only when `CTCarrier` has changed (e.g. when the SIM card was swapped).
@available(iOS 12, *)
internal final class iOS12CarrierInfoPublisher: ContextValuePublisher, ContextValueReader {
    let initialValue: CarrierInfo?

    private let networkInfo: CTTelephonyNetworkInfo

    init(networkInfo: CTTelephonyNetworkInfo = .init()) {
        self.networkInfo = networkInfo
        self.initialValue = CarrierInfo(networkInfo, service: networkInfo.serviceCurrentRadioAccessTechnology?.keys.first)
    }

    func read(_ receiver: ContextValueReceiver<CarrierInfo?>) {
        // no-op
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
    @available(iOS 12, *)
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

/// Carrier info provider for iOS 11.
/// It reads `CarrierInfo?` from `CTTelephonyNetworkInfo` each time.
internal final class iOS11CarrierInfoReader: ContextValuePublisher, ContextValueReader {
    let initialValue: CarrierInfo?

    private let networkInfo: CTTelephonyNetworkInfo

    init(networkInfo: CTTelephonyNetworkInfo = .init()) {
        self.networkInfo = networkInfo
        self.initialValue = CarrierInfo(networkInfo)
    }

    func read(_ receiver: ContextValueReceiver<CarrierInfo?>) {
        let info = CarrierInfo(networkInfo)
        receiver(info)
    }

    func publish(to receiver: @escaping ContextValueReceiver<CarrierInfo?>) {
        // no-op
    }

    func cancel() {
        // no-op
    }
}

extension CarrierInfo {
    init?(_ info: CTTelephonyNetworkInfo) {
        guard
            let radioTechnology = info.currentRadioAccessTechnology,
            let carrier = info.subscriberCellularProvider
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

#endif
