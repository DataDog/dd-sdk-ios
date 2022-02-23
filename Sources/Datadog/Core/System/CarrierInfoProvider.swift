/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

#if os(iOS)
import CoreTelephony
#endif

/// Network connection details specific to cellular radio access.
public struct CarrierInfo: Equatable {
    // swiftlint:disable identifier_name
    public enum RadioAccessTechnology: String, Codable, CaseIterable {
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

    /// The name of the user’s home cellular service provider.
    public let carrierName: String?
    /// The ISO country code for the user’s cellular service provider.
    public let carrierISOCountryCode: String?
    /// Indicates if the carrier allows making VoIP calls on its network.
    public let carrierAllowsVOIP: Bool
    /// The radio access technology used for cellular connection.
    public let radioAccessTechnology: RadioAccessTechnology
}

/// An observer for `CarrierInfo` value.
internal typealias CarrierInfoObserver = ValueObserver

internal protocol CarrierInfoProviderType {
    var current: CarrierInfo? { get }

    /// Subscribes for `CarrierInfo` updates.
    func subscribe<Observer: CarrierInfoObserver>(_ subscriber: Observer) where Observer.ObservedValue == CarrierInfo?
}

extension CarrierInfo.RadioAccessTechnology {
    init(ctRadioAccessTechnologyConstant: String) {
        switch ctRadioAccessTechnologyConstant {
        #if os(iOS)
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
internal class CarrierInfoProvider: CarrierInfoProviderType {
    /// The `CarrierInfo` provider for the current platform.
    private let wrappedProvider: CarrierInfoProviderType

    convenience init() {
        #if os(iOS)
        if #available(iOS 12.0, *) {
            self.init(wrappedProvider: iOS12CarrierInfoProvider(networkInfo: CTTelephonyNetworkInfo()))
        } else {
            self.init(wrappedProvider: iOS11CarrierInfoProvider(networkInfo: CTTelephonyNetworkInfo()))
        }
        #else
        self.init(
            wrappedProvider: NOPCarrierInfoProvider()
        )
        #endif
    }

    init(wrappedProvider: CarrierInfoProviderType) {
        self.wrappedProvider = wrappedProvider
    }

    var current: CarrierInfo? {
        wrappedProvider.current
    }

    func subscribe<Observer: CarrierInfoObserver>(_ subscriber: Observer) where Observer.ObservedValue == CarrierInfo? {
        wrappedProvider.subscribe(subscriber)
    }
}

/// Dummy provider for platforms which doesn't support carrier info.
internal struct NOPCarrierInfoProvider: CarrierInfoProviderType {
    var current: CarrierInfo? { return nil }
    func subscribe<Observer>(_ subscriber: Observer) where Observer: ValueObserver, Observer.ObservedValue == CarrierInfo? {}
}

#if os(iOS)
/// Carrier info provider for iOS 12 and above.
/// It reads `CarrierInfo?` from `CTTelephonyNetworkInfo` only when `CTCarrier` has changed (e.g. when the SIM card was swapped).
@available(iOS 12, *)
internal class iOS12CarrierInfoProvider: CarrierInfoProviderType {
    private let networkInfo: CTTelephonyNetworkInfo
    /// Publisher for notifying observers on `CarrierInfo` change.
    private let publisher: ValuePublisher<CarrierInfo?>

    init(networkInfo: CTTelephonyNetworkInfo) {
        self.networkInfo = networkInfo
        self.publisher = ValuePublisher(
            initialValue: iOS12CarrierInfoProvider.readCarrierInfo(
                from: networkInfo,
                cellularProviderKey: networkInfo.serviceCurrentRadioAccessTechnology?.keys.first
            )
        )

        // The `serviceSubscriberCellularProvidersDidUpdateNotifier` block object executes on the default priority
        // global dispatch queue when the user’s cellular provider information changes.
        // This occurs, for example, if a user swaps the device’s SIM card with one from another provider, while the app is running.
        // ref.: https://developer.apple.com/documentation/coretelephony/cttelephonynetworkinfo/3024512-servicesubscribercellularprovide
        networkInfo.serviceSubscriberCellularProvidersDidUpdateNotifier = { [weak self] cellularProviderKey in
            guard let strongSelf = self else {
                return
            }

            let carrierInfo = iOS12CarrierInfoProvider.readCarrierInfo(
                from: strongSelf.networkInfo,
                cellularProviderKey: cellularProviderKey
            )

            // On iOS12+ `CarrierInfo` subscribers are notified on actual change to cellular provider.
            strongSelf.publisher.publishAsync(carrierInfo)
        }
    }

    private static func readCarrierInfo(from networkInfo: CTTelephonyNetworkInfo, cellularProviderKey: String?) -> CarrierInfo? {
        guard let cellularProviderKey = cellularProviderKey,
           let radioTechnology = networkInfo.serviceCurrentRadioAccessTechnology?[cellularProviderKey],
           let carrier = networkInfo.serviceSubscriberCellularProviders?[cellularProviderKey] else {
            return nil // the service is not registered on any network
        }
        return CarrierInfo(
            carrierName: carrier.carrierName,
            carrierISOCountryCode: carrier.isoCountryCode,
            carrierAllowsVOIP: carrier.allowsVOIP,
            radioAccessTechnology: .init(ctRadioAccessTechnologyConstant: radioTechnology)
        )
    }

    var current: CarrierInfo? {
        publisher.currentValue
    }

    func subscribe<Observer>(_ subscriber: Observer) where Observer: ValueObserver, Observer.ObservedValue == CarrierInfo? {
        publisher.subscribe(subscriber)
    }
}

/// Carrier info provider for iOS 11.
/// It reads `CarrierInfo?` from `CTTelephonyNetworkInfo` each time.
internal class iOS11CarrierInfoProvider: CarrierInfoProviderType {
    private let networkInfo: CTTelephonyNetworkInfo
    /// Publisher for notifying observers on `CarrierInfo` change.
    private let publisher: ValuePublisher<CarrierInfo?>

    init(networkInfo: CTTelephonyNetworkInfo) {
        self.networkInfo = networkInfo
        self.publisher = ValuePublisher(
            initialValue: iOS11CarrierInfoProvider.readCarrierInfo(from: networkInfo)
        )
    }

    private static func readCarrierInfo(from networkInfo: CTTelephonyNetworkInfo) -> CarrierInfo? {
        guard let radioTechnology = networkInfo.currentRadioAccessTechnology,
              let carrier = networkInfo.subscriberCellularProvider else {
            return nil // the service is not registered on any network
        }
        return CarrierInfo(
            carrierName: carrier.carrierName,
            carrierISOCountryCode: carrier.isoCountryCode,
            carrierAllowsVOIP: carrier.allowsVOIP,
            radioAccessTechnology: .init(ctRadioAccessTechnologyConstant: radioTechnology)
        )
    }

    var current: CarrierInfo? {
        let carrierInfo = iOS11CarrierInfoProvider.readCarrierInfo(from: networkInfo)

        // On iOS11 `CarrierInfo` subscribers are notified as a side-effect of pulling the
        // current `CarrierInfo` value.
        publisher.publishAsync(carrierInfo)

        return carrierInfo
    }

    func subscribe<Observer>(_ subscriber: Observer) where Observer: ValueObserver, Observer.ObservedValue == CarrierInfo? {
        publisher.subscribe(subscriber)
    }
}
#endif
