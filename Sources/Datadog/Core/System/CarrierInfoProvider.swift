/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import CoreTelephony

/// Network connection details specific to cellular radio access.
internal struct CarrierInfo: Equatable {
    // swiftlint:disable identifier_name
    enum RadioAccessTechnology: String, Codable, CaseIterable {
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

internal class CarrierInfoProvider: CarrierInfoProviderType {
    #if targetEnvironment(macCatalyst)
    let current: CarrierInfo? = nil
    func subscribe<Observer: CarrierInfoObserver>(_ subscriber: Observer) where Observer.ObservedValue == CarrierInfo? {}
    #else
    private let networkInfo: CTTelephonyNetworkInfo
    /// Publisher for notifying observers on `CarrierInfo` change.
    private let publisher: ValuePublisher<CarrierInfo?>

    init(networkInfo: CTTelephonyNetworkInfo = CTTelephonyNetworkInfo()) {
        self.networkInfo = networkInfo
        // Asynchronous `updatesModel` makes the `current` getter a non-blocking call.
        // This ensures that the value form `CarrierInfoProvider` can be obtained
        // as fast as possible and the eventual observers will be notified asynchronously.
        self.publisher = ValuePublisher(initialValue: nil, updatesModel: .asynchronous)
    }

    var current: CarrierInfo? {
        let carrier: CTCarrier?
        let radioTechnology: String?

        if #available(iOS 12, *) {
            guard let cellularProviderKey = networkInfo.serviceCurrentRadioAccessTechnology?.keys.first else {
                publisher.currentValue = nil
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
                publisher.currentValue = nil
                return nil
        }

        let nextValue = CarrierInfo(
            carrierName: currentCTCarrier.carrierName,
            carrierISOCountryCode: currentCTCarrier.isoCountryCode,
            carrierAllowsVOIP: currentCTCarrier.allowsVOIP,
            radioAccessTechnology: .init(ctRadioAccessTechnologyConstant: radioAccessTechnology)
        )

        // `CarrierInfo` subscribers are notified as a side-effect of retrieving the
        // current `CarrierInfo` value.
        publisher.currentValue = nextValue

        return nextValue
    }

    func subscribe<Observer: CarrierInfoObserver>(_ subscriber: Observer) where Observer.ObservedValue == CarrierInfo? {
        publisher.subscribe(subscriber)
    }
    #endif
}
