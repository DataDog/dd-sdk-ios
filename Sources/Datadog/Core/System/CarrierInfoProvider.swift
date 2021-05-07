/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import CoreTelephony

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
        #if !targetEnvironment(macCatalyst)
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

/// An interface for the target-specific carrier info provider.
internal protocol WrappedCarrierInfoProvider {
    var current: CarrierInfo? { get }
}

internal class CarrierInfoProvider: CarrierInfoProviderType {
    /// The `CarrierInfo` provider for the current platform.
    private let wrappedProvider: WrappedCarrierInfoProvider
    /// Publisher for notifying observers on `CarrierInfo` change.
    private let publisher: ValuePublisher<CarrierInfo?>

    convenience init() {
        #if targetEnvironment(macCatalyst)
            self.init(
                wrappedProvider: MacCatalystCarrierInfoProvider()
            )
        #else
            self.init(
                wrappedProvider: iOSCarrierInfoProvider(
                    networkInfo: CTTelephonyNetworkInfo()
                )
            )
        #endif
    }

    init(wrappedProvider: WrappedCarrierInfoProvider) {
        self.wrappedProvider = wrappedProvider
        self.publisher = ValuePublisher(initialValue: nil)
    }

    var current: CarrierInfo? {
        let nextValue = wrappedProvider.current
        // `CarrierInfo` subscribers are notified as a side-effect of retrieving the
        // current `CarrierInfo` value.
        publisher.publishAsync(nextValue)
        return nextValue
    }

    func subscribe<Observer: CarrierInfoObserver>(_ subscriber: Observer) where Observer.ObservedValue == CarrierInfo? {
        publisher.subscribe(subscriber)
    }
}

#if targetEnvironment(macCatalyst)

internal struct MacCatalystCarrierInfoProvider: WrappedCarrierInfoProvider {
    /// Carrier info is not supported on macCatalyst
    var current: CarrierInfo? { return nil }
}

#else

internal struct iOSCarrierInfoProvider: WrappedCarrierInfoProvider {
    let networkInfo: CTTelephonyNetworkInfo

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

#endif
