/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import CoreTelephony
#endif

/// An observer for `CarrierInfo` value.
internal typealias CarrierInfoObserver = ValueObserver

internal protocol CarrierInfoProviderType {
    var current: CarrierInfo? { get }

    /// Subscribes for `CarrierInfo` updates.
    func subscribe<Observer: CarrierInfoObserver>(_ subscriber: Observer) where Observer.ObservedValue == CarrierInfo?
}

/// Platform-agnostic carrier info provider. It wraps the platform-specific provider inside.
internal class CarrierInfoProvider: CarrierInfoProviderType {
    /// The `CarrierInfo` provider for the current platform.
    private let wrappedProvider: CarrierInfoProviderType

    convenience init() {
        #if os(iOS) && !targetEnvironment(macCatalyst)
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

#if os(iOS) && !targetEnvironment(macCatalyst)
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
            initialValue: CarrierInfo(
                networkInfo,
                service: networkInfo.serviceCurrentRadioAccessTechnology?.keys.first
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

            let carrierInfo = CarrierInfo(
                strongSelf.networkInfo,
                service: cellularProviderKey
            )

            // On iOS12+ `CarrierInfo` subscribers are notified on actual change to cellular provider.
            strongSelf.publisher.publishAsync(carrierInfo)
        }
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
            initialValue: CarrierInfo(networkInfo)
        )
    }

    var current: CarrierInfo? {
        let carrierInfo = CarrierInfo(networkInfo)

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
