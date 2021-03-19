/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

/// An observer for `TrackingConsent` value.
internal typealias TrackingConsentObserver = ValueObserver

/// Provides the current `TrackingConsent` value and notifies all subscribers on its change.
internal class ConsentProvider {
    private let publisher: ValuePublisher<TrackingConsent>

    init(initialConsent: TrackingConsent) {
        self.publisher = ValuePublisher(initialValue: initialConsent)
    }

    // MARK: - Consent Value

    /// The current value of`TrackingConsent`.
    var currentValue: TrackingConsent { publisher.currentValue }

    /// Sets the new value of `TrackingConsent` and notifies all subscribers.
    func changeConsent(to newValue: TrackingConsent) {
        // Synchronous update ensures that the new value of the consent will be applied immediately
        // to all data sent from the the same thread.
        publisher.publishSync(newValue)
    }

    // MARK: - Managing Subscribers

    func subscribe<Observer: TrackingConsentObserver>(_ subscriber: Observer) where Observer.ObservedValue == TrackingConsent {
        publisher.subscribe(subscriber)
    }
}
